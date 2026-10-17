# ezCMD automated installer for Windows PowerShell
$ErrorActionPreference = "Stop"

$Repo = "ItzEvhyx/ezcmd"
$InstallDir = "$env:USERPROFILE\.local\bin"
$ExePath = "$InstallDir\ezcmd.exe"

Write-Host "Installing ezCMD for Windows..." -ForegroundColor Cyan

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path 2>$null
if ($ScriptDir -and (Test-Path "$ScriptDir\target\release\ezcmd.exe")) {
    Copy-Item "$ScriptDir\target\release\ezcmd.exe" $ExePath -Force
} elseif ($ScriptDir -and (Test-Path "$ScriptDir\ezcmd.exe")) {
    Copy-Item "$ScriptDir\ezcmd.exe" $ExePath -Force
} else {
    $AssetTarget = "x86_64-pc-windows-msvc"
    $ZipUrl = "https://github.com/$Repo/releases/latest/download/ezcmd-$AssetTarget.zip"
    $TempZip = "$env:TEMP\ezcmd.zip"
    $TempExtract = "$env:TEMP\ezcmd_extract"

    Write-Host "Downloading $ZipUrl..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $ZipUrl -OutFile $TempZip
    Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force
    Copy-Item "$TempExtract\ezcmd.exe" $ExePath -Force
    Remove-Item $TempZip -Force -ErrorAction SilentlyContinue
    Remove-Item $TempExtract -Recurse -Force -ErrorAction SilentlyContinue
}

# Check if ~/.local/bin is in PATH
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$InstallDir*") {
    Write-Host "Adding $InstallDir to User PATH..." -ForegroundColor Yellow
    [Environment]::SetEnvironmentVariable("Path", "$UserPath;$InstallDir", "User")
    $env:Path += ";$InstallDir"
}

Write-Host ""
Write-Host "✓ ezcmd was successfully installed to $ExePath!" -ForegroundColor Green
Write-Host ""

& "$ExePath" --welcome
