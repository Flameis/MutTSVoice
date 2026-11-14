<#
  Builds the RS2 Voice TeamSpeak 3 plugin.
    1. Gets the TeamSpeak plugin SDK headers into include\ if they aren't there (they are TeamSpeak's, so not in git).
    2. Compiles rs2voice.c with the Visual Studio C++ build tools into build\rs2voice_win64.dll.
    3. Packs build\RS2Voice.ts3_plugin: double-click it to install the plugin into TeamSpeak.
  -Install also copies the DLL straight into %APPDATA%\TS3Client\plugins (close TeamSpeak first).
#>
param([switch]$Install)
$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$Build = Join-Path $Here "build"
New-Item -ItemType Directory -Force $Build | Out-Null

# ---- 1. SDK headers
if (-not (Test-Path (Join-Path $Here "include\ts3_functions.h"))) {
    Write-Host "[Build-Plugin] Getting the TeamSpeak plugin SDK headers"
    $tmp = Join-Path $env:TEMP ("ts3sdk_" + [guid]::NewGuid().ToString("N"))
    git clone --depth 1 https://github.com/TeamSpeak-Systems/ts3client-pluginsdk.git $tmp | Out-Null
    Copy-Item -Recurse (Join-Path $tmp "include") (Join-Path $Here "include")
    Remove-Item -Recurse -Force $tmp
}

# ---- 2. Compile
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw "No Visual Studio C++ build tools found (winget install Microsoft.VisualStudio.2022.BuildTools)" }
$vcvars = Join-Path $vs "VC\Auxiliary\Build\vcvars64.bat"
$cmd = "`"$vcvars`" >nul && cl /nologo /O2 /W3 /MT /LD /D_CRT_SECURE_NO_WARNINGS /DWIN32 /I`"$Here\include`" `"$Here\rs2voice.c`" /Fo`"$Build\\`" /Fe`"$Build\rs2voice_win64.dll`" /link /DLL ws2_32.lib winhttp.lib"
cmd /c $cmd
if ($LASTEXITCODE -ne 0) { throw "Compile failed" }
Write-Host "[Build-Plugin] Built $Build\rs2voice_win64.dll"

# ---- 3. Installer package (a zip with package.ini and plugins\)
$pkg = Join-Path $Build "package"
Remove-Item -Recurse -Force $pkg -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $pkg "plugins") | Out-Null
Copy-Item (Join-Path $Build "rs2voice_win64.dll") (Join-Path $pkg "plugins")
@"
Name = RS2 Voice
Type = Plugin
Author = 29th Infantry Division Engineer Corps
Version = 1.0
Platforms = win64
Description = Rising Storm 2 voice through TeamSpeak: all, team, squad, 29th squad, vehicle, command and proximity voice.
"@ | Set-Content -Encoding ASCII (Join-Path $pkg "package.ini")
$zip = Join-Path $Build "RS2Voice.zip"
$out = Join-Path $Build "RS2Voice.ts3_plugin"
Remove-Item $zip, $out -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $pkg "*") -DestinationPath $zip
Move-Item $zip $out
Write-Host "[Build-Plugin] Installer: $out"

if ($Install) {
    if (Get-Process ts3client_win64 -ErrorAction SilentlyContinue) { throw "Close TeamSpeak before -Install (it locks the plugin DLL)" }
    $dest = Join-Path $env:APPDATA "TS3Client\plugins"
    Copy-Item (Join-Path $Build "rs2voice_win64.dll") $dest -Force
    Write-Host "[Build-Plugin] Installed into $dest"
}
