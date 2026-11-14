// The WebAdmin settings page for TeamSpeak voice (MutTSVoice's server settings). Saving updates every player's info
// straight away, so a new proximity range or TeamSpeak address applies without a map change.
class MutTSVoiceSettings extends MutatorSettings
    config(MutTSVoice_Server);

// The proximity range is shown in meters as it applies: an empty or 0 setting means the game's 75
static function float ShownRange(float Meters)
{
    return (Meters > 0) ? Meters : 75.0;
}

function InitMutSettings()
{
    if (self.myMut == None)
    {
        self.SetFloatPropertyByName('ProximityRangeMeters', ShownRange(class'MutTSVoice'.default.ProximityRangeMeters));
        self.SetIntPropertyByName('bProximitySameTeamOnly', int(class'MutTSVoice'.default.bProximitySameTeamOnly));
        self.SetIntPropertyByName('bLetDeadTalkToLiving', int(class'MutTSVoice'.default.bLetDeadTalkToLiving));
        self.SetIntPropertyByName('bEnemiesOverhear', int(class'MutTSVoice'.default.bEnemiesOverhear));
        self.SetStringPropertyByName('TeamSpeakAddress', class'MutTSVoice'.default.TeamSpeakAddress);
        self.SetStringPropertyByName('TeamSpeakChannel', class'MutTSVoice'.default.TeamSpeakChannel);
    }
    else
    {
        self.SetFloatPropertyByName('ProximityRangeMeters', ShownRange(MutTSVoice(self.myMut).ProximityRangeMeters));
        self.SetIntPropertyByName('bProximitySameTeamOnly', int(MutTSVoice(self.myMut).bProximitySameTeamOnly));
        self.SetIntPropertyByName('bLetDeadTalkToLiving', int(MutTSVoice(self.myMut).bLetDeadTalkToLiving));
        self.SetIntPropertyByName('bEnemiesOverhear', int(MutTSVoice(self.myMut).bEnemiesOverhear));
        self.SetStringPropertyByName('TeamSpeakAddress', MutTSVoice(self.myMut).TeamSpeakAddress);
        self.SetStringPropertyByName('TeamSpeakChannel', MutTSVoice(self.myMut).TeamSpeakChannel);
    }
}

function SaveMutSettings()
{
    local float Range;
    local int SameTeam, DeadToLiving, Overhear;
    local string Address, Channel;

    self.GetFloatPropertyByName('ProximityRangeMeters', Range);
    self.GetIntPropertyByName('bProximitySameTeamOnly', SameTeam);
    self.GetIntPropertyByName('bLetDeadTalkToLiving', DeadToLiving);
    self.GetIntPropertyByName('bEnemiesOverhear', Overhear);
    self.GetStringPropertyByName('TeamSpeakAddress', Address);
    self.GetStringPropertyByName('TeamSpeakChannel', Channel);
    Range = FClamp(Range, 5.0, 500.0);

    if (self.myMut == None)
    {
        class'MutTSVoice'.default.ProximityRangeMeters = Range;
        class'MutTSVoice'.default.bProximitySameTeamOnly = (SameTeam != 0);
        class'MutTSVoice'.default.bLetDeadTalkToLiving = (DeadToLiving != 0);
        class'MutTSVoice'.default.bEnemiesOverhear = (Overhear != 0);
        class'MutTSVoice'.default.TeamSpeakAddress = Address;
        class'MutTSVoice'.default.TeamSpeakChannel = Channel;
        class'MutTSVoice'.static.StaticSaveConfig();
    }
    else
    {
        MutTSVoice(self.myMut).ProximityRangeMeters = Range;
        MutTSVoice(self.myMut).bProximitySameTeamOnly = (SameTeam != 0);
        MutTSVoice(self.myMut).bLetDeadTalkToLiving = (DeadToLiving != 0);
        MutTSVoice(self.myMut).bEnemiesOverhear = (Overhear != 0);
        MutTSVoice(self.myMut).TeamSpeakAddress = Address;
        MutTSVoice(self.myMut).TeamSpeakChannel = Channel;
        self.myMut.SaveConfig();
        MutTSVoice(self.myMut).UpdateSettings();
    }
}

// The WebAdmin page: one tab per group, a plain label for each setting. The group names and labels are in the .int file
// (Localization\INT\MutTSVoice.int, section [MutTSVoiceSettings]), in the same order as below.
defaultproperties
{
    // Tab ids are numbers: the game's WebAdmin checks a named tab against the admin's rights with a broken address on
    // the Mutators page, so with multi-admin logins (the 29th's servers) every named tab was hidden.
    SettingsGroups.Add((GroupID="0",pMin=100,pMax=110,lMin=0,lMax=0))
    SettingsGroups.Add((GroupID="1",pMin=110,pMax=120,lMin=0,lMax=0))

    Properties.Add((PropertyId=100,Data=(Type=SDT_Float)))
    PropertyMappings.Add((Id=100,Name="ProximityRangeMeters",MappingType=PVMT_Ranged,MinVal=5,MaxVal=500,RangeIncrement=5))
    Properties.Add((PropertyId=101,Data=(Type=SDT_Int32,Value1=0)))
    PropertyMappings.Add((Id=101,Name="bProximitySameTeamOnly",MappingType=PVMT_IdMapped,ValueMappings=((Id=0),(Id=1))))
    Properties.Add((PropertyId=102,Data=(Type=SDT_Int32,Value1=0)))
    PropertyMappings.Add((Id=102,Name="bLetDeadTalkToLiving",MappingType=PVMT_IdMapped,ValueMappings=((Id=0),(Id=1))))
    Properties.Add((PropertyId=103,Data=(Type=SDT_Int32,Value1=0)))
    PropertyMappings.Add((Id=103,Name="bEnemiesOverhear",MappingType=PVMT_IdMapped,ValueMappings=((Id=0),(Id=1))))

    Properties.Add((PropertyId=110,Data=(Type=SDT_String)))
    PropertyMappings.Add((Id=110,Name="TeamSpeakAddress",MappingType=PVMT_RawValue,MinVal=0,MaxVal=128))
    Properties.Add((PropertyId=111,Data=(Type=SDT_String)))
    PropertyMappings.Add((Id=111,Name="TeamSpeakChannel",MappingType=PVMT_RawValue,MinVal=0,MaxVal=128))
}
