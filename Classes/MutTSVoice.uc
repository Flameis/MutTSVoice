// TeamSpeak 3 voice for Rising Storm 2: all, team, squad, vehicle, command and proximity voice through TeamSpeak instead
// of the game's own voice chat. Squad voice is plain talk in the player's own TeamSpeak channel.
//  - The server only keeps a TSVPlayerInfo for every player (Steam ID, TeamSpeak channel, the channel they talk on) and hands
//    out the settings. Nothing goes from the server to TeamSpeak.
//  - On each player's computer, TSVInteraction talks to the RS2 Voice TeamSpeak plugin over a local connection: it
//    takes the game's voice keys, works out who should hear (TSVRules) and tells the plugin who to whisper to and where
//    nearby talkers stand, so proximity voice comes from the right direction and fades with distance.
//  - Players without the plugin keep the game's own voice chat.
class MutTSVoice extends ROMutator
    config(MutTSVoice_Server);

var config float    ProximityRangeMeters;       // How far proximity voice carries, in meters (0: 75, like the game)
var config bool     bLetDeadTalkToLiving;       // Dead players can be heard by living ones (off: dead hear dead only)
var config bool     bProximitySameTeamOnly;     // Proximity voice only reaches your own team (off: enemies nearby hear you)
var config string   TeamSpeakAddress;           // Shown to players: the TeamSpeak server to join
var config string   TeamSpeakChannel;           // Shown to players: where to sit while playing (Squad voice is your own channel)

var array<TSVPlayerInfo> Infos;

function PostBeginPlay()
{
    super.PostBeginPlay();
    SetTimer(1.0, true, 'CheckInfos');
    `log("[MutTSVoice] active");
}

function float GetProximityRange()
{
    return ((ProximityRangeMeters > 0) ? ProximityRangeMeters : 75.0) * 50.0;
}

function NotifyLogin(Controller NewPlayer)
{
    super.NotifyLogin(NewPlayer);
    if (PlayerController(NewPlayer) != None)
        InfoFor(PlayerController(NewPlayer));
}

// Every player has an info and every info has a player. NotifyLogin is the quick path; this catches the rest
// (players already in when the mutator started, a player whose PRI was replaced).
function CheckInfos()
{
    local PlayerController PC;
    local int i;

    for (i = Infos.Length - 1; i >= 0; i--)
    {
        if (Infos[i] == None || Infos[i].bDeleteMe || Infos[i].Owner == None || Infos[i].Owner.bDeleteMe)
        {
            if (Infos[i] != None && !Infos[i].bDeleteMe)
                Infos[i].Destroy();
            Infos.Remove(i, 1);
        }
        else if (Infos[i].PRI != PlayerController(Infos[i].Owner).PlayerReplicationInfo)
        {
            Infos[i].PRI = PlayerController(Infos[i].Owner).PlayerReplicationInfo;
        }
    }

    foreach WorldInfo.AllControllers(class'PlayerController', PC)
    {
        if (PC.PlayerReplicationInfo != None && !PC.PlayerReplicationInfo.bBot && !PC.bDemoOwner)
            InfoFor(PC);
    }
}

function TSVPlayerInfo InfoFor(PlayerController PC)
{
    local TSVPlayerInfo NewInfo;
    local int i;

    for (i = 0; i < Infos.Length; i++)
    {
        if (Infos[i] != None && Infos[i].Owner == PC)
            return Infos[i];
    }
    if (PC.PlayerReplicationInfo == None)
        return None;
    NewInfo = Spawn(class'TSVPlayerInfo', PC);
    if (NewInfo != None)
    {
        NewInfo.Setup(self, PC);
        Infos.AddItem(NewInfo);
    }
    return NewInfo;
}

function UpdateSettings()
{
    local int i;

    for (i = 0; i < Infos.Length; i++)
    {
        if (Infos[i] != None)
            Infos[i].CopySettings();
    }
}

// ====================================================
// Commands
// ====================================================

function bool IsAdmin(PlayerController PC)
{
    return PC != None && (WorldInfo.NetMode == NM_Standalone || PC.IsLocalPlayerController()
        || (PC.PlayerReplicationInfo != None && PC.PlayerReplicationInfo.bAdmin));
}

function Mutate(string MutateString, PlayerController PC)
{
    local array<string> Args;

    Args = SplitString(MutateString, " ", true);
    if (Args.Length > 0 && Locs(Args[0]) == "tsvoice")
    {
        Args.Remove(0, 1);
        TSVoiceCommand(Args, PC);
        return;
    }
    super.Mutate(MutateString, PC);
}

function TSVoiceCommand(array<string> Args, PlayerController PC)
{
    local string Sub;

    if (PC == None)
        return;
    Sub = (Args.Length > 0) ? Locs(Args[0]) : "";

    switch (Sub)
    {
        case "":
        case "status":
            ShowStatus(PC, InfoFor(PC));
            return;

        case "who":
            ShowWho(PC);
            return;

        case "on":
        case "off":
            if (InfoFor(PC) != None)
                InfoFor(PC).ClientSetEnabled(Sub == "on");
            return;

        case "help":
        default:
            Say(PC, "mutate tsvoice: your TeamSpeak voice status | mutate tsvoice on / off: use TeamSpeak for your voice keys or not"
                $" | mutate tsvoice who: who has the plugin and which TeamSpeak channel they are in");
            return;
    }
}

function ShowStatus(PlayerController PC, TSVPlayerInfo I)
{
    if (TeamSpeakAddress != "")
        Say(PC, "TeamSpeak: "$TeamSpeakAddress$(TeamSpeakChannel != "" ? ", "$TeamSpeakChannel : ""));
    if (I == None)
        return;
    if (!I.bPluginLinked)
        Say(PC, "Your plugin: not linked, your voice keys use the game's voice chat (mutate tsvoice on / off switches TeamSpeak voice)");
    else
        Say(PC, "Your plugin: linked, your voice keys talk on TeamSpeak. Squad voice goes to your TeamSpeak channel"
            $(I.TSChannelName != "" ? " ("$I.TSChannelName$")" : ""));
}

function ShowWho(PlayerController PC)
{
    local int i, Linked;
    local string Line;

    for (i = 0; i < Infos.Length; i++)
    {
        if (Infos[i] == None || Infos[i].PRI == None)
            continue;
        if (Infos[i].bPluginLinked)
            Linked++;
        Line = Infos[i].PlayerNameOf()$": "$(Infos[i].bPluginLinked ? "plugin linked" : "no plugin");
        if (Infos[i].TSChannelName != "")
            Line $= ", in "$Infos[i].TSChannelName;
        Say(PC, Line);
    }
    Say(PC, Linked$" of "$Infos.Length$" players are on TeamSpeak voice");
}
function Say(PlayerController PC, string Msg)
{
    PC.ClientMessage("[TS Voice] "$Msg);
}

defaultproperties
{
}
