// The TeamSpeak voice tool on the player's own computer. Put in by the player's TSVPlayerInfo.
//  - Links to the RS2 Voice TeamSpeak plugin (TSVLink). While the plugin is linked and TeamSpeak is connected, the
//    game's voice keys talk on TeamSpeak instead of the game's voice chat; otherwise they are left to the game.
//    Squad voice is plain talk in the player's own TeamSpeak channel; the other channels whisper to exactly the players
//    who should hear.
//  - While a key is held it tells the plugin who should hear (by Steam ID) a few times a second, so proximity voice
//    follows people as they move.
//  - Ten times a second it tells the plugin where the camera is and where each proximity talker this player can hear
//    is standing, so their voice comes from that direction and fades with distance.
//  - Shows who is talking on TeamSpeak that this player can hear in the game's own voice pop-up on the left.
class TSVInteraction extends Interaction
    dependson(TSVRules)
    config(MutTSVoice_Client);

const MAX_TALKER_ROWS = 4; // the rows of the game's voice pop-up (ROHUDWidgetVOIPTalkers)
var config int      PluginPort;         // The plugin's local port (0: 25700)
var config bool     bDisableTalkerList; // Don't draw who is talking
var config bool     bDisableTeamSpeak;  // The player turned TeamSpeak voice off (mutate tsvoice off): every voice key uses
                                        // the game's voice chat and the plugin isn't linked. Stored as the negative: on by default

var TSVPlayerInfo   Info;
var TSVLink         Link;

var array<name>     KeyNames;           // keys bound to the game's voice commands...
var array<byte>     KeyChannels;        // ...and the channel each talks on (CH_CURRENT: the game's channel setting)
var float           KeysBuiltAt;        // when the key list was last read (bindings can change during play)

const KEYS_CHECK_TIME = 2.0;            // seconds between reads of the player's key bindings

var bool            bTSConnected;       // the plugin says TeamSpeak is connected to a server
var bool            bAnnouncedLink;
var name            HeldKey;
var byte            HeldKeyChannel;     // the channel the held key asks for (CH_CURRENT: the game's channel setting)
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
    KeysBuiltAt = Info.ToolOwner.WorldInfo.RealTimeSeconds;
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

    // Bindings changed in the options or with setbind during play are picked up within a couple of seconds
    if (Info != None && Info.ToolOwner != None && Info.ToolOwner.WorldInfo.RealTimeSeconds - KeysBuiltAt > KEYS_CHECK_TIME)
        BuildKeyMap();
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

// The channel picked with the game's Change Voice Channel key (ROPlayerController.CurrentVOIPChannel: public, team,
// squad, vehicle, proximity, command), as a TeamSpeak channel. Team when it can't be read.
function byte GameChannelSetting()
{
    local ROPlayerController ROPC;

    ROPC = (Info != None) ? ROPlayerController(Info.ToolOwner) : None;
    if (ROPC == None)
        return class'TSVRules'.const.CH_TEAM;
    return ChannelForGameSetting(ROPC.CurrentVOIPChannel);
}

function int GameSettingIndex()
{
    return (Info != None && ROPlayerController(Info.ToolOwner) != None) ? int(ROPlayerController(Info.ToolOwner).CurrentVOIPChannel) : -1;
}

static function byte ChannelForGameSetting(byte GameChannel)
{
    switch (GameChannel)
    {
        case 0: return class'TSVRules'.const.CH_ALL;       // EVOIP_Public
        case 1: return class'TSVRules'.const.CH_TEAM;      // EVOIP_Team
        case 2: return class'TSVRules'.const.CH_SQUAD;     // EVOIP_Squad: the player's TeamSpeak channel
        case 3: return class'TSVRules'.const.CH_VEHICLE;   // EVOIP_Vehicle
        case 4: return class'TSVRules'.const.CH_PROXIMITY; // EVOIP_Proximity
        case 5: return class'TSVRules'.const.CH_COMMAND;   // EVOIP_Command
    }
    return class'TSVRules'.const.CH_TEAM;
}

// Pressing Change Voice Channel while holding the main voice key moves the talk to the new channel at once
function FollowChannelSetting()
{
    local byte Ch;
    local name Key;

    if (HeldKey == 'None' || HeldKeyChannel != class'TSVRules'.const.CH_CURRENT)
        return;
    Ch = ResolveChannel(class'TSVRules'.const.CH_CURRENT);
    if (Ch == TalkChannel || Ch == class'TSVRules'.const.CH_NONE)
        return;
    Key = HeldKey;
    StopTalk();
    StartTalk(class'TSVRules'.const.CH_CURRENT, Key);
}

function StartTalk(byte Ch, name Key)
{
    HeldKey = Key;
    HeldKeyChannel = Ch;
    Gather();
    Ch = ResolveChannel(Ch);
    // For fault finding: which key, the channel it asks for, the game's Change Voice Channel setting, and what is used
    `log("[MutTSVoice] Talk: key "$Key$" asks "$HeldKeyChannel$", game channel setting "$GameSettingIndex()$", talking on "
        $class'TSVRules'.static.ChannelName(Ch)$(MyIndex == INDEX_NONE ? " (this player not found yet)" : ""));
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

// The game's main voice key talks on the channel the game's Change Voice Channel key (O) has picked, as in the game.
// Every key falls back as the game does for a channel this player can't talk on now (no vehicle, not a leader: team).
function byte ResolveChannel(byte Ch)
{
    local TSVRules.TSVPlayerState Me;

    if (Ch == class'TSVRules'.const.CH_CURRENT)
        Ch = GameChannelSetting();
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

    // Squad is plain talk in the TeamSpeak channel: no one to pick, unless enemies close by overhear it
    if (TalkChannel == class'TSVRules'.const.CH_NONE || MyIndex == INDEX_NONE)
        return;
    if (TalkChannel == class'TSVRules'.const.CH_SQUAD && !Info.bEnemiesOverhear)
        return;
    if (TalkChannel == class'TSVRules'.const.CH_SQUAD)
        Ids = OverhearersOf(MyIndex, TalkChannel);
    else
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

// The enemies close enough to overhear this talker (bEnemiesOverhear), for Squad talk: the channel hears it anyway
function array<string> OverhearersOf(int TalkerIndex, byte Ch)
{
    local array<string> Ids;
    local TSVRules.TSVRuleSettings S;
    local int i;

    S = Settings();
    for (i = 0; i < Seen.Length; i++)
    {
        if (i != TalkerIndex && Seen[i].Info.bPluginLinked
            && class'TSVRules'.static.Overhears(Seen[TalkerIndex].State, Seen[i].State, Ch, S))
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
    S.bEnemiesOverhear = Info.bEnemiesOverhear;
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
    FollowChannelSetting();
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
            // Proximity talkers, and talkers this player overhears (bEnemiesOverhear), come from where they stand
            if (i != MyIndex && Seen[i].State.bHasLocation
                && ((Seen[i].Info.VoiceChannel == class'TSVRules'.const.CH_PROXIMITY
                    && class'TSVRules'.static.CanHear(Seen[i].State, Seen[MyIndex].State, class'TSVRules'.const.CH_PROXIMITY, S))
                || class'TSVRules'.static.Overhears(Seen[i].State, Seen[MyIndex].State, Seen[i].Info.VoiceChannel, S)))
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

// TeamSpeak talkers this player hears (and the player themselves) show in the game's own voice pop-up on the left
// (ROHUDWidgetVOIPTalkers), in its next free rows after anyone on the game's voice chat (enemies on local voice are heard
// but not shown): the name in the game's HUD font,
// the channel under it in its plain font, in team colours with the same drop shadow, scaled with the HUD as it is.
event PostRender(Canvas C)
{
    local TSVRules.TSVRuleSettings S;
    local ROHUD H;
    local ROHUDWidgetVOIPTalkers W;
    local int i, Row;
    local bool bMe;

    if (bDisableTalkerList || !bTSConnected || C == None || Seen.Length == 0 || Info == None || Info.ToolOwner == None)
        return;
    H = ROHUD(Info.ToolOwner.myHUD);
    if (H == None || !H.bShowHUD)
        return;
    W = H.VOIPTalkersWidget;
    if (W == None)
        return;

    S = Settings();
    Row = Min(W.TalkerPRIs.Length, MAX_TALKER_ROWS);
    for (i = 0; i < Seen.Length && Row < MAX_TALKER_ROWS; i++)
    {
        if (Seen[i].Info == None || Seen[i].Info.VoiceChannel == 0 || Seen[i].Info.PRI == None)
            continue;
        bMe = (i == MyIndex);
        if (!bMe && (MyIndex == INDEX_NONE
            || !class'TSVRules'.static.CanHear(Seen[i].State, Seen[MyIndex].State, Seen[i].Info.VoiceChannel, S)))
            continue;
        // An enemy talking on local (proximity) voice is heard but not named
        if (!bMe && !ShowsTalker(Seen[i].State, Seen[MyIndex].State, Seen[i].Info.VoiceChannel))
            continue;
        DrawTalkerRow(C, W, Row, Seen[i].Info);
        Row++;
    }
}

// Whether a talker this player hears is shown in the voice pop-up: teammates always; a talker on another team (or with no
// team) only on All. An enemy on local voice, or one overheard on their own channel, is heard but not named.
static function bool ShowsTalker(TSVRules.TSVPlayerState Talker, TSVRules.TSVPlayerState Me, byte Channel)
{
    if (Channel == class'TSVRules'.const.CH_ALL)
        return true;
    if (Talker.Team < 2 && Talker.Team == Me.Team)
        return true;
    // Squad is the TeamSpeak channel: someone sitting in it is shown whatever their team
    return Channel == class'TSVRules'.const.CH_SQUAD && Talker.TSChannel != "" && Talker.TSChannel == Me.TSChannel;
}

// One row of the game's voice pop-up: the name and channel components of that row, as the game would draw them
function DrawTalkerRow(Canvas C, ROHUDWidgetVOIPTalkers W, int Row, TSVPlayerInfo Talker)
{
    local color Col;
    local int Team, GameChannel;
    local ROPlayerReplicationInfo ROPRI;

    ROPRI = ROPlayerReplicationInfo(Talker.PRI);
    Team = (Talker.PRI.Team != None) ? Talker.PRI.Team.TeamIndex : 255;
    // The game's colours: team colours, white for the commander on this player's team on team or command voice
    if (ROPRI != None && ROPRI.RoleInfo != None && ROPRI.RoleInfo.bIsTeamLeader && Team == Info.ToolOwner.GetTeamNum()
        && (Talker.VoiceChannel == class'TSVRules'.const.CH_TEAM || Talker.VoiceChannel == class'TSVRules'.const.CH_COMMAND))
        Col = W.CommanderTeamChatColor;
    else if (Team < 2)
        Col = W.TeamColor[Team];
    else
        Col = W.NoTeamColor;

    GameChannel = GameVoiceChannel(Talker.VoiceChannel);
    DrawComponentText(C, W, W.HUDComponents[Row * 2], Talker.PRI.PlayerName, Col);
    DrawComponentText(C, W, W.HUDComponents[Row * 2 + 1], (GameChannel >= 0) ? W.VOIPChannelStrings[GameChannel]
        : class'TSVRules'.static.ChannelName(Talker.VoiceChannel), Col);
}

// The game's channel names (ROHUDWidgetVOIPTalkers.VOIPChannelStrings: PUBLIC, TEAM, SQUAD, VEHICLE, ..., LOCAL,
// COMMAND) for a TeamSpeak voice channel, or -1 for none
static function int GameVoiceChannel(byte Channel)
{
    switch (Channel)
    {
        case class'TSVRules'.const.CH_ALL:       return 0;
        case class'TSVRules'.const.CH_TEAM:      return 1;
        case class'TSVRules'.const.CH_SQUAD:     return 2;
        case class'TSVRules'.const.CH_VEHICLE:   return 3;
        case class'TSVRules'.const.CH_PROXIMITY: return 6;
        case class'TSVRules'.const.CH_COMMAND:   return 7;
    }
    return -1;
}

// Text where a component of the widget sits, in its font and scale (as laid out for this screen size), with its shadow
function DrawComponentText(Canvas C, ROHUDWidget W, ROHUDWidgetComponent Comp, string Text, color Col)
{
    local float X, Y, SX, SY;

    if (Comp == None || Comp.TextFont == None || Text == "")
        return;
    X = W.CurrentX + Comp.CurX;
    Y = W.CurrentY + Comp.CurY;
    SX = Comp.TextScale * Comp.TextScaleX * Comp.ScaleX;
    SY = Comp.TextScale * Comp.TextScaleY * Comp.ScaleY;
    C.Font = Comp.TextFont;
    if (Comp.bDropShadow)
    {
        C.DrawColor = Comp.DropShadowColor;
        C.SetPos(X + Comp.DropShadowOffset.X, Y + Comp.DropShadowOffset.Y);
        C.DrawText(Text, false, SX, SY);
    }
    C.DrawColor = Col;
    C.SetPos(X, Y);
    C.DrawText(Text, false, SX, SY);
}

defaultproperties
{
    MyIndex=-1
}
