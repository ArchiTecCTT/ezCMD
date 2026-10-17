# ezCMD

**Type what you want to do. Get the commands, in order.**

ezCMD is a tiny, offline command-line cheatsheet. Instead of a flat list, you describe a task (`initializing repo`) and it prints the full ordered workflow for **your** operating system, with a one-line explanation beside every command.

> **Status:** v0.1 — fully functional. Grab a binary from [Releases](https://github.com/ItzEvhyx/ezCMD/releases) or build from source.

---

## Preview

```
$ ezcmd initializing repo

 ___[ Initializing a Repo ]__________________________________________________________
|
|  git init                          --- Initializes a repo in the current folder
|  git add .                         --- Stages all new and changed files
|  git commit -m "Initial commit"    --- Saves the staged files as the first commit
|  git branch -M main                --- Renames the current branch to main
|  git remote add origin <repo-url>  --- Links the repo to a remote on GitHub
|  git push -u origin main           --- Uploads main and sets it as the upstream
|____________________________________________________________________________________
```

> In a real terminal the frame and title are dimmed, commands are **bold**, and `<placeholders>` are highlighted in yellow. Color switches off automatically in pipes or when `NO_COLOR` is set.

---

## Features

- **Task-based search:** ask for what you want to do, not the command name.
- **Fuzzy matching:** typos, word order, and synonyms still find the right section. It searches titles, aliases, command text, and notes.
- **OS-aware:** detects Windows, Linux, or macOS and shows only commands that work there.
- **Notes on every line:** a right-aligned description beside each command.
- **Colored, framed output:** easy to scan, and it switches off automatically in pipes or when `NO_COLOR` is set.
- **Fully offline:** content is compiled into the binary. No network, no accounts, no telemetry.
- **Extremely lightweight:** it runs only when you call it, then exits. No daemon, no background resource use.

---

## Usage

```
ezcmd <query>                          Find a section or command
ezcmd --help                           Show every section (for your OS)
ezcmd --help -<tool>                   Show one tool's sections
ezcmd --help -<tool> -<section>        Show one section
ezcmd --help -<os>                     Show everything in another OS's commands
ezcmd --version                        Print the version
ezcmd --plain <query>                  No color or framing (good for scripts)
```

### Examples

```
ezcmd initializing repo                 # ordered steps to start a repo
ezcmd undo last commit                  # rollback options
ezcmd -- reset --hard                   # search by command text (use -- if the query starts with -)
ezcmd --help -git                       # all Git sections
ezcmd --help -git -initialize repo      # one specific section
ezcmd --help -windows                   # everything, as Windows commands
ezcmd --help -windows -git              # Git sections, Windows view
```

### When a query is ambiguous

```
$ ezcmd undo

Multiple matches for "undo":
  1. Undo & Rollback
  2. Undoing the Last Commit
  3. Restoring a Deleted File
Choose [1/2/3]:
```

---

## What's covered

- **Git:** setup and config, initializing a repo, cloning, daily workflow, branching, remotes, undo and rollback, stash, tags, history and diff, cleanup, bisect.
- **Shell basics (per OS):** navigating directories, creating, removing, copying, moving and renaming files and folders, viewing file contents, system info, networking, processes, environment variables.

On Windows, shell commands target **CMD**.

---

## Supported platforms

| OS | Status |
|---|---|
| Windows 10+ | ✅ Supported |
| Linux (x86_64 / aarch64) | ✅ Supported |
| macOS (x86_64 / Apple Silicon) | ✅ Supported |

Works in any terminal emulator.

---

## Installation

### Prebuilt binaries

Download the latest release for your platform from [GitHub Releases](https://github.com/ItzEvhyx/ezCMD/releases), extract, and place the `ezcmd` binary somewhere on your `PATH`.

### From source

```bash
git clone https://github.com/ItzEvhyx/ezCMD.git
cd ezCMD
cargo build --release
# binary: target/release/ezcmd
```

Requires Rust 1.70+.

---

## How content works

All commands live in plain TOML files in `data/`, one file per tool, and are compiled into the binary at build time. Nothing is looked up at runtime.

```toml
tool = "git"

[[section]]
title   = "Initializing a Repo"
aliases = ["init repo", "start repo", "new project", "create repository"]

  [[section.command]]
  cmd  = "git init"
  note = "Initializes a repo in the current folder"
```

OS-specific commands use keys that override `cmd`:

```toml
  [[section.command]]
  note    = "Removes a folder and everything inside it"
  windows = "rmdir /s /q <folder>"
  unix    = "rm -rf <folder>"
```

Precedence: `windows` / `linux` / `macos`, then `unix`, then `cmd`.

### Adding a section
1. Open the right file in `data/` (or create one for a new tool).
2. Add a `[[section]]` with a title, aliases, and commands with notes.
3. Run `cargo test`. The build validates the format.
4. Open a pull request.

---

## Tech

- **Language:** Rust
- **Design goals:** under 20 ms startup, under 3 MB binary, under 10 MB memory, no background processes
- **No telemetry, no network access**

See [PRD.md](PRD.md) for the full requirements.

---

## Roadmap

**v0.1:** core search, OS-aware output, `--help` family, Git and shell content.

**Later:** personal sheets, shell keybind, community packs, more tools (npm, Docker, Python, SSH, Flutter), PowerShell support, danger flags for destructive commands.

---

## Contributing

Content contributions (new sections, better aliases, fixes) are very welcome. See "Adding a section" above. A full `CONTRIBUTING.md` will come with the first release.

## License

TBD.
