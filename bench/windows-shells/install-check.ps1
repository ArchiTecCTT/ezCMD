<#
  chore(bench): DO NOT UPSTREAM
  Runs install.ps1 as a freshly created *standard* (non-admin) local user, to check
  whether the README's "Open PowerShell as Administrator" is needed.
    mode file: powershell -ExecutionPolicy Bypass -File <checkout>\install.ps1 (uses the locally built binary)
    mode irm : irm https://raw.githubusercontent.com/ItzEvhyx/ezCMD/main/install.ps1 | iex (the README one-liner)
#>
param(
    [Parameter(Mandatory)] [string] $Exe,
    [Parameter(Mandatory)] [string] $Installer,
    [Parameter(Mandatory)] [string] $OutDir
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$meAdmin = ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "Runner account: $($me.Name), elevated admin: $meAdmin"

# A folder every local user can read, laid out like a checkout so $PSScriptRoot\target\release\ezcmd.exe exists.
$Root = 'C:\ezb-install'
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$Root\pkg\target\release", "$Root\logs" | Out-Null
Copy-Item $Installer "$Root\pkg\install.ps1"
Copy-Item $Exe "$Root\pkg\target\release\ezcmd.exe"
icacls $Root /grant '*S-1-5-32-545:(OI)(CI)M' /T | Out-Null   # BUILTIN\Users: modify

$child = @'
param([string] $Mode)
$ErrorActionPreference = 'Continue'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
"USER=$($id.Name)"
"IS_ADMIN=$(([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
"INTEGRITY=$(((whoami /groups) | Select-String 'Mandatory Label\\(\w+ Mandatory Level)').Matches[0].Groups[1].Value)"
"USERPROFILE=$env:USERPROFILE"
"----- installer output -----"
if ($Mode -eq 'file') {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File 'C:\ezb-install\pkg\install.ps1' 2>&1 | Out-String
} else {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command 'irm https://raw.githubusercontent.com/ItzEvhyx/ezCMD/main/install.ps1 | iex' 2>&1 | Out-String
}
"INSTALL_EXIT=$LASTEXITCODE"
"----- checks -----"
$exe = "$env:USERPROFILE\.local\bin\ezcmd.exe"
"EXE_PRESENT=$(Test-Path $exe)"
"MARKER_PRESENT=$(Test-Path "$env:APPDATA\ezcmd\.installed")"
"USER_PATH_HAS_BIN=$(([Environment]::GetEnvironmentVariable('Path', 'User')) -like "*$env:USERPROFILE\.local\bin*")"
if (Test-Path $exe) { "VERSION=$((& $exe --version) -join ' ')" }
'@
Set-Content -Path "$Root\child.ps1" -Value $child -Encoding utf8

function New-Pw { 'Ezb#' + [guid]::NewGuid().ToString('N').Substring(0, 16) + 'aZ9!' }

function Invoke-AsStandardUser([string] $User, [string] $Mode) {
    $pw = New-Pw
    net user $User $pw /add /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "net user $User /add failed" }
    $members = net localgroup Administrators
    if ($members -match "^$User$") { throw "$User is unexpectedly an Administrator" }
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$Root\child.ps1", '-Mode', $Mode)) { $psi.ArgumentList.Add($a) }
    $psi.UserName = $User
    $psi.Domain = $env:COMPUTERNAME
    $psi.Password = ConvertTo-SecureString $pw -AsPlainText -Force
    $psi.LoadUserProfile = $true
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $Root
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(300000)) { $p.Kill($true); throw "install as $User timed out" }
    $text = $o.GetAwaiter().GetResult() + "`n----- stderr -----`n" + $e.GetAwaiter().GetResult()
    Set-Content -Path (Join-Path $OutDir "install-$Mode.log") -Value $text -Encoding utf8
    Write-Host "===== install as $User ($Mode) =====`n$text"
    $kv = @{}
    foreach ($line in $text -split "`r?`n") { if ($line -match '^([A-Z_]+)=(.*)$') { $kv[$Matches[1]] = $Matches[2].Trim() } }
    $kv['MODE'] = $Mode
    $kv
}

$rows = @()
$rows += Invoke-AsStandardUser 'ezbstd1' 'file'
$rows += Invoke-AsStandardUser 'ezbstd2' 'irm'

$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine('## install.ps1 as a standard (non-admin) user')
[void]$md.AppendLine()
[void]$md.AppendLine("The runner account itself ($($me.Name)) is an elevated admin ($meAdmin), so each install ran as a newly created local user that is **not** in Administrators, started via CreateProcessWithLogon with its profile loaded.")
[void]$md.AppendLine()
[void]$md.AppendLine('| How | User | Admin? | Integrity | Installer exit | ezcmd.exe in ~\.local\bin | marker in %APPDATA% | User PATH updated | `ezcmd --version` |')
[void]$md.AppendLine('|---|---|---|---|---|---|---|---|---|')
foreach ($r in $rows) {
    $how = if ($r.MODE -eq 'file') { '`powershell -ExecutionPolicy Bypass -File install.ps1` (checkout)' } else { '`irm .../main/install.ps1 \| iex` (README one-liner)' }
    [void]$md.AppendLine("| $how | $($r.USER) | $($r.IS_ADMIN) | $($r.INTEGRITY) | $($r.INSTALL_EXIT) | $($r.EXE_PRESENT) | $($r.MARKER_PRESENT) | $($r.USER_PATH_HAS_BIN) | $($r.VERSION) |")
}
$text = $md.ToString()
Set-Content -Path (Join-Path $OutDir 'install.md') -Value $text -Encoding utf8
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $text -Encoding utf8 }
Write-Host $text

foreach ($u in 'ezbstd1', 'ezbstd2') { net user $u /delete | Out-Null }
