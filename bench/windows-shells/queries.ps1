<#
  chore(bench): DO NOT UPSTREAM
  Shows exactly what a Windows user sees for a few real queries, typed in cmd.exe,
  Windows PowerShell and pwsh. ezcmd has no shell detection, so all three should match.
#>
param(
    [Parameter(Mandatory)] [string] $Exe,
    [Parameter(Mandatory)] [string] $OutDir
)
$ErrorActionPreference = 'Stop'
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Queries = 'delete files', 'initializing repo', 'navigating directories'
$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine('## What ezcmd prints on Windows')
[void]$md.AppendLine()
foreach ($q in $Queries) {
    $outs = [ordered]@{}
    $outs['cmd'] = (& "$env:SystemRoot\System32\cmd.exe" /d /c "`"$Exe`" $q" 2>&1 | Out-String)
    $outs['Windows PowerShell'] = (& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "& '$Exe' $q" 2>&1 | Out-String)
    $outs['pwsh'] = (& pwsh -NoProfile -Command "& '$Exe' $q" 2>&1 | Out-String)
    $same = ($outs.Values | Select-Object -Unique).Count -eq 1
    [void]$md.AppendLine("### ``ezcmd $q``")
    [void]$md.AppendLine()
    if ($same) {
        [void]$md.AppendLine('Identical output in cmd, Windows PowerShell and pwsh:')
        [void]$md.AppendLine('```text'); [void]$md.Append($outs['cmd'].TrimEnd()); [void]$md.AppendLine(); [void]$md.AppendLine('```')
    } else {
        foreach ($k in $outs.Keys) {
            [void]$md.AppendLine("$k`:")
            [void]$md.AppendLine('```text'); [void]$md.Append($outs[$k].TrimEnd()); [void]$md.AppendLine(); [void]$md.AppendLine('```')
        }
    }
    [void]$md.AppendLine()
    foreach ($k in $outs.Keys) {
        Set-Content -Path (Join-Path $OutDir ("query-{0}-{1}.txt" -f ($q -replace ' ', '_'), ($k -replace ' ', '_'))) -Value $outs[$k] -Encoding utf8
    }
}
$text = $md.ToString()
Set-Content -Path (Join-Path $OutDir 'queries.md') -Value $text -Encoding utf8
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $text -Encoding utf8 }
Write-Host $text
