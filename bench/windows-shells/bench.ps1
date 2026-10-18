<#
  chore(bench): DO NOT UPSTREAM
  Runs every command ezcmd shows a Windows user in cmd.exe, Windows PowerShell 5.1
  and PowerShell 7, each in a fresh scratch directory, and records whether the
  intended effect happened. A failing command is a result, not a harness error.
#>
param(
    [Parameter(Mandatory)] [string] $Exe,
    [Parameter(Mandatory)] [string] $OutDir,
    [int] $TimeoutSec = 60
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

$Base = Join-Path $env:RUNNER_TEMP ("ezb-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $Base | Out-Null
$Notes = [System.Collections.Generic.List[string]]::new()

$Shells = [ordered]@{
    cmd   = @{ Label = 'cmd'; File = "$env:SystemRoot\System32\cmd.exe" }
    winps = @{ Label = 'Windows PowerShell'; File = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
    pwsh  = @{ Label = 'pwsh'; File = (Get-Command pwsh).Source }
}

# ---------------------------------------------------------------- D: drive
# `cd /d D:\<folder>` is tested literally on D:. Prefer a scratch dir on D:.
$scratchDrive = (Split-Path -Qualifier $Base)
$DScratch = $null   # real folder
$DCmdRoot = $null   # same folder, spelled as D:\...
$SubstUsed = $false
if ($scratchDrive -ieq 'D:') {
    $DScratch = $Base; $DCmdRoot = $Base
    $Notes.Add("RUNNER_TEMP is on D: ($env:RUNNER_TEMP), so ``cd /d D:\<folder>`` targets a folder inside the scratch dir.")
} elseif (Test-Path 'D:\') {
    $DScratch = "D:\ezb-scratch-" + [guid]::NewGuid().ToString('N').Substring(0, 8)
    New-Item -ItemType Directory -Path $DScratch | Out-Null
    $DCmdRoot = $DScratch
    $Notes.Add("RUNNER_TEMP is on $scratchDrive; D: exists, so a dedicated scratch folder $DScratch was used for ``cd /d D:\<folder>``.")
} else {
    $DScratch = Join-Path $Base 'ddrive'
    New-Item -ItemType Directory -Path $DScratch | Out-Null
    subst D: $DScratch
    $SubstUsed = $true; $DCmdRoot = 'D:\'
    $Notes.Add("No D: drive on this runner; ``subst D: $DScratch`` was used so the literal command could run.")
}
# Working dir for that test must be on another drive than D:.
$OtherDriveDir = if ($scratchDrive -ieq 'D:') { Join-Path $env:TEMP ("ezb-c-" + [guid]::NewGuid().ToString('N').Substring(0, 8)) } else { Join-Path $Base 'cdrive' }
New-Item -ItemType Directory -Force -Path $OtherDriveDir | Out-Null

# ---------------------------------------------------------------- resolved commands
$helpText = & $Exe --plain --help -windows
$helpText | Set-Content -Path (Join-Path $OutDir 'ezcmd-help-windows.txt') -Encoding utf8
$Resolved = [System.Collections.Generic.List[object]]::new()
$tool = $null; $section = $null
foreach ($line in $helpText) {
    if ($line -match '^TOOL: (.+)$') { $tool = $Matches[1]; continue }
    if ($line -match '^# ---(.+)---$') { $section = $Matches[1]; continue }
    if ($tool -and $line -match '^(.*?) --- (.*)$') {
        $Resolved.Add([pscustomobject]@{ Tool = $tool; Section = $section; Template = $Matches[1]; Note = $Matches[2] })
    }
}
if ($Resolved.Count -lt 50) { throw "Parsed only $($Resolved.Count) commands from ezcmd --help -windows; parser broken?" }
Write-Host "Resolved $($Resolved.Count) Windows commands from ezcmd."

# ---------------------------------------------------------------- helpers
# Plain functions on purpose: an advanced function would swallow git's `-d` as -Debug.
function G {
    # git for fixtures/verification, in the current test's environment
    $out = & git @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "fixture git $($args -join ' ') failed: $out" }
    $out
}
function GQ {
    # git query that may fail; returns $null on failure
    $out = & git @args 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    ($out -join "`n").Trim()
}
function FileUrl([string] $path) { 'file:///' + ($path -replace '\\', '/') }
function Write-Text([string] $path, [string] $text) { [IO.File]::WriteAllText($path, $text) }

# ---------------------------------------------------------------- template fixture
$Template = Join-Path $Base 'template'
New-Item -ItemType Directory -Path $Template | Out-Null
Push-Location $Template
try {
    Write-Text "$Template\file.txt" "hello text world`r`nsecond line`r`n"
    Write-Text "$Template\src.txt" "source file`r`n"
    Write-Text "$Template\old.txt" "old name`r`n"
    New-Item -ItemType Directory -Path "$Template\emptydir", "$Template\navtarget", "$Template\fulldir\sub", "$Template\srcdir\sub" | Out-Null
    Write-Text "$Template\fulldir\a.txt" "a"
    Write-Text "$Template\fulldir\sub\b.txt" "b"
    Write-Text "$Template\srcdir\a.txt" "a"
    Write-Text "$Template\srcdir\sub\b.txt" "b"
    New-Item -ItemType Directory -Path "$Template\newproj" | Out-Null
    Write-Text "$Template\newproj\readme.txt" "new project`r`n"

    $env:GIT_CONFIG_GLOBAL = "$Template\gitconfig"
    Write-Text $env:GIT_CONFIG_GLOBAL "[user]`n`tname = Bench Fixture`n`temail = fixture@example.com`n[init]`n`tdefaultBranch = main`n[advice]`n`tdetachedHead = false`n"
    $env:GIT_EDITOR = 'true'
    G init -q -b main repo | Out-Null
    Set-Location "$Template\repo"
    Write-Text "$Template\repo\tracked.txt" "line1`n"
    G add tracked.txt | Out-Null; G commit -q -m 'c1' | Out-Null
    Add-Content tracked.txt 'line2'; Write-Text "$Template\repo\other.txt" "other`n"
    G add . | Out-Null; G commit -q -m 'c2' | Out-Null
    G tag v0.1 | Out-Null
    Add-Content tracked.txt 'line3'
    G commit -q -am 'c3' | Out-Null
    G switch -q -c feature | Out-Null
    Write-Text "$Template\repo\feature.txt" "feature`n"
    G add feature.txt | Out-Null; G commit -q -m 'c4 feature' | Out-Null
    G switch -q main | Out-Null
    G init -q --bare "$Template\bare.git" | Out-Null
    G remote add origin (FileUrl "$Template\bare.git") | Out-Null
    G push -q -u origin main 2>&1 | Out-Null
} finally { Pop-Location }

# ---------------------------------------------------------------- specs
# Cwd: root | repo | nav | newproj | otherdrive
# Setup: param($d) -> hashtable of extra tokens (optional). Runs with cwd = repo if it exists.
# Verify: param($r) -> $true / $false / $null(not checkable) or @{ ok=..; detail=.. }
# $r: Dir, Repo, Out, Err, Probe, Ctx
$Specs = @(
    # ---- Navigating Directories
    @{ T = 'cd'; Effect = 'prints the current directory'; Cwd = 'root'; Cmd = 'cd'
        Verify = { param($r) $r.Out -match [regex]::Escape($r.Dir) } }
    @{ T = 'cd <folder>'; Effect = 'shell is now in navtarget'; Cwd = 'root'; Cmd = 'cd navtarget'; Probe = 'cwd'
        Verify = { param($r) $r.Probe -ieq (Join-Path $r.Dir 'navtarget') } }
    @{ T = 'cd ..'; Effect = 'shell is now in the parent folder'; Cwd = 'nav'; Cmd = 'cd ..'; Probe = 'cwd'
        Verify = { param($r) $r.Probe -ieq $r.Dir } }
    @{ T = 'cd \'; Effect = 'shell is now at the drive root'; Cwd = 'root'; Cmd = 'cd \'; Probe = 'cwd'
        Verify = { param($r) $r.Probe -ieq ((Split-Path -Qualifier $r.Dir) + '\') } }
    @{ T = 'cd /d D:\<folder>'; Effect = 'shell switched to drive D: and the folder'; Cwd = 'otherdrive'; Cmd = 'cd /d {dtarget}'; Probe = 'cwd'
        Setup = { param($d)  $t = Join-Path $DCmdRoot ("dnav-" + (Split-Path -Leaf $d)); New-Item -ItemType Directory -Force -Path $t | Out-Null; @{ dtarget = $t } }
        Verify = { param($r) $r.Probe -ieq $r.Ctx.dtarget } }
    @{ T = 'dir'; Effect = 'lists file.txt'; Cwd = 'root'; Cmd = 'dir'
        Verify = { param($r) $r.Out -match 'file\.txt' } }
    @{ T = 'tree'; Effect = 'prints the folder tree'; Cwd = 'root'; Cmd = 'tree'
        Verify = { param($r) $r.Out -match 'navtarget' } }
    @{ T = 'cls'; Effect = 'clears the screen (not checkable when redirected)'; Cwd = 'root'; Cmd = 'cls'
        Verify = { param($r) $null } }
    # ---- Creating Folders & Files
    @{ T = 'mkdir <folder>'; Effect = 'folder newdir exists'; Cwd = 'root'; Cmd = 'mkdir newdir'
        Verify = { param($r) Test-Path -PathType Container (Join-Path $r.Dir 'newdir') } }
    @{ T = 'type nul > <file>'; Effect = 'empty file newfile.txt exists'; Cwd = 'root'; Cmd = 'type nul > newfile.txt'
        Verify = { param($r)
            $p = Join-Path $r.Dir 'newfile.txt'
            if (-not (Test-Path $p)) { return @{ ok = $false; detail = 'file not created' } }
            $len = (Get-Item $p).Length
            @{ ok = ($len -eq 0); detail = "file created, $len bytes" } } }
    # ---- Removing Folders & Files
    @{ T = 'rmdir <folder>'; Effect = 'empty folder removed'; Cwd = 'root'; Cmd = 'rmdir emptydir'
        Verify = { param($r) -not (Test-Path (Join-Path $r.Dir 'emptydir')) } }
    @{ T = 'rmdir /s /q <folder>'; Effect = 'non-empty folder removed'; Cwd = 'root'; Cmd = 'rmdir /s /q fulldir'
        Verify = { param($r) -not (Test-Path (Join-Path $r.Dir 'fulldir')) } }
    @{ T = 'del <file>'; Effect = 'file.txt deleted'; Cwd = 'root'; Cmd = 'del file.txt'
        Verify = { param($r) -not (Test-Path (Join-Path $r.Dir 'file.txt')) } }
    # ---- Copying, Moving & Renaming
    @{ T = 'copy <src> <dest>'; Effect = 'dest.txt is a copy of src.txt'; Cwd = 'root'; Cmd = 'copy src.txt dest.txt'
        Verify = { param($r) (Test-Path (Join-Path $r.Dir 'dest.txt')) -and ((Get-Content -Raw (Join-Path $r.Dir 'dest.txt')) -eq (Get-Content -Raw (Join-Path $r.Dir 'src.txt'))) } }
    @{ T = 'xcopy <src> <dest> /e /i'; Effect = 'destdir has srcdir incl. subfolders'; Cwd = 'root'; Cmd = 'xcopy srcdir destdir /e /i'
        Verify = { param($r) Test-Path (Join-Path $r.Dir 'destdir\sub\b.txt') } }
    @{ T = 'move <src> <dest>'; Effect = 'src.txt moved to moved.txt'; Cwd = 'root'; Cmd = 'move src.txt moved.txt'
        Verify = { param($r) (Test-Path (Join-Path $r.Dir 'moved.txt')) -and -not (Test-Path (Join-Path $r.Dir 'src.txt')) } }
    @{ T = 'ren <old> <new>'; Effect = 'old.txt renamed to new.txt'; Cwd = 'root'; Cmd = 'ren old.txt new.txt'
        Verify = { param($r) (Test-Path (Join-Path $r.Dir 'new.txt')) -and -not (Test-Path (Join-Path $r.Dir 'old.txt')) } }
    # ---- Viewing File Contents
    @{ T = 'type <file>'; Effect = 'prints file.txt'; Cwd = 'root'; Cmd = 'type file.txt'
        Verify = { param($r) $r.Out -match 'hello text world' } }
    @{ T = 'more <file>'; Effect = 'prints file.txt'; Cwd = 'root'; Cmd = 'more file.txt'
        Verify = { param($r) $r.Out -match 'hello text world' } }
    @{ T = 'findstr "text" <file>'; Effect = 'prints the matching line'; Cwd = 'root'; Cmd = 'findstr "text" file.txt'
        Verify = { param($r) ($r.Out -match 'hello text world') -and ($r.Out -notmatch 'second line') } }
    # ---- System Info
    @{ T = 'ver'; Effect = 'prints the Windows version'; Cwd = 'root'; Cmd = 'ver'
        Verify = { param($r) $r.Out -match 'Microsoft Windows \[Version' } }
    @{ T = 'hostname'; Effect = 'prints the host name'; Cwd = 'root'; Cmd = 'hostname'
        Verify = { param($r) $r.Out -match [regex]::Escape($env:COMPUTERNAME) } }
    @{ T = 'whoami'; Effect = 'prints the user name'; Cwd = 'root'; Cmd = 'whoami'
        Verify = { param($r) $r.Out -match [regex]::Escape($env:USERNAME) } }
    # ---- Networking
    @{ T = 'ipconfig'; Effect = 'prints IP configuration'; Cwd = 'root'; Cmd = 'ipconfig'
        Verify = { param($r) $r.Out -match 'Windows IP Configuration' } }
    @{ T = 'ping <host>'; Effect = 'gets replies from 127.0.0.1'; Cwd = 'root'; Cmd = 'ping 127.0.0.1'
        Verify = { param($r) $r.Out -match 'Reply from 127\.0\.0\.1' } }
    @{ T = 'tracert <host>'; Effect = 'traces route to 127.0.0.1'; Cwd = 'root'; Cmd = 'tracert 127.0.0.1'
        Verify = { param($r) $r.Out -match 'Trace complete' } }
    @{ T = 'nslookup <domain>'; Effect = 'resolves github.com'; Cwd = 'root'; Cmd = 'nslookup github.com'
        Verify = { param($r) $r.Out -match 'Name:\s+github\.com' } }
    @{ T = 'netstat -ano'; Effect = 'lists ports with PIDs'; Cwd = 'root'; Cmd = 'netstat -ano'
        Verify = { param($r) $r.Out -match 'LISTENING' } }
    # ---- Processes
    @{ T = 'tasklist'; Effect = 'lists processes'; Cwd = 'root'; Cmd = 'tasklist'
        Verify = { param($r) $r.Out -match 'svchost\.exe' } }
    @{ T = 'taskkill /PID <pid> /F'; Effect = 'scratch ping.exe process killed'; Cwd = 'root'; Cmd = 'taskkill /PID {pid} /F'
        Setup = { param($d)
            $p = Start-Process -FilePath "$env:SystemRoot\System32\PING.EXE" -ArgumentList '-n', '600', '127.0.0.1' -WindowStyle Hidden -PassThru
            Start-Sleep -Milliseconds 300
            if ($p.HasExited) { throw 'sleeper process exited early' }
            @{ pid = $p.Id; proc = $p } }
        Verify = { param($r) $r.Ctx.proc.Refresh(); $r.Ctx.proc.HasExited }
        Cleanup = { param($ctx) if (-not $ctx.proc.HasExited) { $ctx.proc.Kill() } } }
    @{ T = 'taskkill /IM <name.exe> /F'; Effect = 'scratch ezbsleep.exe process killed'; Cwd = 'root'; Cmd = 'taskkill /IM ezbsleep.exe /F'
        Setup = { param($d)
            Get-Process ezbsleep -ErrorAction SilentlyContinue | Stop-Process -Force
            $exe = Join-Path $d 'ezbsleep.exe'
            Copy-Item "$env:SystemRoot\System32\PING.EXE" $exe
            $mui = "$env:SystemRoot\System32\en-US\PING.EXE.mui"
            if (Test-Path $mui) { New-Item -ItemType Directory -Force "$d\en-US" | Out-Null; Copy-Item $mui "$d\en-US\ezbsleep.exe.mui" }
            $p = Start-Process -FilePath $exe -ArgumentList '-n', '600', '127.0.0.1' -WindowStyle Hidden -PassThru
            Start-Sleep -Milliseconds 300
            if ($p.HasExited) { throw 'ezbsleep exited early' }
            @{ proc = $p } }
        Verify = { param($r) -not (Get-Process ezbsleep -ErrorAction SilentlyContinue) }
        Cleanup = { param($ctx) Get-Process ezbsleep -ErrorAction SilentlyContinue | Stop-Process -Force } }
    # ---- Environment Variables
    @{ T = 'set'; Effect = 'prints environment variables'; Cwd = 'root'; Cmd = 'set'
        Verify = { param($r) $r.Out -match '(?im)^(Path|PATH)=' } }
    @{ T = 'echo %PATH%'; Effect = 'prints the PATH value'; Cwd = 'root'; Cmd = 'echo %PATH%'
        Verify = { param($r) ($r.Out -match '(?i)\\Windows') -and ($r.Out -notmatch '%PATH%') } }
    @{ T = 'set <NAME>=<value>'; Effect = 'env var EZB_NAME=ezvalue in this session'; Cwd = 'root'; Cmd = 'set EZB_NAME=ezvalue'; Probe = 'env'
        Verify = { param($r) $r.Probe.Trim() -ceq 'ezvalue' } }
    # ---- Uninstalling ezcmd
    @{ T = 'ezcmd --uninstall'; Skip = 'not run: would uninstall ezcmd; identical binary call in every shell' }

    # ---- git: Setup & Config (writes go to a per-test GIT_CONFIG_GLOBAL file)
    @{ T = 'git config --global user.name "<name>"'; Effect = 'global user.name = Ez Bench'; Cwd = 'repo'; Cmd = 'git config --global user.name "Ez Bench"'
        Verify = { param($r) (GQ config --global user.name) -ceq 'Ez Bench' } }
    @{ T = 'git config --global user.email "<email>"'; Effect = 'global user.email set'; Cwd = 'repo'; Cmd = 'git config --global user.email "bench@example.com"'
        Verify = { param($r) (GQ config --global user.email) -ceq 'bench@example.com' } }
    @{ T = 'git config --global init.defaultBranch main'; Effect = 'global init.defaultBranch = main'; Cwd = 'repo'; Cmd = 'git config --global init.defaultBranch main'
        Setup = { param($d) G config --global init.defaultBranch trunk | Out-Null }
        Verify = { param($r) (GQ config --global init.defaultBranch) -ceq 'main' } }
    @{ T = 'git config --list'; Effect = 'lists config'; Cwd = 'repo'; Cmd = 'git config --list'
        Verify = { param($r) $r.Out -match 'user\.name=' } }
    # ---- Initializing a Repo
    @{ T = 'git init'; Effect = 'newproj\.git created'; Cwd = 'newproj'; Cmd = 'git init'
        Verify = { param($r) Test-Path (Join-Path $r.Dir 'newproj\.git\HEAD') } }
    @{ T = 'git add .'; Effect = 'untracked file staged'; Cwd = 'repo'; Cmd = 'git add .'
        Setup = { param($d) Write-Text "$d\repo\untracked.txt" "u`n" }
        Verify = { param($r) (GQ diff --cached --name-only) -match 'untracked\.txt' } }
    @{ T = 'git commit -m "Initial commit"'; Effect = 'commit with subject "Initial commit"'; Cwd = 'repo'; Cmd = 'git commit -m "Initial commit"'
        Setup = { param($d) Write-Text "$d\repo\new.txt" "n`n"; G add new.txt | Out-Null }
        Verify = { param($r) (GQ log -1 --format=%s) -ceq 'Initial commit' } }
    @{ T = 'git branch -M main'; Effect = 'current branch renamed to main'; Cwd = 'repo'; Cmd = 'git branch -M main'
        Setup = { param($d) G switch -q -c trunk | Out-Null }
        Verify = { param($r) (GQ branch --show-current) -ceq 'main' } }
    @{ T = 'git remote add origin <repo-url>'; Effect = 'origin points to the bare repo'; Cwd = 'repo'; Cmd = 'git remote add origin {url}'
        Setup = { param($d) G remote remove origin | Out-Null }
        Verify = { param($r) (GQ remote get-url origin) -ceq $r.Ctx.url } }
    @{ T = 'git push -u origin main'; Effect = 'bare repo main == local HEAD'; Cwd = 'repo'; Cmd = 'git push -u origin main'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'pushme'; G commit -q -am 'to push' | Out-Null }
        Verify = { param($r) (GQ --git-dir "$($r.Dir)\bare.git" rev-parse main) -eq (GQ rev-parse HEAD) } }
    # ---- Cloning a Repo
    @{ T = 'git clone <repo-url>'; Effect = 'folder bare\ cloned'; Cwd = 'root'; Cmd = 'git clone {url}'
        Verify = { param($r) Test-Path (Join-Path $r.Dir 'bare\tracked.txt') } }
    @{ T = 'git clone <repo-url> <folder>'; Effect = 'folder clonedir\ cloned'; Cwd = 'root'; Cmd = 'git clone {url} clonedir'
        Verify = { param($r) Test-Path (Join-Path $r.Dir 'clonedir\tracked.txt') } }
    @{ T = 'git clone --depth 1 <repo-url>'; Effect = 'shallow clone in bare\'; Cwd = 'root'; Cmd = 'git clone --depth 1 {url}'
        Verify = { param($r) (GQ -C (Join-Path $r.Dir 'bare') rev-parse --is-shallow-repository) -eq 'true' } }
    # ---- Daily Workflow
    @{ T = 'git status'; Effect = 'prints status'; Cwd = 'repo'; Cmd = 'git status'
        Verify = { param($r) $r.Out -match 'On branch main' } }
    @{ T = 'git add <file>'; Effect = 'tracked.txt staged'; Cwd = 'repo'; Cmd = 'git add tracked.txt'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'change' }
        Verify = { param($r) (GQ diff --cached --name-only) -match 'tracked\.txt' } }
    @{ T = 'git commit -m "<message>"'; Effect = 'commit with subject "Bench message"'; Cwd = 'repo'; Cmd = 'git commit -m "Bench message"'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'change'; G add tracked.txt | Out-Null }
        Verify = { param($r) (GQ log -1 --format=%s) -ceq 'Bench message' } }
    @{ T = 'git pull'; Effect = 'HEAD fast-forwarded to origin/main'; Cwd = 'repo'; Cmd = 'git pull'
        Setup = { param($d) G reset -q --hard HEAD~1 | Out-Null }
        Verify = { param($r) (GQ rev-parse HEAD) -eq (GQ rev-parse origin/main) } }
    @{ T = 'git push'; Effect = 'bare repo main == local HEAD'; Cwd = 'repo'; Cmd = 'git push'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'pushme'; G commit -q -am 'to push' | Out-Null }
        Verify = { param($r) (GQ --git-dir "$($r.Dir)\bare.git" rev-parse main) -eq (GQ rev-parse HEAD) } }
    # ---- Branching
    @{ T = 'git branch'; Effect = 'lists branches'; Cwd = 'repo'; Cmd = 'git branch'
        Verify = { param($r) $r.Out -match 'feature' } }
    @{ T = 'git branch -a'; Effect = 'lists remote-tracking branches'; Cwd = 'repo'; Cmd = 'git branch -a'
        Verify = { param($r) $r.Out -match 'remotes/origin/main' } }
    @{ T = 'git switch -c <branch>'; Effect = 'on new branch ezb-new'; Cwd = 'repo'; Cmd = 'git switch -c ezb-new'
        Verify = { param($r) (GQ branch --show-current) -ceq 'ezb-new' } }
    @{ T = 'git switch <branch>'; Effect = 'on branch feature'; Cwd = 'repo'; Cmd = 'git switch feature'
        Verify = { param($r) (GQ branch --show-current) -ceq 'feature' } }
    @{ T = 'git merge <branch>'; Effect = 'feature merged into main'; Cwd = 'repo'; Cmd = 'git merge feature'
        Verify = { param($r) & git merge-base --is-ancestor feature HEAD; $LASTEXITCODE -eq 0 } }
    @{ T = 'git branch -d <branch>'; Effect = 'branch done-br deleted'; Cwd = 'repo'; Cmd = 'git branch -d done-br'
        Setup = { param($d) G branch done-br | Out-Null }
        Verify = { param($r) -not (GQ rev-parse --verify --quiet refs/heads/done-br) } }
    # ---- Remotes
    @{ T = 'git remote -v'; Effect = 'lists remotes'; Cwd = 'repo'; Cmd = 'git remote -v'
        Verify = { param($r) $r.Out -match 'origin' } }
    @{ T = 'git remote add <name> <url>'; Effect = 'remote mirror added'; Cwd = 'repo'; Cmd = 'git remote add mirror {url}'
        Verify = { param($r) (GQ remote get-url mirror) -ceq $r.Ctx.url } }
    @{ T = 'git remote set-url <name> <url>'; Effect = 'origin URL changed'; Cwd = 'repo'; Cmd = 'git remote set-url origin {url2}'
        Verify = { param($r) (GQ remote get-url origin) -ceq $r.Ctx.url2 } }
    @{ T = 'git remote remove <name>'; Effect = 'origin removed'; Cwd = 'repo'; Cmd = 'git remote remove origin'
        Verify = { param($r) -not ((GQ remote) -match 'origin') } }
    @{ T = 'git fetch <name>'; Effect = 'origin/main ref fetched'; Cwd = 'repo'; Cmd = 'git fetch origin'
        Setup = { param($d) G update-ref -d refs/remotes/origin/main | Out-Null }
        Verify = { param($r) [bool](GQ rev-parse --verify --quiet refs/remotes/origin/main) } }
    # ---- Undo & Rollback
    @{ T = 'git restore --staged <file>'; Effect = 'tracked.txt unstaged, change kept'; Cwd = 'repo'; Cmd = 'git restore --staged tracked.txt'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'change'; G add tracked.txt | Out-Null }
        Verify = { param($r) -not (GQ diff --cached --name-only) -and ((GQ diff --name-only) -match 'tracked\.txt') } }
    @{ T = 'git restore <file>'; Effect = 'tracked.txt change discarded'; Cwd = 'repo'; Cmd = 'git restore tracked.txt'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'change' }
        Verify = { param($r) -not (GQ status --porcelain) } }
    @{ T = 'git commit --amend -m "<message>"'; Effect = 'last commit subject = "Amended message"'; Cwd = 'repo'; Cmd = 'git commit --amend -m "Amended message"'
        Verify = { param($r) (GQ log -1 --format=%s) -ceq 'Amended message' } }
    @{ T = 'git reset --soft HEAD~1'; Effect = 'HEAD moved back one, changes staged'; Cwd = 'repo'; Cmd = 'git reset --soft HEAD~1'
        Setup = { param($d) @{ parent = (GQ rev-parse HEAD~1) } }
        Verify = { param($r) ((GQ rev-parse HEAD) -eq $r.Ctx.parent) -and [bool](GQ diff --cached --name-only) } }
    @{ T = 'git reset --hard HEAD~1'; Effect = 'HEAD moved back one, tree clean'; Cwd = 'repo'; Cmd = 'git reset --hard HEAD~1'
        Setup = { param($d) @{ parent = (GQ rev-parse HEAD~1) } }
        Verify = { param($r) ((GQ rev-parse HEAD) -eq $r.Ctx.parent) -and -not (GQ status --porcelain) } }
    @{ T = 'git revert <commit>'; Effect = 'revert commit created'; Cwd = 'repo'; Cmd = 'git revert {head}'
        Setup = { param($d) @{ head = (GQ rev-parse --short HEAD) } }
        Verify = { param($r) (GQ log -1 --format=%s) -like 'Revert*' } }
    # ---- Stash
    @{ T = 'git stash'; Effect = 'change stashed, tree clean'; Cwd = 'repo'; Cmd = 'git stash'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'change' }
        Verify = { param($r) [bool](GQ stash list) -and -not (GQ status --porcelain) } }
    @{ T = 'git stash list'; Effect = 'lists stash@{0}'; Cwd = 'repo'; Cmd = 'git stash list'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'change'; G stash -q | Out-Null }
        Verify = { param($r) $r.Out -match 'stash@\{0\}' } }
    @{ T = 'git stash pop'; Effect = 'stash applied and dropped'; Cwd = 'repo'; Cmd = 'git stash pop'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'change'; G stash -q | Out-Null }
        Verify = { param($r) -not (GQ stash list) -and [bool](GQ status --porcelain) } }
    @{ T = 'git stash apply'; Effect = 'stash applied and kept'; Cwd = 'repo'; Cmd = 'git stash apply'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'change'; G stash -q | Out-Null }
        Verify = { param($r) [bool](GQ stash list) -and [bool](GQ status --porcelain) } }
    @{ T = 'git stash drop'; Effect = 'stash dropped'; Cwd = 'repo'; Cmd = 'git stash drop'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'change'; G stash -q | Out-Null }
        Verify = { param($r) -not (GQ stash list) -and -not (GQ status --porcelain) } }
    @{ T = 'git stash clear'; Effect = 'all stashes removed'; Cwd = 'repo'; Cmd = 'git stash clear'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'a'; G stash -q | Out-Null; Add-Content "$d\repo\tracked.txt" 'b'; G stash -q | Out-Null }
        Verify = { param($r) -not (GQ stash list) } }
    # ---- Tags
    @{ T = 'git tag'; Effect = 'lists v0.1'; Cwd = 'repo'; Cmd = 'git tag'
        Verify = { param($r) $r.Out -match 'v0\.1' } }
    @{ T = 'git tag -a <tag> -m "<message>"'; Effect = 'annotated tag v9.9'; Cwd = 'repo'; Cmd = 'git tag -a v9.9 -m "Bench tag"'
        Verify = { param($r) (GQ cat-file -t v9.9) -eq 'tag' } }
    @{ T = 'git push origin <tag>'; Effect = 'v0.1 on the bare repo'; Cwd = 'repo'; Cmd = 'git push origin v0.1'
        Verify = { param($r) [bool](GQ --git-dir "$($r.Dir)\bare.git" rev-parse --verify --quiet refs/tags/v0.1) } }
    @{ T = 'git push origin --tags'; Effect = 'all tags on the bare repo'; Cwd = 'repo'; Cmd = 'git push origin --tags'
        Setup = { param($d) G tag v0.2 | Out-Null }
        Verify = { param($r) [bool](GQ --git-dir "$($r.Dir)\bare.git" rev-parse --verify --quiet refs/tags/v0.2) -and [bool](GQ --git-dir "$($r.Dir)\bare.git" rev-parse --verify --quiet refs/tags/v0.1) } }
    @{ T = 'git tag -d <tag>'; Effect = 'tag v0.1 deleted'; Cwd = 'repo'; Cmd = 'git tag -d v0.1'
        Verify = { param($r) -not (GQ rev-parse --verify --quiet refs/tags/v0.1) } }
    # ---- History & Diff
    @{ T = 'git log --oneline --graph'; Effect = 'prints graph'; Cwd = 'repo'; Cmd = 'git log --oneline --graph'
        Verify = { param($r) $r.Out -match '\* [0-9a-f]{7}' } }
    @{ T = 'git log -n <number>'; Effect = 'prints exactly 2 commits'; Cwd = 'repo'; Cmd = 'git log -n 2'
        Verify = { param($r) ([regex]::Matches($r.Out, '(?m)^commit [0-9a-f]{40}')).Count -eq 2 } }
    @{ T = 'git diff'; Effect = 'prints unstaged diff'; Cwd = 'repo'; Cmd = 'git diff'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'change' }
        Verify = { param($r) $r.Out -match 'diff --git' } }
    @{ T = 'git diff --staged'; Effect = 'prints staged diff'; Cwd = 'repo'; Cmd = 'git diff --staged'
        Setup = { param($d) Add-Content "$d\repo\tracked.txt" 'change'; G add tracked.txt | Out-Null }
        Verify = { param($r) $r.Out -match 'diff --git' } }
    @{ T = 'git show <commit>'; Effect = 'shows the commit'; Cwd = 'repo'; Cmd = 'git show {head}'
        Setup = { param($d) @{ head = (GQ rev-parse --short HEAD); full = (GQ rev-parse HEAD) } }
        Verify = { param($r) $r.Out -match $r.Ctx.full } }
    @{ T = 'git blame <file>'; Effect = 'annotates tracked.txt'; Cwd = 'repo'; Cmd = 'git blame tracked.txt'
        Verify = { param($r) $r.Out -match 'line3' } }
    # ---- Cleanup & Maintenance
    @{ T = 'git clean -n'; Effect = 'previews junk.txt, keeps it'; Cwd = 'repo'; Cmd = 'git clean -n'
        Setup = { param($d) Write-Text "$d\repo\junk.txt" 'j' }
        Verify = { param($r) ($r.Out -match 'Would remove junk\.txt') -and (Test-Path (Join-Path $r.Repo 'junk.txt')) } }
    @{ T = 'git clean -fd'; Effect = 'untracked file and dir removed'; Cwd = 'repo'; Cmd = 'git clean -fd'
        Setup = { param($d) Write-Text "$d\repo\junk.txt" 'j'; New-Item -ItemType Directory "$d\repo\junkdir" | Out-Null; Write-Text "$d\repo\junkdir\x.txt" 'x' }
        Verify = { param($r) -not (Test-Path (Join-Path $r.Repo 'junk.txt')) -and -not (Test-Path (Join-Path $r.Repo 'junkdir')) } }
    @{ T = 'git remote prune origin'; Effect = 'stale origin/gone ref pruned'; Cwd = 'repo'; Cmd = 'git remote prune origin'
        Setup = { param($d) G update-ref refs/remotes/origin/gone HEAD | Out-Null }
        Verify = { param($r) -not (GQ rev-parse --verify --quiet refs/remotes/origin/gone) } }
    @{ T = 'git branch --merged'; Effect = 'lists merged branches'; Cwd = 'repo'; Cmd = 'git branch --merged'
        Verify = { param($r) $r.Out -match 'main' } }
    @{ T = 'git gc'; Effect = 'objects packed'; Cwd = 'repo'; Cmd = 'git gc'
        Verify = { param($r) [bool](Get-ChildItem (Join-Path $r.Repo '.git\objects\pack\*.pack') -ErrorAction SilentlyContinue) } }
    # ---- bisect
    @{ T = 'git bisect start'; Effect = 'bisect session started'; Cwd = 'repo'; Cmd = 'git bisect start'
        Verify = { param($r) Test-Path (Join-Path $r.Repo '.git\BISECT_START') } }
    @{ T = 'git bisect bad'; Effect = 'HEAD marked bad'; Cwd = 'repo'; Cmd = 'git bisect bad'
        Setup = { param($d) G bisect start | Out-Null }
        Verify = { param($r) [bool](GQ rev-parse --verify --quiet refs/bisect/bad) } }
    @{ T = 'git bisect good <commit>'; Effect = 'first commit marked good'; Cwd = 'repo'; Cmd = 'git bisect good {first}'
        Setup = { param($d) $f = (GQ rev-list --max-parents=0 HEAD); G bisect start | Out-Null; G bisect bad | Out-Null; @{ first = $f.Substring(0, 7); firstFull = $f } }
        Verify = { param($r) [bool](GQ rev-parse --verify --quiet "refs/bisect/good-$($r.Ctx.firstFull)") } }
    @{ T = 'git bisect reset'; Effect = 'bisect session ended'; Cwd = 'repo'; Cmd = 'git bisect reset'
        Setup = { param($d) G bisect start | Out-Null; G bisect bad | Out-Null }
        Verify = { param($r) -not (Test-Path (Join-Path $r.Repo '.git\BISECT_START')) } }
)

$SpecByT = @{}
foreach ($s in $Specs) { $SpecByT[$s.T] = $s }

# ---------------------------------------------------------------- runner
function Decode-Clixml([string] $s) {
    if ($s -notmatch '#< CLIXML') { return $s }
    $parts = [regex]::Matches($s, '<S S="Error">(.*?)</S>') | ForEach-Object { $_.Groups[1].Value }
    $txt = ($parts -join '') -replace '_x000D_', '' -replace '_x000A_', "`n"
    [System.Net.WebUtility]::HtmlDecode($txt)
}

function Invoke-InShell {
    param([string] $Shell, [string] $Command, [string] $Probe, [string] $Cwd, [hashtable] $Env)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Shells[$Shell].File
    $psi.WorkingDirectory = $Cwd
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($k in $Env.Keys) { $psi.Environment[$k] = $Env[$k] }
    if ($Shell -eq 'cmd') {
        $line = "$Command & call echo __EZB_EL__=%^ERRORLEVEL%"
        if ($Probe -eq 'cwd') { $line += ' & call echo __EZB_PROBE__=%^CD%' }
        if ($Probe -eq 'env') { $line += ' & call echo __EZB_PROBE__=%^EZB_NAME%' }
        # /s: strip only the outer quotes, run the rest exactly as typed
        $psi.Arguments = '/d /s /c "' + $line + '"'
    } else {
        $script = "`$ProgressPreference='SilentlyContinue'`n$Command`n" +
        "`$__ezbOk = `$?; `$__ezbLec = `$LASTEXITCODE`n" +
        "'__EZB_OK__=' + `$__ezbOk`n'__EZB_LEC__=' + `$__ezbLec`n"
        if ($Probe -eq 'cwd') { $script += "'__EZB_PROBE__=' + (Get-Location).ProviderPath`n" }
        if ($Probe -eq 'env') { $script += "'__EZB_PROBE__=' + `$env:EZB_NAME`n" }
        foreach ($a in @('-NoProfile', '-Command', $script)) { $psi.ArgumentList.Add($a) }
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()   # no one is at the keyboard: prompts get EOF
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $timedOut = -not $p.WaitForExit($TimeoutSec * 1000)
    if ($timedOut) { try { $p.Kill($true) } catch {} ; $p.WaitForExit(10000) | Out-Null }
    $out = $outTask.GetAwaiter().GetResult()
    $err = (Decode-Clixml ($errTask.GetAwaiter().GetResult())) -replace "\e\[[0-9;?]*[A-Za-z]", ''
    $sw.Stop()

    $ok = $null; $code = $null; $probeVal = $null
    if ($Shell -eq 'cmd') {
        if ($out -match '__EZB_EL__=(-?\d+)') { $code = [int]$Matches[1]; $ok = ($code -eq 0) }
    } else {
        if ($out -match '__EZB_OK__=(\w+)') { $ok = ($Matches[1] -eq 'True') }
        if ($out -match '__EZB_LEC__=(-?\d+)') { $code = [int]$Matches[1] }
    }
    if ($out -match '__EZB_PROBE__=(.*)') { $probeVal = $Matches[1].TrimEnd("`r") }
    $clean = ($out -split "`r?`n" | Where-Object { $_ -notmatch '__EZB_' }) -join "`n"
    [pscustomobject]@{
        Ok = $ok; Code = $code; ExitCode = $p.ExitCode; TimedOut = $timedOut
        Out = $clean; Err = $err.Trim(); Probe = $probeVal; Ms = $sw.ElapsedMilliseconds
    }
}

function First-ErrorLine([string] $err) {
    $lines = @($err -split "`r?`n" | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and $_ -notmatch '^(At line|At char|\+|~|\||Line \||CategoryInfo|FullyQualifiedErrorId)' })
    if (-not $lines) { return $null }
    # pwsh may print "Cmdlet:" and the message on separate lines
    if ($lines[0] -match ':$' -and $lines.Count -gt 1) { return "$($lines[0]) $($lines[1])" }
    $lines[0]
}

# ---------------------------------------------------------------- main loop
$Results = [System.Collections.Generic.List[object]]::new()
$seen = @{}
$n = 0
foreach ($rc in $Resolved) {
    if ($seen.ContainsKey($rc.Template)) { continue }
    $seen[$rc.Template] = $true
    $spec = $SpecByT[$rc.Template]
    $row = [ordered]@{ Tool = $rc.Tool; Section = $rc.Section; Template = $rc.Template; Note = $rc.Note; Command = $null; Effect = $null; Skip = $null; Shells = [ordered]@{} }
    if (-not $spec) { $row.Skip = 'HARNESS GAP: no spec for this command'; $Results.Add([pscustomobject]$row); continue }
    if ($spec.Skip) { $row.Skip = $spec.Skip; $row.Command = $rc.Template; $Results.Add([pscustomobject]$row); continue }
    $row.Effect = $spec.Effect

    foreach ($sh in $Shells.Keys) {
        $n++
        $dir = Join-Path $Base ("t{0:d3}-{1}" -f $n, $sh)
        Copy-Item -Recurse -Force $Template $dir
        $envs = @{ GIT_CONFIG_GLOBAL = "$dir\gitconfig"; GIT_EDITOR = 'true'; GIT_TERMINAL_PROMPT = '0'; NO_COLOR = '1' }
        $env:GIT_CONFIG_GLOBAL = $envs.GIT_CONFIG_GLOBAL
        $repo = Join-Path $dir 'repo'
        Push-Location $repo
        $ctx = @{ url = (FileUrl "$dir\bare.git"); url2 = "$dir\bare.git" }
        try {
            G remote set-url origin $ctx.url | Out-Null
            if ($spec.Setup) { $extra = & $spec.Setup $dir; if ($extra -is [hashtable]) { foreach ($k in $extra.Keys) { $ctx[$k] = $extra[$k] } } }
        } finally { Pop-Location }

        $cmdText = $spec.Cmd
        foreach ($k in $ctx.Keys) { $cmdText = $cmdText.Replace("{$k}", [string]$ctx[$k]) }
        # sanity: the concrete command must have the exact shape ezcmd printed
        $shape = '^' + (([regex]::Escape($rc.Template)) -replace '<[^>]+>', '.+') + '$'
        if ($cmdText -notmatch $shape) { throw "Spec command '$cmdText' does not match template '$($rc.Template)'" }
        $row.Command = $cmdText -replace [regex]::Escape($dir), '<scratch>' -replace [regex]::Escape(($dir -replace '\\', '/')), '<scratch>'

        $cwd = switch ($spec.Cwd) {
            'root' { $dir } 'repo' { $repo } 'nav' { Join-Path $dir 'navtarget' } 'newproj' { Join-Path $dir 'newproj' }
            'otherdrive' { $od = Join-Path $OtherDriveDir (Split-Path -Leaf $dir); New-Item -ItemType Directory -Force $od | Out-Null; $od }
        }
        $res = Invoke-InShell -Shell $sh -Command $cmdText -Probe $spec.Probe -Cwd $cwd -Env $envs

        Push-Location $repo
        try {
            $vr = & $spec.Verify ([pscustomobject]@{ Dir = $dir; Repo = $repo; Out = $res.Out; Err = $res.Err; Probe = $res.Probe; Ctx = $ctx; Shell = $sh })
        } catch { $vr = @{ ok = $false; detail = "verify threw: $($_.Exception.Message)" } }
        finally { Pop-Location }
        if ($spec.Cleanup) { try { & $spec.Cleanup $ctx } catch {} }
        $effect = $vr; $detail = $null
        if ($vr -is [hashtable]) { $effect = $vr.ok; $detail = $vr.detail }
        if ($null -ne $effect) { $effect = [bool]$effect }

        $row.Shells[$sh] = [pscustomobject]@{
            Ok = $res.Ok; Code = $res.Code; ExitCode = $res.ExitCode; TimedOut = $res.TimedOut; Effect = $effect; Detail = $detail
            Err = $res.Err; ErrLine = (First-ErrorLine $res.Err); Out = $res.Out; Probe = $res.Probe; Ms = $res.Ms
        }
        Write-Host ("[{0,-5}] {1,-45} ok={2} code={3} effect={4} {5}ms {6}" -f $sh, $cmdText.Substring(0, [Math]::Min(45, $cmdText.Length)), $res.Ok, $res.Code, $effect, $res.Ms, (First-ErrorLine $res.Err))
    }
    $Results.Add([pscustomobject]$row)
}

# ---------------------------------------------------------------- report
function Cell($s) {
    if (-not $s) { return 'n/a' }
    if ($s.TimedOut) { return "⏱ hung, killed after ${TimeoutSec}s" }
    if ($null -eq $s.Ok) { return '❌ did not run (parse error)' }
    $d = if ($s.Detail) { " ($($s.Detail))" } else { '' }
    if ($null -eq $s.Effect) { if ($s.Ok) { return '✅ ran, exit 0 (effect not checkable)' } else { return "❌ error, exit $($s.Code)" } }
    if ($s.Effect -and $s.Ok) { return "✅$d" }
    if ($s.Effect -and -not $s.Ok) { return "⚠️ effect happened but reported error$d" }
    if (-not $s.Effect -and $s.Ok) { return "❌ **silent**: no error, no effect$d" }
    return "❌ error, no effect$d"
}
function Esc([string] $s) { if (-not $s) { return '' } ($s -replace '\|', '\|' -replace '`', "'" -replace '\r?\n', ' ').Trim() }

$md = [System.Text.StringBuilder]::new()
$psv = (& $Shells.winps.File -NoProfile -Command '$PSVersionTable.PSVersion.ToString()').Trim()
$pwv = (& $Shells.pwsh.File -NoProfile -Command '$PSVersionTable.PSVersion.ToString()').Trim()
$osv = (cmd /d /c ver | Out-String).Trim()
[void]$md.AppendLine("## ezCMD Windows commands: cmd vs Windows PowerShell vs pwsh")
[void]$md.AppendLine()
[void]$md.AppendLine("Runner: $osv · Windows PowerShell $psv · pwsh $pwv · $(git --version)")
[void]$md.AppendLine()
[void]$md.AppendLine("Every command is the exact text ``ezcmd --help -windows`` printed (placeholders filled), run alone in a fresh scratch copy, as ``cmd /d /s /c ""<command>""``, ``powershell -NoProfile -Command <command>`` and ``pwsh -NoProfile -Command <command>``. Stdin is closed (no keyboard). ✅ = no error and the effect was verified; ❌ **silent** = shell reported success but nothing happened.")
[void]$md.AppendLine()
[void]$md.AppendLine('| # | Command (as run) | Intended effect | cmd | Windows PowerShell | pwsh | Error snippet |')
[void]$md.AppendLine('|---|---|---|---|---|---|---|')
$i = 0
foreach ($r in $Results) {
    $i++
    if ($r.Skip) {
        [void]$md.AppendLine("| $i | ``$(Esc $r.Template)`` | $(Esc $r.Note) | – | – | – | $(Esc $r.Skip) |")
        continue
    }
    $snips = @()
    foreach ($sh in 'winps', 'pwsh', 'cmd') {
        $s = $r.Shells[$sh]
        if ($s -and (($s.Ok -eq $false) -or ($s.Effect -eq $false) -or $s.TimedOut -or $null -eq $s.Ok) -and $s.ErrLine) {
            $label = @{ cmd = 'cmd'; winps = 'WinPS'; pwsh = 'pwsh' }[$sh]
            $line = $s.ErrLine; if ($line.Length -gt 160) { $line = $line.Substring(0, 157) + '...' }
            $snips += "**${label}:** $(Esc $line)"
        }
    }
    [void]$md.AppendLine("| $i | ``$(Esc $r.Command)`` | $(Esc $r.Effect) | $(Cell $r.Shells.cmd) | $(Cell $r.Shells.winps) | $(Cell $r.Shells.pwsh) | $($snips -join '<br>') |")
}
[void]$md.AppendLine()
$count = @{ cmd = 0; winps = 0; pwsh = 0 }; $tested = 0
foreach ($r in $Results) {
    if ($r.Skip) { continue }; $tested++
    foreach ($sh in @('cmd', 'winps', 'pwsh')) { $s = $r.Shells[$sh]; if ($s -and $s.Ok -and $s.Effect -ne $false -and -not $s.TimedOut) { $count[$sh]++ } }
}
[void]$md.AppendLine("**Worked:** cmd $($count.cmd)/$tested · Windows PowerShell $($count.winps)/$tested · pwsh $($count.pwsh)/$tested (distinct commands; ``git add .`` appears twice in ezcmd and is tested once).")
[void]$md.AppendLine()
[void]$md.AppendLine('### Notes')
foreach ($note in $Notes) { [void]$md.AppendLine("- $note") }
[void]$md.AppendLine('- `git` runs with `GIT_CONFIG_GLOBAL` pointing at a per-test file (so `--global` writes stay in scratch), `GIT_EDITOR=true` (so `git revert` does not wait for an editor) and `GIT_TERMINAL_PROMPT=0`. `<repo-url>` is a `file:///` URL to a local bare repo.')
[void]$md.AppendLine('- `cls`/`more` are interactive by nature; with output redirected the run only shows whether the shell accepts the command.')

$mdText = $md.ToString()
Set-Content -Path (Join-Path $OutDir 'results.md') -Value $mdText -Encoding utf8
$Results | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $OutDir 'results.json') -Encoding utf8
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $mdText -Encoding utf8 }

# full per-shell detail for failures
$detail = [System.Text.StringBuilder]::new()
foreach ($r in $Results) {
    if ($r.Skip) { continue }
    foreach ($sh in $r.Shells.Keys) {
        $s = $r.Shells[$sh]
        [void]$detail.AppendLine("===== [$sh] $($r.Command)  ok=$($s.Ok) code=$($s.Code) exit=$($s.ExitCode) effect=$($s.Effect) timeout=$($s.TimedOut) probe=$($s.Probe)")
        if ($s.Out) { [void]$detail.AppendLine('--- stdout'); [void]$detail.AppendLine(($s.Out.Substring(0, [Math]::Min(1500, $s.Out.Length)))) }
        if ($s.Err) { [void]$detail.AppendLine('--- stderr'); [void]$detail.AppendLine($s.Err) }
    }
}
Set-Content -Path (Join-Path $OutDir 'details.txt') -Value $detail.ToString() -Encoding utf8

if ($SubstUsed) { subst D: /d }
Get-Process ezbsleep -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host $mdText
$gaps = @($Results | Where-Object { $_.Skip -like 'HARNESS GAP*' })
if ($gaps.Count) { throw "Harness gap: no spec for $($gaps.Template -join ', ')" }
