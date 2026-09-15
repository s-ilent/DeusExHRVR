param([Parameter(Mandatory=$true)][string]$GameDirectory)
$ErrorActionPreference='Stop'
$gameRoot=(Resolve-Path -LiteralPath $GameDirectory).Path
$exe=Join-Path $gameRoot 'DXHRDC.exe'
if(!(Test-Path -LiteralPath $exe)){throw 'DXHRDC.exe not found.'}
if(Get-Process DXHRDC -ErrorAction SilentlyContinue){throw 'Close Deus Ex before installation.'}
# Validate the EXE by PE header fields (TimeDateStamp + SizeOfImage), matching
# the checks the C++ hooks perform at runtime (EngineCamera.cpp Install() and
# EngineDisplay.cpp InstallOnce()). This accepts both the Steam and GOG builds
# of Director's Cut 2.0.66.0, which share these header values and the same
# code layout at the hook RVAs despite different SHA256 hashes (the builds
# differ only in non-code sections — DRM stubs, GOG Galaxy integration, etc.).
$bytes=[System.IO.File]::ReadAllBytes($exe)
$e_lfanew=[BitConverter]::ToInt32($bytes,0x3c)
$timestamp=[BitConverter]::ToUInt32($bytes,$e_lfanew+8)
$sizeOfImage=[BitConverter]::ToUInt32($bytes,$e_lfanew+80)
if($timestamp -ne 0x52840914 -or $sizeOfImage -ne 0x01c54000){
    throw "Unsupported DXHRDC.exe build (TimeDateStamp=0x$($timestamp.ToString('x8')), SizeOfImage=0x$($sizeOfImage.ToString('x8'))). This mod supports Director's Cut 2.0.66.0 (Steam and GOG)."
}
$payload=Join-Path $PSScriptRoot 'dist'
$files=@('d3d11.dll','atidxx32.dll','atiadlxy.dll','DeusExHRVR\DeusExHRVRHost.exe')
foreach($f in $files){if(!(Test-Path -LiteralPath (Join-Path $payload $f))){throw "Missing payload: $f"}}
$backupRoot=Join-Path $gameRoot 'DeusExHRVR-backup'
$manifestPath=Join-Path $backupRoot 'install.json'
$regPath='HKCU:\Software\Eidos\Deus Ex: HRDC\Graphics'
$changes=@{EnableDirectX11=1;StereoMode=1;EnableVSync=0;AntiAliasingMode=0}
if(!(Test-Path -LiteralPath $manifestPath)) {
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $reg=Get-Item -LiteralPath $regPath
    $entries=@();$settings=@()
    foreach($f in $files){
        $target=Join-Path $gameRoot $f;$exists=Test-Path -LiteralPath $target
        if($exists){$dest=Join-Path $backupRoot $f;New-Item -ItemType Directory -Path (Split-Path $dest) -Force|Out-Null;Copy-Item -LiteralPath $target -Destination $dest}
        $entries+=@{path=$f;existed=$exists}
    }
    foreach($key in $changes.Keys){$exists=$reg.GetValueNames() -contains $key;$settings+=@{name=$key;existed=$exists;value=if($exists){$reg.GetValue($key)}else{$null}}}
    @{version=1;gameRoot=$gameRoot;files=$entries;settings=$settings} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
}
foreach($f in $files){$target=Join-Path $gameRoot $f;New-Item -ItemType Directory -Path (Split-Path $target) -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $payload $f) -Destination $target -Force}
foreach($key in $changes.Keys){New-ItemProperty -LiteralPath $regPath -Name $key -Value $changes[$key] -PropertyType DWord -Force|Out-Null}
'Installed native stereo bridge. Original files/settings are in '+$backupRoot
