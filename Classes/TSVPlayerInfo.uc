// One per player, made by MutTSVoice on the server and seen by everyone. It carries what the other game clients need
// to work out who hears this player on TeamSpeak: their Steam ID (the TeamSpeak plugin finds the player's TeamSpeak
// client by it), the TeamSpeak channel they sit in (Squad voice), which voice channel they are talking on, and whether
// their plugin is linked. On the owning player's own computer it also puts in the voice tool (TSVInteraction).
class TSVPlayerInfo extends ReplicationInfo;

// ---- Everyone
var PlayerReplicationInfo PRI;
var string  SteamId;
var string  TSChannel;      // TeamSpeak channel ID ("" when not known)
var string  TSChannelName;  // and its name, for tsvoice who
var byte    VoiceChannel;   // TSVRules channel while talking on TeamSpeak, 0 when silent
var bool    bPluginLinked;  // the player's TeamSpeak plugin is linked to their game

// ---- The owner only: the server's settings
var float   ProximityRange;
var bool    bLetDeadTalkToLiving;
var bool    bProximitySameTeamOnly;
var string  TeamSpeakAddress;
var string  TeamSpeakChannel;

// ---- Local
var MutTSVoice           Mut;   // server only
var TSVInteraction       Tool;  // owner's computer only
var PlayerController     ToolOwner;

replication
{
    if (bNetDirty)
        PRI, SteamId, TSChannel, TSChannelName, VoiceChannel, bPluginLinked;
    if (bNetDirty && bNetOwner)
        ProximityRange, bLetDeadTalkToLiving, bProximitySameTeamOnly, TeamSpeakAddress, TeamSpeakChannel;
}

simulated event PostBeginPlay()
{
    super.PostBeginPlay();
    if (WorldInfo.NetMode != NM_DedicatedServer)
        SetTimer(0.5, true, 'InstallTool');
}

// ====================================================
// Server
// ====================================================

function Setup(MutTSVoice M, PlayerController PC)
{
    Mut = M;
    PRI = PC.PlayerReplicationInfo;
    if (PRI != None)
        SteamId = class'ROSteamUtils'.static.UniqueIdToSteamId64(PRI.UniqueId);
    CopySettings();
}

function CopySettings()
{
    if (Mut == None)
        return;
    ProximityRange = Mut.GetProximityRange();
    bLetDeadTalkToLiving = Mut.bLetDeadTalkToLiving;
    bProximitySameTeamOnly = Mut.bProximitySameTeamOnly;
    TeamSpeakAddress = Mut.TeamSpeakAddress;
    TeamSpeakChannel = Mut.TeamSpeakChannel;
}

// The player's TeamSpeak plugin says which channel they sit in
reliable server function ServerSetTSChannel(string ChannelId, string ChannelName)
{
    TSChannel = class'TSVRules'.static.CleanChannelId(ChannelId);
    TSChannelName = (TSChannel != "") ? Left(ChannelName, 40) : "";
}

reliable server function ServerSetVoice(byte Channel)
{
    VoiceChannel = (Channel < class'TSVRules'.const.CH_MAX) ? Channel : byte(0);
}

reliable server function ServerSetPluginLinked(bool bLinked)
{
    bPluginLinked = bLinked;
    if (!bLinked)
    {
        VoiceChannel = 0;
        TSChannel = "";
        TSChannelName = "";
    }
}

// mutate tsvoice on / off: the setting lives on the player's own computer
reliable client function ClientSetEnabled(bool bOn)
{
    if (Tool != None)
        Tool.SetEnabled(bOn);
}

function string PlayerNameOf()
{
    return (PRI != None) ? PRI.PlayerName : "?";
}

// ====================================================
// Owner's computer
// ====================================================

// The local player this info belongs to, or None when it is someone else's (or their player hasn't arrived yet). The
// owner isn't sent to players' games (only to a game that is also the server), so the local player is found by their
// player info: every player's game gets every player's info, and only the matching one puts in the tool.
simulated function PlayerController LocalOwner()
{
    local PlayerController PC;

    PC = PlayerController(Owner);
    if (PC == None || LocalPlayer(PC.Player) == None)
        PC = GetALocalPlayerController();
    if (PC == None || LocalPlayer(PC.Player) == None || PC.PlayerInput == None)
        return None;
    if (PRI == None || PC.PlayerReplicationInfo != PRI)
        return None;
    return PC;
}

simulated function InstallTool()
{
    local PlayerController PC;

    if (Tool != None)
    {
        ClearTimer('InstallTool');
        return;
    }
    PC = LocalOwner();
    if (PC == None)
        return;
    // Owned here too, so this game sends the server calls below (linked, voice channel, TeamSpeak channel): without an
    // owner on this side the game drops them
    if (Owner != PC)
        SetOwner(PC);
    // Wait for the player's Steam ID to arrive
    if (SteamId == "")
        return;

    ClearTimer('InstallTool');
    ToolOwner = PC;
    Tool = new(PC) class'TSVInteraction';
    Tool.Info = self;
    Tool.OnReceivedNativeInputKey = Tool.InputKey;
    PC.Interactions.AddItem(Tool);
    KeepToolFirst();
    SetTimer(1.0, true, 'KeepToolFirst');
    Tool.Start();
    SetTimer(0.1, true, 'ToolFrame');
}

simulated function ToolFrame()
{
    if (Tool != None)
        Tool.Frame(0.1);
}

// The voice keys have to reach the tool before the game's own input (which would start the game's voice chat), so
// the tool sits in front of PlayerInput. Other mods may reorder the list, so this is checked again now and then.
simulated function KeepToolFirst()
{
    local int ToolIndex, InputIndex;

    if (ToolOwner == None || Tool == None)
        return;

    ToolIndex = ToolOwner.Interactions.Find(Tool);
    InputIndex = ToolOwner.Interactions.Find(ToolOwner.PlayerInput);
    if (ToolIndex == INDEX_NONE || InputIndex == INDEX_NONE || ToolIndex < InputIndex)
        return;

    ToolOwner.Interactions.Remove(ToolIndex, 1);
    ToolOwner.Interactions.Insert(InputIndex, 1);
    ToolOwner.Interactions[InputIndex] = Tool;
}

simulated event Destroyed()
{
    if (Tool != None)
    {
        Tool.Stop();
        if (ToolOwner != None)
            ToolOwner.Interactions.RemoveItem(Tool);
    }
    Tool = None;
    super.Destroyed();
}

defaultproperties
{
    bAlwaysRelevant=true
    bOnlyRelevantToOwner=false
    NetUpdateFrequency=10
    ProximityRange=3750.0
}
