# Build the watch app (Connect IQ SDK + developer key in %USERPROFILE%\.garmin).
#   scripts\build.ps1                      bin\AudiobooksBeta-<device>.prg for every beta product
#   scripts\build.ps1 -Device fr970        one product
#   scripts\build.ps1 -Beta 3              signed bin\beta3\AudiobooksBeta.iq, upload as version 0.0.3
param(
    [string]$Device = "all",
    [int]$Beta = 0
)
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$jungle = "$RepoRoot\beta.jungle"
$manifest = "$RepoRoot\manifest-beta.xml"
$name = "AudiobooksBeta"

function Get-CiqSdk {
    $root = Join-Path $env:APPDATA "Garmin\ConnectIQ"
    $cfg = Join-Path $root "current-sdk.cfg"
    if (Test-Path $cfg) {
        $p = (Get-Content $cfg -Raw).Trim()
        if (Test-Path (Join-Path $p "bin\monkeyc.bat")) { return $p }
    }
    $sdks = Get-ChildItem (Join-Path $root "Sdks") -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "bin\monkeyc.bat") } |
        Sort-Object LastWriteTime -Descending
    if ($sdks) { return $sdks[0].FullName }
    throw "Connect IQ SDK not found under $root - install it with the SDK Manager"
}

$sdk = Get-CiqSdk
$key = Join-Path $env:USERPROFILE ".garmin\developer_key.der"
if (-not (Test-Path $key)) { throw "No developer key at $key" }
# Gitignored: holds the built-in proxies and debug values; the example builds a proxy-less app.
if (-not (Test-Path "$RepoRoot\source\Local.mc")) {
    Copy-Item "$RepoRoot\source\Local.mc.example" "$RepoRoot\source\Local.mc"
}
Write-Host "SDK: $sdk"
New-Item -ItemType Directory -Force "$RepoRoot\bin" | Out-Null

function Invoke-Monkeyc([string[]]$monkeyArgs) {
    # PS 5.1 turns a native tool's stderr (monkeyc warnings) into a terminating error under Stop
    $ErrorActionPreference = "Continue"
    # Upstream's code compiles only with the type checker off (static calls to instance methods,
    # string enums as indexes)
    & "$sdk\bin\monkeyc.bat" @monkeyArgs -l 0 2>&1 | ForEach-Object { Write-Host "$_" }
    $code = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    return $code
}

if ($Beta -gt 0) {
    $dir = "$RepoRoot\bin\beta$Beta"
    New-Item -ItemType Directory -Force $dir | Out-Null
    $out = "$dir\$name.iq"
    $code = Invoke-Monkeyc @("-e", "-r", "-f", $jungle, "-o", $out, "-y", $key, "-w")
    if ($code -ne 0) { throw "monkeyc -e failed" }
    Write-Host "OK $out ($((Get-Item $out).Length) bytes), upload as version 0.0.$Beta"
    exit 0
}

$devices = if ($Device -ne "all") { @($Device) } else {
    ([xml](Get-Content $manifest)).manifest.application.products.product | ForEach-Object { $_.id }
}
foreach ($d in $devices) {
    $out = "$RepoRoot\bin\$name-$d.prg"
    $code = Invoke-Monkeyc @("-d", $d, "-f", $jungle, "-o", $out, "-y", $key, "-w")
    if ($code -ne 0) { throw "monkeyc failed for $d" }
    Write-Host "OK $out ($((Get-Item $out).Length) bytes)"
}
