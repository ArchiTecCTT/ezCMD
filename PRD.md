# ezCMD PRD

**Author:** Evhyy
**Status:** Draft
**Target Date:** No fixed date. Work proceeds milestone by milestone (see Section 6).

---

## 1. Document Overview

| Field | Value |
|---|---|
| **Product Name** | ezCMD (command: `ezcmd`) |
| **One-liner** | Type what you want to do. Get the commands, in order. |
| **Status** | Draft |
| **Target Release / Timeline** | Not fixed. v0.1 (MVP) first, later releases as time allows |
| **Key Contributors** | Evhyy (product owner, lead developer, designer) |
| **Primary Language** | Rust |
| **Platforms** | Windows, Linux, macOS |

---

## 2. Context & Objectives

### 2.1 Problem Statement
Beginners and busy developers keep forgetting terminal commands, especially multi-step ones like creating a repo and pushing it for the first time. Looking them up means leaving the terminal for a browser, wading through long articles or one-line answers, and then discovering the command differs on your operating system. Existing cheatsheets are flat reference lists. They don't answer "I want to do X" with an ordered, ready-to-run list.

### 2.2 Goals & Business Value
1. **Answer a task with an ordered command list.** Querying `initializing repo` returns the full workflow, not one command.
2. **Stay in the terminal.** No browser, no network, no account.
3. **Be OS-aware.** The tool detects the OS and shows only the commands that work there.
4. **Be extremely lightweight.** It runs only when invoked, like zoxide or atuin. There is no daemon and no background resource use when no terminal is open.
5. **Explain every command inline.** Each line has a short right-aligned description, so the output teaches as well as reminds.
6. **Be easy to extend.** Content lives in plain text files, so adding a section never requires touching code.

This is a personal and open-source utility. Its value is learning, portfolio quality, and day-to-day usefulness, not revenue.

### 2.3 Non-Goals (v0.1)
- **Not a command executor.** It prints commands and never runs them.
- **No AI or LLM fallback.** Matching is local only.
- **No network access of any kind:** no lookups, updates, telemetry, or accounts.
- **No background process, daemon, or shell hook** required for core use.
- **No cross-OS display in normal use.** The MVP shows only the detected OS's commands. The one exception is the explicit `--help -<os>` view (FR-8).
- **No personal sheets, community packs, or shell keybind** in v0.1. These are planned for later releases.
- **No GUI.**
- **No long-form explanations.** One line per command, nothing more.

---

## 3. Target Audience & User Stories

### 3.1 Personas
| Persona | Description | Needs |
|---|---|---|
| **The Beginner** | Student learning Git and the command line | Ordered steps, plain-language notes, forgiving search |
| **The Switcher** | Developer who moves between Windows and Linux | The right command for the current OS, plus a quick way to see the other OS's equivalent |
| **The Terminal Minimalist** | Experienced user who hates leaving the terminal | Instant results, tiny footprint, zero setup |

### 3.2 User Stories
- As a **beginner**, I want to type `ezcmd initializing repo` so that I get every command needed in the right order.
- As a **beginner**, I want a short note beside each command so that I understand what it does.
- As a **user who misspells things**, I want fuzzy matching so that `initalize repo` still finds the right section.
- As a **user with a vague query**, I want to choose from a numbered list when several sections match so that I get the one I meant.
- As a **Linux user**, I want to see only Linux commands so that nothing I copy fails on my machine.
- As a **Windows user**, I want CMD equivalents of everyday commands such as `mkdir`, `rmdir`, and `cd` so that I don't have to translate from tutorials.
- As a **developer switching machines**, I want `ezcmd --help -windows` so that I can see the Windows version of every command from my Linux box.
- As a **user who knows the command but not the section**, I want to search by command text (for example `reset --hard`) so that I can find what it belongs to.
- As a **Git user**, I want `ezcmd --help -git` so that I can browse all Git sections and nothing else.
- As a **minimalist**, I want the tool to use no resources when I'm not calling it so that it never slows my system.
- As a **contributor**, I want to add a section by editing a text file so that I never need to learn the codebase.

---

## 4. Technical Requirements & User Experience

### 4.1 Functional Requirements

**FR-1: Query lookup.** `ezcmd <query>` takes all remaining arguments as one free-text query (`ezcmd initializing repo` works without quotes). It returns the best-matching section for the detected OS. A query that begins with `-` must follow `--` (for example `ezcmd -- --hard`).

**FR-2: Fuzzy matching.** A query is matched against four fields of every section: title, aliases, command text, and command notes. Matching is case-insensitive, ignores word order, and tolerates typos. Title and alias matches rank above command-text matches. Only sections for the detected OS are searched.

**FR-3: Ambiguity prompt.** If the top results are too close to call, ezcmd lists up to 3 and asks the user to choose:
```
Multiple matches for "undo":
  1. Undo & Rollback
  2. Undoing the Last Commit
  3. Restoring a Deleted File
Choose [1/2/3]:
```
If stdin is not a terminal (piped), skip the prompt, print the single best match, and exit normally.

**FR-4: No match.** If nothing scores above the threshold, print `No match for "<query>"`, followed by the 3 closest section titles, and exit with a non-zero code.

**FR-5: OS detection.** The OS is determined from the compile target (`std::env::consts::OS`), at no runtime cost. Supported: `windows`, `linux`, `macos`. The MVP shows only that OS's commands. On Windows, commands target **CMD**. If a command has no equivalent on the current OS, it is shown dimmed with the note `No equivalent on <OS>`, or omitted if the whole section has none.

**FR-6: Section output format.** Each section is drawn in an ASCII frame, with a colored title, aligned commands, and a right-aligned note on every line (see Section 4.2). Notes are always shown.

**FR-7: Full help.**
- `ezcmd --help` prints a short usage header followed by **every section of every tool**, for the detected OS.
- `ezcmd --help -<tool>` (for example `-git`) prints every section of that tool only.
- `ezcmd --help -<tool> -<section words>` (for example `-git -initialize repo`) prints one section. The section is fuzzy-matched, so `-initialize repo` and `-initializing a repo` both work.
- Unknown tool names print the list of available tools.

**FR-8: OS equivalents view.** Adding an OS flag to `--help` shows the same content in that OS's commands:
- `ezcmd --help -windows` is the full dump in Windows commands.
- `ezcmd --help -linux`, `ezcmd --help -macos` work the same way.
- Flags combine: `ezcmd --help -windows -git -initialize repo`.
- This is a view only. Normal queries (FR-1) always use the detected OS.

**FR-9: Offline, file-based content.**
- Sections are authored in plain-text files in the repository's `data/` folder (see Section 4.4).
- Files are compiled into the binary at build time, so the installed tool is a single file with no runtime file lookups and no network access.

**FR-10: Color.**
- Colors are applied as in atuin's help output (see Section 4.2).
- Color is disabled automatically when output is not a terminal, when `NO_COLOR` is set, or with `--plain`.
- On Windows, enable ANSI virtual-terminal processing at startup, and fall back to plain output if that fails.

**FR-11: Other flags.** `--version` prints the version. `--plain` disables color and framing characters, leaving only `command --- note` lines for scripts and pipes.

**FR-12: Exit codes.** `0` success, `1` no match, `2` invalid arguments.

**Edge cases**
- Narrow terminals (under 80 columns): notes drop onto the line below the command, indented.
- Placeholders such as `<url>` or `<branch>` are printed literally and highlighted.
- Empty query (`ezcmd` with no arguments) prints the short usage header and a pointer to `ezcmd --help`.
- The same string can be both a tool and an OS name only if a future tool is named after an OS. Names are checked as OS first, then tool.
- Terminal width is read at runtime, and a failure to read it defaults to 80.

### 4.2 User Interface / Design

ezCMD is text only. There are no mockups or Figma files, and this section is the design spec.

**Section frame:** only ASCII characters (`_`, `|`, `[`, `]`), so it renders in every terminal on every OS, including legacy ones.

```
 ___[ Initializing a Repo ]_________________________________________________
|
|  git init                        --- Initializes a repo in the current folder
|  git add .                       --- Stages all new and changed files
|  git commit -m "Initial commit"  --- Saves the staged files as the first commit
|  git branch -M main              --- Renames the current branch to main
|  git remote add origin <url>     --- Links the repo to a remote on GitHub
|  git push -u origin main         --- Uploads main and sets it as the upstream
|___________________________________________________________________________
```

**Colors (modeled on atuin's help screen):**
| Element | Style |
|---|---|
| Section title in `[ ]` | Bold cyan |
| Frame characters (`_`, `|`) | Dim gray |
| Commands | Bold, default foreground |
| Placeholders (`<url>`) | Yellow |
| `---` separator | Dim gray |
| Notes | Default foreground, slightly dimmed |
| Prompts and errors | Bold, with errors in red |

**Layout rules**
- Commands within a section are padded so the `---` separators line up in one column.
- Section width follows the terminal width, with a minimum of 60 columns.
- Meaning never relies on color alone, so the output is readable in plain mode.

**Help header**
```
ezcmd 0.1.0
Find the right command, in order.

USAGE:
  ezcmd <query>                          Find a section or command
  ezcmd --help                           Show every section (this OS)
  ezcmd --help -<tool>                   Show one tool's sections
  ezcmd --help -<tool> -<section>        Show one section
  ezcmd --help -<os>                     Show everything for another OS
```

### 4.3 Non-Functional Requirements

**Performance**
- Cold start to output: under 20 ms (target under 10 ms).
- Peak memory: under 10 MB.
- Release binary: under 3 MB (target under 2 MB).
- Zero background processes, zero timers, zero network calls. When ezcmd is not being invoked, it uses no resources.

**Security & Privacy**
- Never executes the commands it displays.
- Makes no network connections and collects no data. Nothing is written to disk in v0.1.
- No elevated permissions needed.

**Accessibility** (WCAG does not apply to a terminal tool, so these are the equivalents)
- Works with `NO_COLOR`, plain mode, and screen readers.
- Color is never the only carrier of meaning.
- No box-drawing Unicode in v0.1, so there are no missing-glyph issues.

**Platform Support**
- Windows 10 and later (CMD), Linux (glibc and musl), macOS (Intel and Apple Silicon).
- Terminal-agnostic: any terminal emulator, including Windows Terminal, GNOME Terminal, Kitty, Alacritty, iTerm2, and the legacy Windows console.

**Reliability**
- Content files are validated at build time. A malformed section fails the build and never reaches users.
- Unit tests for matching, argument parsing, and OS selection. Snapshot tests for output.

### 4.4 Content & Data Design

Content files are authored in **TOML**, one file per tool, in `data/`:

```
data/
  git.toml        # Git sections
  shell.toml      # Filesystem & CMD/shell basics
  ...
```

Entry format:

```toml
tool = "git"

[[section]]
title   = "Initializing a Repo"
aliases = ["init repo", "start repo", "new project", "create repository"]

  [[section.command]]
  cmd  = "git init"
  note = "Initializes a repo in the current folder"

  [[section.command]]
  cmd  = "git add ."
  note = "Stages all new and changed files"
```

OS-specific commands use keys that override `cmd`:

```toml
[[section]]
title   = "Removing a Folder"
aliases = ["delete folder", "remove directory"]

  [[section.command]]
  note    = "Removes a folder and everything inside it"
  windows = "rmdir /s /q <folder>"
  unix    = "rm -rf <folder>"
```

Precedence: exact OS key (`windows` / `linux` / `macos`), then `unix` (Linux + macOS), then `cmd` (all OSes).

**Launch content (MVP)**
- **Git:** setup and config, initializing a repo, cloning, daily workflow, branching, remotes, undo and rollback, stash, tags, history and diff, cleanup, bisect.
- **Shell basics (per OS):** navigating directories, creating folders and files, removing, copying/moving/renaming, viewing file contents, system info, networking, processes, environment variables.

### 4.5 Technology Stack

| Area | Choice |
|---|---|
| **Language** | **Rust** (stable) |
| **Argument parsing** | Hand-written parser. The `-git` / `-windows` style (single dash, multi-letter) isn't supported cleanly by `clap`, which would read `-git` as bundled short flags, and skipping it also reduces binary size |
| **Fuzzy matching** | `nucleo-matcher` or `fuzzy-matcher`, with a small in-house scorer over aliases |
| **Content parsing** | `serde` + `toml`, run in `build.rs` so parsing happens at build time and the binary ships pre-parsed static data |
| **Content embedding** | Compile-time embedding (`include_str!` or generated static tables) |
| **Color / terminal** | `owo-colors` or `anstyle`; Windows VT enablement via `enable-ansi-support`; terminal width via `terminal_size` |
| **Testing** | Built-in `cargo test`, snapshot tests with `insta` |
| **Release profile** | `opt-level = "z"`, `lto = true`, `codegen-units = 1`, `panic = "abort"`, `strip = true` |
| **CI / releases** | GitHub Actions building Windows, Linux, and macOS binaries, published as GitHub Releases |
| **Install (planned)** | `cargo install`, prebuilt binaries; package managers later |

---

## 5. Data & Metrics (Success Criteria)

### 5.1 Key Metrics
| Metric | Target |
|---|---|
| Cold start time | < 20 ms |
| Release binary size | < 3 MB |
| Peak memory | < 10 MB |
| Top-1 match accuracy on a test set of 100 natural phrasings | ≥ 90% |
| Top-3 match accuracy on the same set | ≥ 98% |
| Background processes / network calls | 0 / 0 |
| Content at launch | ≥ 12 Git sections, ≥ 9 shell sections, on all 3 OSes |
| Cross-platform CI | All tests pass on Windows, Linux, macOS |

### 5.2 Telemetry & Analytics
**None.** ezCMD is fully offline and collects no usage data. Success is measured with:
- **Local benchmarks** in CI (startup time, binary size, memory).
- **A fixed query test set** that scores match accuracy on every change.
- **Public signals only:** GitHub release downloads, stars, and issues.

---

## 6. Roadmap

No dates. Each milestone ships when ready.

**v0.1 (MVP)**
- [ ] TOML content files + build-time embedding
- [ ] Argument parser (query, `--help` family, `--version`, `--plain`)
- [ ] OS detection and per-OS command selection
- [ ] Fuzzy search over title, aliases, command text, and notes
- [ ] Framed, colored, aligned output with right-side notes
- [ ] `[1/2/3]` ambiguity prompt
- [ ] `--help`, `--help -<tool>`, `--help -<tool> -<section>`, `--help -<os>`
- [ ] Launch content for Git and shell basics
- [ ] Windows, Linux, macOS release builds

**Later releases (not committed)**
- [ ] Personal sheets (`ezcmd add`)
- [ ] Shell keybind to insert a command into the prompt
- [ ] Community content packs
- [ ] More tools (npm, Docker, Python/pip, SSH, Flutter)
- [ ] PowerShell and additional shell variants on Windows
- [ ] Danger flags on destructive commands
- [ ] Clipboard copy, interactive picker, placeholder fill-in prompts

**Dropped:** AI fallback.

---

## 7. Open Questions
1. **Paging:** Should `ezcmd --help` page automatically on long output, or leave it to `| less`? (Default for now: no auto-paging.)
2. **Windows shells:** CMD only for v0.1, or add PowerShell variants? (Default for now: CMD only.)
3. **macOS content:** Treat as `unix` with no macOS-specific entries until a command actually differs? (Default for now: yes.)
4. **License:** MIT, Apache-2.0, or dual-licensed?
