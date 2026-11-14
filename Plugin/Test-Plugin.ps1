<#
  Checks the RS2 Voice plugin without the game: connects to it the way the game does, says hello with a Steam ID,
  and prints what the plugin answers (TS 1/0 for TeamSpeak's connection, CHAN for the channel you sit in).
  TeamSpeak must be running with the plugin turned on. While this runs, the plugin turns your TeamSpeak microphone off
  (as it does while the game is linked); it is given back when this ends.

    .\Test-Plugin.ps1 -SteamId 76561198040740127 [-Seconds 20] [-Port 25700]
#>
param(
    [Parameter(Mandatory = $true)][string]$SteamId,
    [int]$Seconds = 20,
    [int]$Port = 25700
)
$client = New-Object System.Net.Sockets.TcpClient
try { $client.Connect("127.0.0.1", $Port) }
catch { Write-Host "No plugin on 127.0.0.1:$Port. Is TeamSpeak running with RS2 Voice turned on (Tools > Options > Addons)?"; exit 1 }
$stream = $client.GetStream()
$writer = New-Object System.IO.StreamWriter($stream); $writer.NewLine = "`n"; $writer.AutoFlush = $true
$reader = New-Object System.IO.StreamReader($stream)

$writer.WriteLine("HELLO 1 $SteamId")
$writer.WriteLine("CFG 75")
Write-Host "Linked. Waiting $Seconds seconds for answers (move to another TeamSpeak channel to see CHAN change)..."

$end = (Get-Date).AddSeconds($Seconds)
$pending = $reader.ReadLineAsync()
while ((Get-Date) -lt $end) {
    if ($pending.Wait(250)) {
        if ($null -eq $pending.Result) { Write-Host "The plugin closed the link"; break }
        Write-Host "plugin> $($pending.Result)"
        $pending = $reader.ReadLineAsync()
    }
    # A frame like the game sends, so the 3D calls run too
    $writer.WriteLine("LIS 0 0 0 1 0 0 0 0 1")
    $writer.WriteLine("END")
}
$writer.WriteLine("BYE")
$client.Close()
Write-Host "Done; the plugin has given the microphone back."
