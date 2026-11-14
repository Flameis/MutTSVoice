// The TeamSpeak voice tool on the player's own computer. Put in by the player's TSVPlayerInfo.
//  - Links to the RS2 Voice TeamSpeak plugin (TSVLink). While the plugin is linked and TeamSpeak is connected, the
//    game's voice keys talk on TeamSpeak instead of the game's voice chat; otherwise they are left to the game.
//    Squad voice is plain talk in the player's own TeamSpeak channel; the other channels whisper to exactly the players
//    who should hear.
//  - While a key is held it tells the plugin who should hear (by Steam ID) a few times a second, so proximity voice
//    follows people as they move.
//  - Ten times a second it tells the plugin where the camera is and where each proximity talker this player can hear
//    is standing, so their voice comes from that direction and fades with distance.
//  - Draws a short list of who is talking on TeamSpeak that this player can hear.
class TSVInteraction extends Interaction
    dependson(TSVRules)
    config(MutTSVoice_Client);

var config int      PluginPort;         // The plugin's local port (0: 25700)
var config bool     bDisableTalkerList; // Don't draw who is talking
var config bool     bDisableTeamSpeak;  // The player turned TeamSpeak voice off (mutate tsvoice off): every voice key uses
                                        // the game's voice chat and the plugin isn't linked. Stored as the negative: on by default

var TSVPlayerInfo   Info;
var TSVLink         Link;

var array<name>     KeyNames;           // keys bound to the game's voice commands...
var array<byte>     KeyChannels;        // ...and the channel each talks on (CH_CURRENT: the game's channel setting)

var bool            bTSConnected;       // the plugin says TeamSpeak is connected to a server
var bool            bAnnouncedLink;
var name            HeldKey;
var byte            TalkChannel;
var float           TargetsAge;
var string          LastTargets;

// This frame's players, built by Gather()
struct TSVSeen
{
    var TSVPlayerInfo Info;
    var TSVRules.TSVPlayerState State;
};
var array<TSVSeen>  Seen;
var int             MyIndex;
var array<Actor>    SeenVehicles;       // VehicleKey is 3000 + the index in here

// ====================================================
// Start and stop
// ====================================================

function Start()
{
    if (PluginPort <= 0)
        PluginPort = 25700;
    HeldKey = 'None';
    BuildKeyMap();
    if (!bDisableTeamSpeak)
        OpenLink();
}

function Stop()
{
    CloseLink();
}

function OpenLink()
{
    if (Link != None || Info == None || Info.ToolOwner == None)
        return;
    Link = Info.ToolOwner.Spawn(class'TSVLink');
    if (Link != None)
    {
        Link.Tool = self;
        Link.Connect(PluginPort);
    }
}

// Closing the link makes the plugin give the microphone back
function CloseLink()
{
    StopTalk();
    if (bTSConnected && Info != None)
        Info.ServerSetPluginLinked(false);
    bTSConnected = false;
    if (Link != None)
        Link.CloseLink();
    Link = None;
}

// mutate tsvoice on / off, saved on this computer
function SetEnabled(bool bOn)
{
    bDisableTeamSpeak = !bOn;
    SaveConfig();
    if (bOn)
    {
        bAnnouncedLink = false;
        OpenLink();
        Message("TeamSpeak voice on. Your voice keys will talk on TeamSpeak once the plugin is linked.");
    }
    else
    {
        CloseLink();
        Message("TeamSpeak voice off. Your voice keys use the game's voice chat. Turn it back on with: mutate tsvoice on");
    }
}

// ====================================================
// The link
// ====================================================

function LinkOpened()
{
    Send("HELLO 1 "$Info.SteamId);
    Send("CFG "$int(Info.ProximityRange / 50.0));
}

function LinkClosed()
{
    StopTalk();
    if (bTSConnected && Info != None)
        Info.ServerSetPluginLinked(false);
    bTSConnected = false;
}

function HandleLine(string Line)
{
    local array<string> A;
    local string Rest;

    A = SplitString(Line, " ", true);
    if (A.Length == 0)
        return;
    if (Caps(A[0]) == "TS" || Caps(A[0]) == "CHAN")
        `log("[MutTSVoice] Plugin: "$Line);
    switch (Caps(A[0]))
    {
        // TS <1|0>: TeamSpeak connected to a server or not
        case "TS":
            SetTSConnected(A.Length > 1 && A[1] == "1");
            break;
        // CHAN <id> <name>: the TeamSpeak channel this player sits in (Squad voice)
        case "CHAN":
            if (A.Length > 1)
                Info.ServerSetTSChannel(A[1], (A.Length > 2) ? Mid(Line, Len(A[0]) + Len(A[1]) + 2) : "");
            break;
        // MSG <text>: show the player a message from the plugin
        case "MSG":
            Rest = Mid(Line, 4);
            Message(Rest);
            break;
    }
}

function SetTSConnected(bool bNow)
{
    if (bNow == bTSConnected)
        return;
    bTSConnected = bNow;
    if (!bNow)
        StopTalk();
    Info.ServerSetPluginLinked(bNow);
    if (bNow && !bAnnouncedLink)
    {
        bAnnouncedLink = true;
        Message("Linked to TeamSpeak. Your voice keys now talk on TeamSpeak; Squad voice goes to your TeamSpeak channel.");
    }
    else if (!bNow)
    {
        Message("TeamSpeak disconnected. Your voice keys use the game's voice chat again.");
    }
}

function Send(string Line)
{
    if (Link != None)
        Link.Send(Line);
}

function bool IsActive()
{
    return !bDisableTeamSpeak && Link != None && Link.IsConnected() && bTSConnected;
}

function Message(string Msg)
{
    if (Info != None && Info.ToolOwner != None)
        Info.ToolOwner.ClientMessage("[TS Voice] "$Msg);
}


// ====================================================
// Keys
// ====================================================

// The keys bound to the game's voice commands. A key is usually bound to a named command ("CapsLock" to
// "Voice_Chat"), and that name to the real command ("StartVoiceChat | OnRelease StopVoiceChat").
function BuildKeyMap()
{
    local PlayerInput Inp;
    local array<name> Aliases;
    local array<byte> AliasChannels;
    local int i, Found;
    local byte Ch;

    KeyNames.Length = 0;
    KeyChannels.Length = 0;
    if (Info == None || Info.ToolOwner == None || Info.ToolOwner.PlayerInput == None)
        return;
    Inp = Info.ToolOwner.PlayerInput;

    for (i = 0; i < Inp.Bindings.Length; i++)
    {
        Ch = class'TSVRules'.static.ChannelForCommand(Inp.Bindings[i].Command);
        if (Ch != class'TSVRules'.const.CH_NONE)
        {
            Aliases.AddItem(Inp.Bindings[i].Name);
            AliasChannels.AddItem(Ch);
        }
    }
    for (i = 0; i < Inp.Bindings.Length; i++)
    {
        if (Inp.Bindings[i].Control || Inp.Bindings[i].Shift || Inp.Bindings[i].Alt)
            continue;
        Found = Aliases.Find(name(Inp.Bindings[i].Command));
        if (Found != INDEX_NONE)
            AddKey(Inp.Bindings[i].Name, AliasChannels[Found]);
        else
        {
            Ch = class'TSVRules'.static.ChannelForCommand(Inp.Bindings[i].Command);
            if (Ch != class'TSVRules'.const.CH_NONE)
                AddKey(Inp.Bindings[i].Name, Ch);
        }
    }
}

function AddKey(name Key, byte Ch)
{
    if (Key == 'None' || Key == '---' || KeyNames.Find(Key) != INDEX_NONE)
        return;
    KeyNames.AddItem(Key);
    KeyChannels.AddItem(Ch);
}

function byte ChannelForKey(name Key)
{
    local int i;

    i = KeyNames.Find(Key);
    return (i != INDEX_NONE) ? KeyChannels[i] : byte(class'TSVRules'.const.CH_NONE);
}

function bool InputKey(int ControllerId, name Key, EInputEvent EventType, optional float AmountDepressed = 1.f, optional bool bGamepad)
{
    local byte Ch;

    // The key that is talking now: its repeats and its release are ours
    if (HeldKey != 'None' && Key == HeldKey)
    {
        if (EventType == IE_Released)
            StopTalk();
        return true;
    }
    if (EventType != IE_Pressed || !IsActive() || IsTyping())
        return false;

    Ch = ChannelForKey(Key);
    if (Ch == class'TSVRules'.const.CH_NONE)
        return false;
    if (HeldKey == 'None')
        StartTalk(Ch, Key);
    return true;
}

function bool IsTyping()
{
    local LocalPlayer LP;

    LP = (Info != None && Info.ToolOwner != None) ? LocalPlayer(Info.ToolOwner.Player) : None;
    return LP != None && LP.ViewportClient != None && LP.ViewportClient.ViewportConsole != None
        && (LP.ViewportClient.ViewportConsole.IsInState('Typing') || LP.ViewportClient.ViewportConsole.IsInState('Open'));
}

// ====================================================
// Talking
// ====================================================

function StartTalk(byte Ch, name Key)
{
    HeldKey = Key;
    Gather();
    Ch = ResolveChannel(Ch);
    if (Ch == class'TSVRules'.const.CH_NONE)
        return; // the key is still held (and its release is ours), but nothing is said
    TalkChannel = Ch;
    Info.VoiceChannel = Ch; // shown at once on this computer; the server sends it to everyone
    Info.ServerSetVoice(Ch);
    LastTargets = "";
    SendTargets();
    Send("PTT 1 "$Ch);
}

function StopTalk()
{
    if (HeldKey == 'None')
        return;
    if (TalkChannel != class'TSVRules'.const.CH_NONE)
    {
        Send("PTT 0");
        Info.VoiceChannel = 0;
        Info.ServerSetVoice(0);
    }
    HeldKey = 'None';
    TalkChannel = class'TSVRules'.const.CH_NONE;
}

// The game's main voice key is TeamSpeak's own push-to-talk (the player's channel), whatever the game's channel setting.
// The other keys fall back as the game does for a channel this player can't talk on now (no vehicle, not a leader: team).
function byte ResolveChannel(byte Ch)
{
    local TSVRules.TSVPlayerState Me;

    if (Ch == class'TSVRules'.const.CH_CURRENT)
        Ch = class'TSVRules'.const.CH_SQUAD; // the main voice key is always TeamSpeak's own: talk in your channel
    if (MyIndex == INDEX_NONE)
        return Ch;
    Me = Seen[MyIndex].State;

    switch (Ch)
    {
        case class'TSVRules'.const.CH_VEHICLE:
            return (Me.VehicleKey != 0) ? Ch : byte(class'TSVRules'.const.CH_TEAM);
        case class'TSVRules'.const.CH_COMMAND:
            return Me.bLeader ? Ch : byte(class'TSVRules'.const.CH_TEAM);
    }
    return Ch;
}

// Who should hear this player now, by Steam ID. Sent in short lines; only when it changed or every second.
function SendTargets()
{
    local array<string> Ids;
    local string All, Line;
    local int i, n;

    // Squad is plain talk in the TeamSpeak channel: no one to pick
    if (TalkChannel == class'TSVRules'.const.CH_NONE || TalkChannel == class'TSVRules'.const.CH_SQUAD || MyIndex == INDEX_NONE)
        return;
    Ids = TargetsFor(MyIndex, TalkChannel);
    for (i = 0; i < Ids.Length; i++)
        All $= Ids[i]$" ";
    if (All == LastTargets && TargetsAge < 1.0)
        return;
    LastTargets = All;
    TargetsAge = 0;

    Send("TGT_BEGIN "$TalkChannel);
    for (i = 0; i < Ids.Length; i++)
    {
        Line $= (n > 0 ? " " : "")$Ids[i];
        if (++n == 8)
        {
            Send("TGT "$Line);
            Line = "";
            n = 0;
        }
    }
    if (n > 0)
        Send("TGT "$Line);
    Send("TGT_END");
}

function array<string> TargetsFor(int TalkerIndex, byte Ch)
{
    local array<string> Ids;
    local TSVRules.TSVRuleSettings S;
    local int i;

    S = Settings();
    for (i = 0; i < Seen.Length; i++)
    {
        if (i != TalkerIndex && Seen[i].Info.bPluginLinked
            && class'TSVRules'.static.CanHear(Seen[TalkerIndex].State, Seen[i].State, Ch, S))
            Ids.AddItem(Seen[i].State.SteamId);
    }
    return Ids;
}

function TSVRules.TSVRuleSettings Settings()
{
    local TSVRules.TSVRuleSettings S;

    S.ProximityRange = Info.ProximityRange;
    S.bLetDeadTalkToLiving = Info.bLetDeadTalkToLiving;
    S.bProximitySameTeamOnly = Info.bProximitySameTeamOnly;
    return S;
}

// ====================================================
// Every tenth of a second (driven by the info's timer)
// ====================================================

function Frame(float DeltaTime)
{
    local vector CamLoc, X, Y, Z;
    local rotator CamRot;
    local TSVRules.TSVRuleSettings S;
    local int i;

    if (!IsActive())
        return;
    Gather();

    TargetsAge += DeltaTime;
    if (TalkChannel != class'TSVRules'.const.CH_NONE)
        SendTargets();

    // Where this player listens from, and where the proximity talkers they can hear stand
    Info.ToolOwner.GetPlayerViewPoint(CamLoc, CamRot);
    GetAxes(CamRot, X, Y, Z);
    Send("LIS "$int(CamLoc.X)@int(CamLoc.Y)@int(CamLoc.Z)@F3(X.X)@F3(X.Y)@F3(X.Z)@F3(Z.X)@F3(Z.Y)@F3(Z.Z));
    if (MyIndex != INDEX_NONE)
    {
        S = Settings();
        for (i = 0; i < Seen.Length; i++)
        {
            if (i != MyIndex && Seen[i].Info.VoiceChannel == class'TSVRules'.const.CH_PROXIMITY && Seen[i].State.bHasLocation
                && class'TSVRules'.static.CanHear(Seen[i].State, Seen[MyIndex].State, class'TSVRules'.const.CH_PROXIMITY, S))
            {
                Send("POS "$Seen[i].State.SteamId@int(Seen[i].State.Location.X)@int(Seen[i].State.Location.Y)@int(Seen[i].State.Location.Z));
            }
        }
    }
    Send("END");
}

static function string F3(float F)
{
    return string(float(int(F * 1000.0)) / 1000.0);
}

// Everyone with an info, as the rules see them
function Gather()
{
    local TSVPlayerInfo I;
    local TSVSeen Entry;
    local Pawn P;
    local array<Pawn> Pawns;
    local PlayerReplicationInfo MyPRI;

    Seen.Length = 0;
    SeenVehicles.Length = 0;
    MyIndex = INDEX_NONE;
    if (Info == None || Info.ToolOwner == None)
        return;
    MyPRI = Info.ToolOwner.PlayerReplicationInfo;

    foreach Info.ToolOwner.WorldInfo.AllPawns(class'Pawn', P)
    {
        if (P.PlayerReplicationInfo != None && P.Health > 0 && !P.bDeleteMe)
            Pawns.AddItem(P);
    }

    foreach Info.ToolOwner.DynamicActors(class'TSVPlayerInfo', I)
    {
        if (I.bDeleteMe || I.PRI == None || I.SteamId == "")
            continue;
        Entry.Info = I;
        Entry.State = MakeState(I, Pawns);
        if (I.PRI == MyPRI)
            MyIndex = Seen.Length;
        Seen.AddItem(Entry);
    }
}

function TSVRules.TSVPlayerState MakeState(TSVPlayerInfo PInfo, array<Pawn> Pawns)
{
    local TSVRules.TSVPlayerState S;
    local ROPlayerReplicationInfo ROPRI;
    local ROTeamInfo TI;
    local Pawn P;
    local Vehicle V;
    local int i;

    S.SteamId = PInfo.SteamId;
    S.TSChannel = PInfo.TSChannel;
    ROPRI = ROPlayerReplicationInfo(PInfo.PRI);
    if (PInfo.PRI.Team != None && PInfo.PRI.Team.TeamIndex < 2 && !PInfo.PRI.bOnlySpectator)
        S.Team = PInfo.PRI.Team.TeamIndex;
    if (ROPRI == None)
        return S;

    S.Squad = ROPRI.SquadIndex;
    S.bLeader = ROPRI.bIsSquadLeader || (ROPRI.RoleInfo != None && ROPRI.RoleInfo.bIsTeamLeader);
    S.bDead = ROPRI.bDead;

    for (i = 0; i < Pawns.Length; i++)
    {
        if (Pawns[i].PlayerReplicationInfo == PInfo.PRI)
        {
            P = Pawns[i];
            break;
        }
    }
    if (P != None)
    {
        S.bHasLocation = true;
        S.Location = P.Location;
        S.bDead = false;
    }
    else if (!S.bDead && S.Team < 2 && ROTeamInfo(PInfo.PRI.Team) != None)
    {
        // Not near enough for the game to send their soldier, but a teammate: the map's team positions
        TI = ROTeamInfo(PInfo.PRI.Team);
        S.Location = TI.GetTeamLocationVector(ROPRI.TeamPRIArrayIndex);
        S.bHasLocation = !IsZero(S.Location);
    }

    // The same vehicle: the game's helicopter and transport slots, or the same vehicle seen here
    if (ROPRI.TeamHelicopterArrayIndex != 255)
        S.VehicleKey = 1000 + ROPRI.TeamHelicopterArrayIndex;
    else if (ROPRI.TeamTransportArrayIndex != 255)
        S.VehicleKey = 2000 + ROPRI.TeamTransportArrayIndex;
    else if (P != None)
    {
        V = Vehicle(P);
        if (ROWeaponPawn(V) != None)
            V = ROWeaponPawn(V).MyVehicle;
        if (V != None && ROTurret(P) == None)
        {
            i = SeenVehicles.Find(V);
            if (i == INDEX_NONE)
            {
                i = SeenVehicles.Length;
                SeenVehicles.AddItem(V);
            }
            S.VehicleKey = 3000 + i;
        }
    }
    return S;
}

// ====================================================
// Who is talking
// ====================================================

event PostRender(Canvas C)
{
    local TSVRules.TSVRuleSettings S;
    local float X, Y, XL, YL;
    local int i;
    local bool bMe, bHeader;
    local string Line;

    if (bDisableTalkerList || !bTSConnected || C == None || Seen.Length == 0)
        return;

    S = Settings();
    C.Font = class'Engine'.static.GetSmallFont();
    C.TextSize("Ag", XL, YL);
    X = C.ClipX * 0.80;
    Y = C.ClipY * 0.30;

    for (i = 0; i < Seen.Length; i++)
    {
        if (Seen[i].Info == None || Seen[i].Info.VoiceChannel == 0 || Seen[i].Info.PRI == None)
            continue;
        bMe = (i == MyIndex);
        if (!bMe && (MyIndex == INDEX_NONE
            || !class'TSVRules'.static.CanHear(Seen[i].State, Seen[MyIndex].State, Seen[i].Info.VoiceChannel, S)))
            continue;
        if (!bHeader)
        {
            bHeader = true;
            C.SetDrawColor(200, 200, 200, 200);
            C.SetPos(X, Y);
            C.DrawText("TeamSpeak");
            Y += YL;
        }
        Line = Seen[i].Info.PRI.PlayerName$" ("$class'TSVRules'.static.ChannelName(Seen[i].Info.VoiceChannel)$")";
        if (bMe)
            C.SetDrawColor(120, 220, 120, 230);
        else
            C.SetDrawColor(255, 255, 255, 230);
        C.SetPos(X, Y);
        C.DrawText(Line);
        Y += YL;
    }
}

defaultproperties
{
    MyIndex=-1
}
