// The connection from the game to the RS2 Voice TeamSpeak plugin, on this computer only (127.0.0.1). One text line per
// message, both ways; the messages are listed in the README under "How it works". Tries again every few seconds while
// the plugin isn't there (TeamSpeak closed, plugin not installed), without filling the log.
class TSVLink extends TcpLink;

var TSVInteraction  Tool;
var int             PluginPort;
var bool            bWantOpen;
var bool            bReportedFail;

function Connect(int ToPort)
{
    PluginPort = ToPort;
    bWantOpen = true;
    TryOpen();
}

function TryOpen()
{
    local IpAddr Addr;

    if (!bWantOpen || IsConnected())
        return;
    if (LinkState != STATE_Initialized && LinkState != STATE_Ready)
        Close();

    if (!StringToIpAddr("127.0.0.1", Addr))
        return;
    Addr.Port = PluginPort;
    if (BindPort(0, true) == 0 || !Open(Addr))
        Failed();
    else
        SetTimer(3.0, false, 'OpenTimedOut');
}

function OpenTimedOut()
{
    if (!IsConnected())
        Failed();
}

function Failed()
{
    if (!bReportedFail)
    {
        bReportedFail = true;
        `log("[MutTSVoice] No TeamSpeak plugin on port "$PluginPort$" (TeamSpeak closed or the RS2 Voice plugin not installed); trying again every 5 seconds");
    }
    Close();
    if (bWantOpen)
        SetTimer(5.0, false, 'TryOpen');
}

event Opened()
{
    ClearTimer('OpenTimedOut');
    bReportedFail = false;
    `log("[MutTSVoice] Linked to the TeamSpeak plugin on port "$PluginPort);
    if (Tool != None)
        Tool.LinkOpened();
}

event Closed()
{
    if (Tool != None)
        Tool.LinkClosed();
    if (bWantOpen)
        SetTimer(5.0, false, 'TryOpen');
}

event ReceivedLine(string Line)
{
    if (Tool != None)
        Tool.HandleLine(Line);
}

function Send(string Line)
{
    if (IsConnected())
        SendText(Line);
}

function CloseLink()
{
    bWantOpen = false;
    ClearTimer('TryOpen');
    ClearTimer('OpenTimedOut');
    Tool = None;
    if (IsConnected())
        SendText("BYE");
    Close();
    Destroy();
}

defaultproperties
{
    LinkMode=MODE_Line
    InLineMode=LMODE_auto
    OutLineMode=LMODE_UNIX
    ReceiveMode=RMODE_Event
}
