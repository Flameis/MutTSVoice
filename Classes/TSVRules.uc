// Who hears whom on each TeamSpeak voice channel. Pure functions on plain player snapshots, so the same rules run on
// every game client (to pick who the TeamSpeak plugin whispers to) and in the test harness.
//
// Channel numbers are shared with the TeamSpeak plugin (Plugin\rs2voice.c): keep them in step.
class TSVRules extends Object;

const CH_NONE      = 0;
const CH_ALL       = 1;
const CH_TEAM      = 2;
const CH_SQUAD     = 3;   // everyone in the talker's TeamSpeak channel (plain channel talk, not a whisper)
const CH_VEHICLE   = 4;
const CH_PROXIMITY = 5;
const CH_COMMAND   = 7;   // squad leaders and the commander
const CH_MAX       = 8;
const CH_CURRENT   = 255; // "the channel the game's voice key is set to" (only used while choosing)

const NO_TEAM      = 255;
const NO_SQUAD     = 255;

// One player as the rules see them
struct TSVPlayerState
{
    var string  SteamId;
    var byte    Team;         // 0 or 1; NO_TEAM for spectators and players not on a team
    var byte    Squad;        // game squad index; NO_SQUAD for none (only used for the game's squad leader checks)
    var bool    bLeader;      // squad leader or commander (for the command channel)
    var bool    bDead;
    var string  TSChannel;    // the player's TeamSpeak channel ID; "" when not known
    var int     VehicleKey;   // the same number for everyone in one vehicle; 0 when not in one
    var bool    bHasLocation;
    var vector  Location;

    structdefaultproperties
    {
        Team=255
        Squad=255
    }
};

// The server's settings that change the rules
struct TSVRuleSettings
{
    var float   ProximityRange;         // unreal units
    var bool    bLetDeadTalkToLiving;
    var bool    bProximitySameTeamOnly;
    var bool    bEnemiesOverhear;       // enemies close by overhear Squad, Team, Vehicle and Command talk

    structdefaultproperties
    {
        ProximityRange=3750.0
    }
};

static function bool CanHear(TSVPlayerState Talker, TSVPlayerState Listener, byte Channel, TSVRuleSettings S)
{
    if (Talker.SteamId == "" || Talker.SteamId == Listener.SteamId)
        return false;

    // With the server's bEnemiesOverhear, an enemy close by overhears the channels that are otherwise private
    if (Overhears(Talker, Listener, Channel, S))
        return true;

    // Squad is the TeamSpeak channel itself: everyone sitting in it hears, whatever their team or state in the game
    if (Channel == CH_SQUAD)
        return Talker.TSChannel != "" && Talker.TSChannel == Listener.TSChannel;

    // Spectators and players without a team only reach each other, on any other channel
    if (Talker.Team > 1)
        return Listener.Team > 1;

    // The dead are heard by the dead only, unless the server lets them talk to the living
    if (Talker.bDead && !Listener.bDead && !S.bLetDeadTalkToLiving)
        return false;

    switch (Channel)
    {
        case CH_ALL:
            return true;
        case CH_TEAM:
            return Talker.Team == Listener.Team;
        case CH_VEHICLE:
            return Talker.Team == Listener.Team && Talker.VehicleKey != 0 && Talker.VehicleKey == Listener.VehicleKey;
        case CH_COMMAND:
            return Talker.Team == Listener.Team && Talker.bLeader && Listener.bLeader;
        case CH_PROXIMITY:
            return !Talker.bDead && !Listener.bDead && Talker.bHasLocation && Listener.bHasLocation
                && VSize(Talker.Location - Listener.Location) <= S.ProximityRange
                && (!S.bProximitySameTeamOnly || Talker.Team == Listener.Team);
    }
    return false;
}

// An enemy within proximity range overhearing Squad, Team, Vehicle or Command talk, as if they heard the talker speak
// (only with the server's bEnemiesOverhear; both alive, both on a team). They hear it from the talker's direction.
static function bool Overhears(TSVPlayerState Talker, TSVPlayerState Listener, byte Channel, TSVRuleSettings S)
{
    if (!S.bEnemiesOverhear)
        return false;
    if (Channel != CH_SQUAD && Channel != CH_TEAM && Channel != CH_VEHICLE && Channel != CH_COMMAND)
        return false;
    if (Talker.SteamId == "" || Talker.SteamId == Listener.SteamId)
        return false;
    return Talker.Team < 2 && Listener.Team < 2 && Talker.Team != Listener.Team && !Talker.bDead && !Listener.bDead
        && Talker.bHasLocation && Listener.bHasLocation && VSize(Talker.Location - Listener.Location) <= S.ProximityRange;
}

static function string ChannelName(byte Channel)
{
    switch (Channel)
    {
        case CH_ALL:       return "All";
        case CH_TEAM:      return "Team";
        case CH_SQUAD:     return "Squad";
        case CH_VEHICLE:   return "Vehicle";
        case CH_PROXIMITY: return "Proximity";
        case CH_COMMAND:   return "Command";
    }
    return "";
}

// The game's own voice channel setting (ROPlayerController.CurrentVOIPChannel, EVOIPChannel) as one of ours
static function byte FromGameChannel(byte GameChannel)
{
    switch (GameChannel)
    {
        case 0: return CH_ALL;
        case 1: return CH_TEAM;
        case 2: return CH_SQUAD;
        case 3: return CH_VEHICLE;
        case 4: return CH_PROXIMITY;
        case 5: return CH_COMMAND;
    }
    return CH_TEAM;
}

// The channel a game voice command talks on ("StartTeamVoiceChat" is Team); CH_CURRENT for the game's own voice key,
// CH_NONE if the command isn't a voice command. Takes a whole binding ("StartVoiceChat | OnRelease StopVoiceChat").
static function byte ChannelForCommand(string Command)
{
    local array<string> Parts;
    local string First;

    Parts = SplitString(Command, "|", true);
    if (Parts.Length == 0)
        return CH_NONE;
    First = Locs(Repl(Parts[0], " ", ""));
    switch (First)
    {
        case "startvoicechat":            return CH_CURRENT;
        case "startpublicvoicechat":      return CH_ALL;
        case "startteamvoicechat":        return CH_TEAM;
        case "startsquadvoicechat":       return CH_SQUAD;
        case "startvehiclevoicechat":     return CH_VEHICLE;
        case "startspatializedvoicechat": return CH_PROXIMITY;
        case "startcommandvoicechat":     return CH_COMMAND;
    }
    return CH_NONE;
}

// A TeamSpeak channel ID as the plugin sends it: digits only, "" otherwise
static function string CleanChannelId(string S)
{
    local string C;
    local int i;

    if (Len(S) == 0 || Len(S) > 20)
        return "";
    for (i = 0; i < Len(S); i++)
    {
        C = Mid(S, i, 1);
        if (C < "0" || C > "9")
            return "";
    }
    return S;
}

defaultproperties
{
}
