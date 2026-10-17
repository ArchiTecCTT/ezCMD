# ezCMD: Implementation Guide (for AI coding agents)

This document tells an AI coding agent **how to build ezCMD**. It is written to be handed to the agent together with `PRD.md` and `README.md`.

---

## 0. How to use this document

1. **Read `PRD.md`, `README.md`, and this file completely before writing any code.**
2. `PRD.md` defines *what* to build. This file defines *how*. If they conflict, `PRD.md` wins, **except** for the items listed in [Section 15](#15-decisions-that-extend-the-prd), which are deliberate refinements.
3. Work **one milestone at a time** (Section 13), in order. Do not start a milestone until the previous one's "Done when" checklist passes.
4. After every milestone, run the verification commands in Section 14, then report: what was built, what was tested, and any deviation from this guide.
5. **Do not add features that are not in the PRD.** In particular: no AI fallback, no telemetry, no personal sheets, no shell keybind, no config files, no auto-update. Those are out of scope.
6. If something is ambiguous, **ask instead of guessing**.

---

## 1. Hard constraints

These are non-negotiable. They come straight from the PRD's goals (lightweight, offline, cross-platform).

| Rule | Reason |
|---|---|
| **No network access, ever.** No HTTP crates, no update checks, no telemetry. | Fully offline tool |
| **No background processes, threads, timers, or async runtime.** | Zero resource use when idle |
| **No `clap`, `structopt`, or other CLI frameworks.** Use the hand-written parser in Section 6.2. | `-git` / `-windows` single-dash multi-letter flags, plus binary size |
| **No `regex`, `serde`, or `toml` in the runtime dependency tree.** They may be used in `build.rs` only. | Binary size and startup time |
| **Never execute the commands being displayed.** | Safety |
| **No file writes and no file reads at runtime** (content is embedded at build time). | Offline, single-file binary |
| **No `unsafe`.** | Simplicity |
| **No `unwrap()` / `expect()` / `panic!` in non-test code** unless the invariant is provably guaranteed, and then add a comment saying why. | Reliability |
| **Output is ASCII only** (frame characters are `_`, `|`, `[`, `]`, `-`). | Works in every terminal, including legacy Windows consoles |
| **Handle broken pipes quietly** (`ezcmd --help \| head` must not panic or print an error). | Rust's `println!` panics on `EPIPE`, so write to a locked, buffered stdout and treat `ErrorKind::BrokenPipe` as a normal exit |
| **Cross-platform from day one.** No Unix-only or Windows-only code outside `#[cfg(...)]` blocks. | Windows, Linux, macOS support |

---

## 2. Tools & environment

### Required
| Tool | Purpose |
|---|---|
| **Rust (stable)** via `rustup` | Language and toolchain. Minimum version: whatever supports `std::io::IsTerminal` (1.70+). Use the current stable edition |
| **cargo**, **rustfmt**, **clippy** | Build, format, lint (`rustup component add rustfmt clippy`) |
| **Git** | Version control |

### Recommended
| Tool | Install | Purpose |
|---|---|---|
| `cargo-insta` | `cargo install cargo-insta` | Review snapshot tests |
| `hyperfine` | package manager or `cargo install hyperfine` | Measure startup time against the 20 ms target |
| `cargo-bloat` | `cargo install cargo-bloat` | See what contributes to binary size |
| Extra targets | `rustup target add x86_64-pc-windows-gnu` etc. | Quick cross-checks with `cargo check --target ...` |

### Environment note
The developer may work on only one OS. **Windows- and macOS-specific behavior must be verified by the CI matrix** (Section 12), not assumed. Keep all platform-specific code small, isolated in `term.rs` and `os.rs`, and covered by `cfg` gates.

### Adding dependencies
Run `cargo add <crate>` to get the current version. **Do not copy version numbers from this document.** Justify every new dependency in the PR or milestone report (what it does, why `std` is not enough, size impact).

---

## 3. Project structure

The project is a **library crate plus a thin binary**, so integration tests can call the library directly.

```
ezcmd/
├── Cargo.toml
├── build.rs                  # parses + validates data/*.toml, generates static Rust tables
├── README.md
├── PRD.md
├── IMPLEMENTATION.md
├── data/
│   ├── git.toml              # Git sections
│   └── shell.toml            # Filesystem / CMD / shell basics (per OS)
├── src/
│   ├── main.rs               # thin: collect args, call lib, map result to exit code
│   ├── lib.rs                # pub mod declarations
│   ├── model.rs              # Tool / Section / Command structs, OS resolution
│   ├── content.rs            # include!(concat!(env!("OUT_DIR"), "/content.rs"))
│   ├── os.rs                 # Os enum, current(), parsing/printing OS names
│   ├── cli.rs                # hand-written argument parser
│   ├── matcher.rs            # tokenizer, scorer, search results
│   ├── render.rs             # section/help rendering (pure, writes to impl Write)
│   ├── prompt.rs             # [1/2/3] chooser (takes BufRead + Write for testability)
│   └── term.rs               # color enablement, terminal width, Windows VT setup
├── tests/
│   ├── cli.rs                # end-to-end tests with assert_cmd
│   ├── content.rs            # data sanity checks (counts, aliases, OS coverage)
│   ├── accuracy.rs           # runs tests/queries.toml against the matcher
│   └── queries.toml          # ≥100 phrasings → expected section
└── .github/workflows/
    ├── ci.yml
    └── release.yml
```

---

## 4. Dependencies

### Runtime (allowed)
| Crate | Use | Notes |
|---|---|---|
| `strsim` | Typo tolerance (Damerau-Levenshtein) | Tiny, no dependencies |
| `terminal_size` | Terminal width | Falls back to 80 when unavailable |
| `enable-ansi-support` | Enable ANSI colors on legacy Windows consoles | **Windows only**, under `[target.'cfg(windows)'.dependencies]` |

### Optional (only if the accuracy test needs it)
| Crate | Use |
|---|---|
| `nucleo-matcher` | Extra fuzzy subsequence scoring. Start **without** it. Add only if `tests/accuracy.rs` cannot hit its targets with the Section 8 algorithm |

### Build-time only (`[build-dependencies]`)
`serde` (with `derive`) and `toml` to parse `data/*.toml`.

### Dev-only (`[dev-dependencies]`)
`insta` (snapshots), `assert_cmd` + `predicates` (CLI tests).

### Forbidden at runtime
`clap`, `regex`, `serde*`, `toml`, `tokio`/any async runtime, `reqwest`/any HTTP client, `anyhow`/`thiserror` (use a small hand-written error enum), `lazy_static`/`once_cell` (the data is `static`).

### Release profile
```toml
[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
panic = "abort"
strip = true
```
Because `panic = "abort"` is set, the "no panics" rule matters even more.

---

## 5. Data model & build script

### 5.1 Runtime types (`model.rs`)

```rust
pub struct Tool    { pub name: &'static str, pub sections: &'static [Section] }
pub struct Section { pub title: &'static str,
                     pub aliases: &'static [&'static str],
                     pub commands: &'static [Command] }
pub struct Command {
    pub note:    &'static str,
    pub cmd:     Option<&'static str>,  // all OSes
    pub unix:    Option<&'static str>,  // linux + macos
    pub windows: Option<&'static str>,
    pub linux:   Option<&'static str>,
    pub macos:   Option<&'static str>,
}

impl Command {
    /// Precedence: exact OS key > unix (linux/macos only) > cmd.
    pub fn resolve(&self, os: Os) -> Option<&'static str> { /* ... */ }
}
impl Section {
    /// True if at least one command resolves for `os`.
    pub fn available_on(&self, os: Os) -> bool { /* ... */ }
}
```

`content.rs` exposes `pub static TOOLS: &[Tool]`, generated by `build.rs`. Tools are sorted by name; sections keep file order.

### 5.2 Input format (`data/*.toml`)

Exactly as specified in PRD Section 4.4:

```toml
tool = "git"

[[section]]
title   = "Initializing a Repo"
aliases = ["init repo", "start repo", "new project", "create repository"]

  [[section.command]]
  cmd  = "git init"
  note = "Initializes a repo in the current folder"

[[section]]
title   = "Removing a Folder"
aliases = ["delete folder", "remove directory"]

  [[section.command]]
  note    = "Removes a folder and everything inside it"
  windows = "rmdir /s /q <folder>"
  unix    = "rm -rf <folder>"
```

### 5.3 `build.rs` responsibilities

1. Print `cargo:rerun-if-changed=data` and `cargo:rerun-if-changed=build.rs`.
2. Read every `data/*.toml`, parse with `serde` + `toml`.
3. **Validate** (fail the build with a clear message like `data/git.toml: section "X": <problem>`):
   - `tool` is non-empty, lowercase, no spaces, and unique across files. It must not equal an OS name (`windows`, `linux`, `macos`).
   - Section titles are non-empty and unique within a tool.
   - Each section has **≥ 3 aliases**, all lowercase, non-empty, and not duplicated within the tool.
   - Each section has **≥ 1 command**.
   - Each command has a non-empty `note` of **≤ 60 characters** with no trailing period, and **at least one** of `cmd`, `unix`, `windows`, `linux`, `macos`.
   - `<` and `>` in command strings are balanced.
   - No command string contains a newline or a tab.
4. Generate `$OUT_DIR/content.rs` containing the `static TOOLS` table. **Use `{:?}` (Debug formatting) to emit string literals** so quotes and backslashes (`D:\<folder>`) are escaped correctly. Emit `Option` fields as `Some("...")` / `None`.
5. Never access the network and never write outside `OUT_DIR`.

---

## 6. Module specifications

### 6.1 `os.rs`
```rust
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Os { Windows, Linux, Macos }
impl Os {
    pub fn current() -> Os;                  // from std::env::consts::OS; any non-windows/non-macos => Linux
    pub fn from_flag(name: &str) -> Option<Os>;   // "windows" | "linux" | "macos" (case-insensitive)
    pub fn name(self) -> &'static str;       // "windows" | "linux" | "macos"
    pub fn display(self) -> &'static str;    // "Windows" | "Linux" | "macOS"
}
```

### 6.2 `cli.rs`: argument parser

Input: `&[String]` (args without the program name). Output: `Result<Invocation, CliError>`.

```rust
pub struct Invocation { pub plain: bool, pub action: Action }
pub enum Action {
    Usage,                                      // no arguments at all
    Version,                                    // --version
    Query(String),                              // free-text search
    Help { os: Option<Os>, tool: Option<String>, section: Option<String> },
}
```

**Grammar**

| Input | Result |
|---|---|
| *(nothing)* | `Usage` |
| `--version` | `Version` |
| `--plain` | Sets `plain = true`. Allowed anywhere before a bare `--` |
| `--` | Everything after it is treated as query text, even if it starts with `-` |
| `--help …` | Help mode (below) |
| any other token starting with `--` | `CliError::UnknownFlag` (exit 2) |
| anything else | Collected, space-joined, into `Query` |

**Help mode.** After `--help`, the remaining tokens are processed left to right:

1. A token starting with a single `-` (and not `--`) is a **selector**. Strip the dash.
   - If it equals an OS name → set `os`.
   - Else if it equals a tool name from `TOOLS` → set `tool`.
   - Else, **if a tool was already selected** → it begins the **section query** (see 3).
   - Else → `CliError::UnknownSelector` (message lists available tools and OS names).
2. `--plain` is allowed anywhere.
3. **Section query:** once a tool is selected, the first token that is not an OS/tool selector begins the section text. Strip one leading `-` if present, then append every following token that does **not** start with `-`. So `-initialize repo` and `-initializing a repo` both produce a section query.
4. A section query without a tool selector is an error (`-initialize repo` alone is not valid).
5. Selectors are order-independent: `-windows -git` equals `-git -windows`.

**Examples to cover in tests**

| Args | Parsed |
|---|---|
| `initializing repo` | `Query("initializing repo")` |
| `-- reset --hard` | `Query("reset --hard")` |
| `--help` | `Help{None,None,None}` |
| `--help -git` | `Help{os:None, tool:git, section:None}` |
| `--help -git -initialize repo` | `Help{None, git, Some("initialize repo")}` |
| `--help -windows` | `Help{Windows, None, None}` |
| `--help -windows -git -initialize repo` | all three set |
| `--help -nope` | `UnknownSelector` |
| `--bogus` | `UnknownFlag` |
| `--plain initializing repo` | plain + query |

`CliError` is a small enum with a `Display` implementation. `main.rs` prints it to stderr, followed by a one-line hint (`Try: ezcmd --help`), and exits with code 2.

### 6.3 `matcher.rs`
See Section 8. Public API:

```rust
pub struct Hit<'a> { pub tool: &'a Tool, pub section: &'a Section, pub score: f32 }
pub enum SearchResult<'a> {
    Single(Hit<'a>),
    Ambiguous(Vec<Hit<'a>>),     // 2..=MAX_CHOICES
    NoMatch(Vec<Hit<'a>>),       // up to 3 closest, may be empty
}
pub fn search<'a>(tools: &'a [Tool], os: Os, query: &str,
                  only_tool: Option<&str>) -> SearchResult<'a>;
```
`only_tool` restricts the search to one tool (used by `--help -git -<section>`).

### 6.4 `render.rs`
Pure functions that write to `impl std::io::Write`. They take a `RenderCtx { color: bool, plain: bool, width: usize }` and an `Os`. See Section 9.

### 6.5 `prompt.rs`
```rust
pub fn choose<R: BufRead, W: Write>(input: &mut R, out: &mut W, hits: &[Hit]) -> io::Result<Option<usize>>;
```
- Prints the list (`  1. Title`) and the prompt `Choose [1/2/3]: ` (the bracket contents match the number of choices, for example `[1/2]`).
- Accepts a number in range. **Enter alone selects nothing** and re-prompts.
- Re-prompts up to **3 times** on invalid input, then returns `None`.
- End of input (EOF / Ctrl-D) returns `None`.
- The caller decides interactivity: prompt only when **stdin and stdout are both terminals** (`std::io::IsTerminal`). Otherwise print the single best hit and continue normally.

### 6.6 `term.rs`
- `color_enabled(plain: bool) -> bool`: true only if **stdout is a terminal**, `plain` is false, `NO_COLOR` is unset or empty, and `TERM` is not `dumb`. On Windows, call `enable_ansi_support()` first and return `false` if it fails.
- `width() -> usize`: from `terminal_size`, default **80** if it fails.
- A tiny `Style` helper with hand-written ANSI constants (see Section 9.3). No color crate is needed.

### 6.7 `main.rs` flow
```
args → cli::parse
  Err(e)            → stderr message, exit 2
  Usage             → print short usage header, exit 0
  Version           → print "ezcmd <version>", exit 0
  Query(q)          → matcher::search(os = Os::current())
                        Single      → render section
                        Ambiguous   → interactive ? prompt::choose → render chosen
                                                  : render best hit
                        NoMatch     → print message + closest 3, exit 1
  Help{..}          → see Section 9.5
Write errors: BrokenPipe → exit 0 quietly; other io errors → stderr, exit 1.
```

---

## 7. Exit codes

| Code | Meaning |
|---|---|
| `0` | Success (including `--help`, `--version`, no-argument usage) |
| `1` | No match, or the user aborted the chooser |
| `2` | Invalid arguments (unknown flag, unknown tool/OS selector, malformed `--help` use) |

---

## 8. Matching algorithm

Content is tiny (tens of sections), so **no indexing or caching is needed**. Keep the code simple and fast to start.

### 8.1 Tokenizing
- Lowercase. Split on any non-alphanumeric character. Drop tokens shorter than 2 characters.
- Strip leading dashes before splitting, so `--hard` becomes `hard`.
- Remove stopwords **from the query only**: `a an the to how do i my in on of for with and`. If that empties the query, retry without stopword removal. If it is still empty, return a usage error (exit 2).
- Light stemmer applied to every token (query and content): strip the **first** matching suffix from `ing`, `ed`, `es`, `s`, `e`, but only if at least 3 characters remain. Examples: `initializing` → `initializ`, `initialize` → `initializ`, `branches` → `branch`, `commits` → `commit`.

### 8.2 Token match score `tm(q, t)`
| Case | Score |
|---|---|
| Stems equal | `1.00` |
| `t` starts with `q` (`q.len() >= 3`), e.g. `repo` vs `repository` | `0.85` |
| `q` starts with `t` (`t.len() >= 3`), e.g. `initialize` vs `init` | `0.80` |
| Damerau-Levenshtein distance ≤ 1 (token length 4 to 7) or ≤ 2 (length ≥ 8) | `0.70` |
| otherwise | `0.00` |

### 8.3 Field and section scores
- **Field score** = (sum over query tokens of the best `tm` against any token in the field) ÷ (number of query tokens). Unmatched query tokens pull the score down.
- Fields: **title**, **each alias separately** (take the max), **command text** (all commands that resolve for the OS, joined), **notes** (joined).
- **Section score** = max of:
  `W_TITLE × title`, `W_ALIAS × best alias`, `W_CMD × commands`, `W_NOTE × notes`
- Constants (tune against the accuracy test, keep them together at the top of `matcher.rs`):

```rust
const W_TITLE: f32 = 1.00;
const W_ALIAS: f32 = 0.95;
const W_CMD:   f32 = 0.70;
const W_NOTE:  f32 = 0.50;
const MATCH_THRESHOLD: f32 = 0.45;   // below this: not a match
const AMBIGUITY_RATIO: f32 = 0.85;   // candidates within 85% of the top score
const MAX_CHOICES: usize = 3;
```

### 8.4 Result decision
1. Consider only sections where `available_on(os)` is true, and score command text using **resolved commands for that OS only**.
2. Sort by score, with ties broken by tool name then file order (deterministic output).
3. If the top score `< MATCH_THRESHOLD` → `NoMatch` (with up to 3 closest sections regardless of threshold).
4. Else collect candidates with `score >= top × AMBIGUITY_RATIO`. If there is exactly one → `Single`. If more → `Ambiguous` (first `MAX_CHOICES`).

### 8.5 Accuracy gate
`tests/queries.toml` holds **≥ 100** realistic phrasings, including typos, synonyms, reordered words, and command-text searches:

```toml
[[q]]
query  = "initalize repo"
expect = "Initializing a Repo"

[[q]]
query  = "reset --hard"
expect = "Undo & Rollback"
```
`tests/accuracy.rs` runs every query for **each of the three OSes** (skip entries marked `os = "windows"` etc. when not applicable) and asserts:
- Top-1 hit rate ≥ **90%**
- Top-3 hit rate ≥ **98%** (an `Ambiguous` result counts as a top-3 hit if it contains the expected section)

When the test fails, print each failing query with the actual ranking. Tune constants and aliases until it passes. Do **not** weaken the thresholds.

---

## 9. Rendering specification

### 9.1 Section frame (colored layout)

```
 ___[ Initializing a Repo ]_________________________________________________
|
|  git init                        --- Initializes a repo in the current folder
|  git add .                       --- Stages all new and changed files
|  git commit -m "Initial commit"  --- Saves the staged files as the first commit
|___________________________________________________________________________
```

Layout algorithm:
1. Resolve each command for the current (or requested) OS. Commands that resolve to `None` follow the "no equivalent" rule (9.4).
2. `cmd_w` = longest resolved command, capped at 48.
3. **Wide layout** if `3 + cmd_w + 2 + 4 + longest_note <= term_width`; each line is `|  ` + command padded to `cmd_w` + `  --- ` + note.
4. Otherwise **narrow layout** (decided per section): the note drops to its own line, indented:
   ```
   |  git commit -m "Initial commit"
   |      --- Saves the staged files as the first commit
   ```
5. Frame width = `clamp(widest_line + 2, 60, max(term_width, 60))`.
   - Top rule: ` ___[ ` + title + ` ]` followed by `_` to fill the width.
   - A bare `|` line follows the top rule.
   - Bottom rule: `|` followed by `_` to fill the width.
6. One blank line between sections.

**Padding pitfall:** compute widths on the **plain** strings, then apply color. Never pad strings that already contain ANSI escape codes.

### 9.2 Plain mode (`--plain`, or output is not a terminal, or `NO_COLOR`)
- `--plain`: no color and no frame. Each section prints `# ---Title---` then `command --- note` lines, with a blank line between sections.
- Not a terminal or `NO_COLOR` without `--plain`: keep the frame, drop only the color.

### 9.3 Colors (hand-written ANSI, modeled on atuin's help screen)
| Element | Escape |
|---|---|
| Section title inside `[ ]` | bold cyan `\x1b[1;36m` |
| Frame characters (`_`, `\|`, brackets) | dim gray `\x1b[90m` |
| Commands | bold `\x1b[1m` |
| Placeholders (`<url>`) | yellow `\x1b[33m` |
| `---` separator | dim gray `\x1b[90m` |
| Notes | default foreground |
| Errors and "no match" lines | bold red `\x1b[1;31m` |
| Reset | `\x1b[0m` |

Placeholders are found with a simple `<`…`>` scan (no regex) and highlighted inside the command.

### 9.4 "No equivalent" rule (OS view)
- If **no** command in a section resolves for the OS, omit the whole section.
- If only some commands don't resolve, show the command column as dim `(no equivalent)` and keep the note, followed by `[no equivalent on <Os>]`.

### 9.5 Help output

**Header** (matches the PRD; headings cyan bold like atuin's "Usage:"):
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

| Invocation | Output |
|---|---|
| `ezcmd` (no args) | Header only, plus a hint to run `ezcmd --help` |
| `--help` | Header, then **every section of every tool**, with a bold cyan `TOOL: <name>` line before each tool's sections |
| `--help -<tool>` | Header, then that tool's sections only |
| `--help -<tool> -<section>` | Header omitted. Run `matcher::search(only_tool)`. `Single` renders the section. `Ambiguous` uses the same chooser as queries. `NoMatch` prints closest titles and exits 1 |
| any of the above + `-<os>` | Same output, with commands resolved for that OS |

`--help` output is **not** paged (see PRD open question 1).

---

## 10. Content authoring

The agent must also write the launch content.

### 10.1 Style rules
- Notes: ≤ 60 characters, start with a verb in the present tense (`Stages…`, `Lists…`), no trailing period.
- Sections group **a task**, ordered so that the commands run top to bottom. Example: *Initializing a Repo* starts with `git init`.
- Every section has **≥ 3 aliases** written the way a beginner would phrase the task.
- **Verify every command for accuracy.** Prefer modern equivalents (`git switch`, `git restore`). If unsure about a command's behavior on one OS, leave that OS out instead of guessing.
- Placeholders use `<angle-brackets>` and short names (`<url>`, `<branch>`, `<file>`).

### 10.2 `data/git.toml` (12 sections minimum)
Setup & Config · Initializing a Repo · Cloning a Repo · Daily Workflow · Branching · Remotes · Undo & Rollback · Stash · Tags · History & Diff · Cleanup & Maintenance · Finding a Bad Commit (bisect)

Git commands are identical on every OS, so use `cmd`. The *Initializing a Repo* section must be exactly: `git init`, `git add .`, `git commit -m "Initial commit"`, `git branch -M main`, `git remote add origin <repo-url>`, `git push -u origin main`.

### 10.3 `data/shell.toml` (9 sections minimum)
Navigating Directories · Creating Folders & Files · Removing Folders & Files · Copying, Moving & Renaming · Viewing File Contents · System Info · Networking · Processes · Environment Variables

Reference for the per-OS commands (Windows = CMD). Double-check each before committing it:

| Task | Windows (CMD) | Linux | macOS |
|---|---|---|---|
| Show current folder | `cd` | `pwd` | `pwd` |
| Enter folder | `cd <folder>` | `cd <folder>` | `cd <folder>` |
| Go up one level | `cd ..` | `cd ..` | `cd ..` |
| Go to root | `cd \` | `cd /` | `cd /` |
| Switch drive | `cd /d D:\<folder>` | *(none)* | *(none)* |
| List files | `dir` | `ls -la` | `ls -la` |
| Folder tree | `tree` | `tree` | `tree` |
| Clear screen | `cls` | `clear` | `clear` |
| Make folder | `mkdir <folder>` | `mkdir <folder>` | `mkdir <folder>` |
| Make empty file | `type nul > <file>` | `touch <file>` | `touch <file>` |
| Remove empty folder | `rmdir <folder>` | `rmdir <folder>` | `rmdir <folder>` |
| Remove folder + contents | `rmdir /s /q <folder>` | `rm -rf <folder>` | `rm -rf <folder>` |
| Delete file | `del <file>` | `rm <file>` | `rm <file>` |
| Copy file | `copy <src> <dest>` | `cp <src> <dest>` | `cp <src> <dest>` |
| Copy folder | `xcopy <src> <dest> /e /i` | `cp -r <src> <dest>` | `cp -r <src> <dest>` |
| Move file | `move <src> <dest>` | `mv <src> <dest>` | `mv <src> <dest>` |
| Rename | `ren <old> <new>` | `mv <old> <new>` | `mv <old> <new>` |
| Show file | `type <file>` | `cat <file>` | `cat <file>` |
| Page through file | `more <file>` | `less <file>` | `less <file>` |
| Search in file | `findstr "text" <file>` | `grep "text" <file>` | `grep "text" <file>` |
| OS version | `ver` | `uname -a` | `sw_vers` |
| Machine name | `hostname` | `hostname` | `hostname` |
| Current user | `whoami` | `whoami` | `whoami` |
| IP addresses | `ipconfig` | `ip addr` | `ifconfig` |
| Ping | `ping <host>` | `ping <host>` | `ping <host>` |
| Trace route | `tracert <host>` | `traceroute <host>` | `traceroute <host>` |
| DNS lookup | `nslookup <domain>` | `nslookup <domain>` | `nslookup <domain>` |
| Open ports | `netstat -ano` | `ss -tulpn` | `lsof -i -P` |
| List processes | `tasklist` | `ps aux` | `ps aux` |
| Kill by PID | `taskkill /PID <pid> /F` | `kill -9 <pid>` | `kill -9 <pid>` |
| Kill by name | `taskkill /IM <name.exe> /F` | `pkill -9 <name>` | `pkill -9 <name>` |
| Show variables | `set` | `printenv` | `printenv` |
| Show PATH | `echo %PATH%` | `echo $PATH` | `echo $PATH` |
| Set variable (session) | `set <NAME>=<value>` | `export <NAME>=<value>` | `export <NAME>=<value>` |

Where Linux and macOS match, use `unix`. Where only one OS has a command (`cd /d`), give only that OS's key so the other OSes get the "no equivalent" behavior.

---

## 11. Testing plan

| Layer | What | How |
|---|---|---|
| **Unit** | `Command::resolve` precedence; `Os::from_flag`; tokenizer, stemmer, `tm()`; `cli::parse` for **every row** in Section 6.2's table plus error cases | `#[cfg(test)]` in each module |
| **Prompt** | Valid choice, invalid input then valid, three invalid inputs, EOF | Feed `Cursor<&[u8]>` as input and a `Vec<u8>` as output |
| **Render snapshots** | Wide, narrow, plain, colored (escape codes visible), no-equivalent, placeholder highlighting, per-OS output for the same section | `insta` snapshots with fixed `width` and `RenderCtx` |
| **Content sanity** (`tests/content.rs`) | ≥ 12 git and ≥ 9 shell sections; every section has ≥ 3 aliases; every section is `available_on` all three OSes; the *Initializing a Repo* section matches Section 10.2 exactly | Plain integration test |
| **Accuracy** (`tests/accuracy.rs`) | Top-1 ≥ 90%, top-3 ≥ 98% on `queries.toml` | See Section 8.5 |
| **CLI end-to-end** (`tests/cli.rs`) | Exit codes 0/1/2; `--plain` output has no ANSI escapes; `NO_COLOR=1` output has no escapes; piped stdin never blocks on the chooser; `--help -windows` contains `rmdir /s /q`; `--help -git -initialize repo` prints exactly one section; a closed pipe (`| head -n 1`) does not panic | `assert_cmd` |

Rules: tests must be deterministic and must **not** depend on the host OS unless gated with `#[cfg(...)]`. Use `Os` values explicitly in tests instead of `Os::current()`.

---

## 12. CI & releases

### `ci.yml` (on push and pull request)
Matrix: `ubuntu-latest`, `windows-latest`, `macos-latest`. Steps:
1. Checkout, install stable Rust with `rustfmt` and `clippy`.
2. `cargo fmt --all -- --check`
3. `cargo clippy --all-targets -- -D warnings`
4. `cargo test --all-targets`
5. `cargo build --release`
6. **Size gate:** fail if the release binary is larger than 3 MB.
7. **Content gate:** the build itself fails on invalid `data/*.toml` (Section 5.3).

### `release.yml` (on tags `v*`)
Build release binaries for:
- `x86_64-pc-windows-msvc`
- `x86_64-unknown-linux-musl` (install `musl-tools`; add `aarch64-unknown-linux-musl` if easy)
- `x86_64-apple-darwin`
- `aarch64-apple-darwin`

Package each as `ezcmd-<version>-<target>.zip` (Windows) or `.tar.gz`, attach to the GitHub Release, and include SHA-256 checksums. No other publishing in v0.1.

---

## 13. Milestones

Complete in order. Each milestone ends with the verification commands from Section 14.

### M0: Scaffold
- `cargo new --lib ezcmd` plus `src/main.rs`; set up `Cargo.toml` with the release profile; add the folder structure from Section 3 with empty modules.
- `ci.yml` with fmt, clippy, test, build on the 3-OS matrix.
- **Done when:** CI is green on all three OSes with an empty program that prints the version.

### M1: Data model & build script
- `model.rs`, `os.rs`, `build.rs`, `content.rs`.
- `data/git.toml` and `data/shell.toml` with **two sections each** as seed content.
- `tests/content.rs` (relaxed minimums for now).
- **Done when:** `build.rs` generates `TOOLS`, malformed TOML fails the build with a clear message (add a test or manual proof), and `resolve()` precedence tests pass.

### M2: CLI parser
- `cli.rs` and `CliError`, with unit tests for every example in Section 6.2.
- **Done when:** parser tests pass, including `-initialize repo` multi-word handling and `--` handling.

### M3: Matcher
- `matcher.rs` as specified in Section 8, seed `queries.toml` with 30 queries, `tests/accuracy.rs`.
- **Done when:** the accuracy test runs and reports its rate (the 90%/98% gate is enforced from M7 once content is complete).

### M4: Rendering & terminal
- `render.rs`, `term.rs`, with snapshot tests for wide, narrow, plain, colored, and no-equivalent output.
- **Done when:** snapshots are reviewed and committed, and colors switch off for `--plain`, `NO_COLOR`, and non-terminal output.

### M5: Query mode end to end
- `prompt.rs`, `main.rs` wiring for `Query`, `Usage`, `Version`, exit codes, and broken-pipe handling.
- **Done when:** `ezcmd initializing repo` prints the correct section on every OS in CI, the chooser works in a terminal, and piped output never blocks.

### M6: Help family & OS view
- All `--help` forms from Section 9.5, including `-<tool>`, `-<tool> -<section>`, and `-<os>` combinations.
- **Done when:** the CLI end-to-end tests for help pass.

### M7: Full content & accuracy gate
- Write all of `git.toml` and `shell.toml` per Section 10; grow `queries.toml` to ≥ 100 phrasings; tune matcher constants and aliases.
- **Done when:** the accuracy gate passes (top-1 ≥ 90%, top-3 ≥ 98%) and the content tests enforce the full minimums.

### M8: Performance, size & release
- Add the size gate and `release.yml`; measure startup with `hyperfine`; trim with `cargo bloat` if the binary is over target.
- Replace the `TODO` screenshot placeholder in `README.md` once real output exists.
- **Done when:** all targets in Section 14 are met and a tagged build produces release artifacts.

---

## 14. Verification & definition of done

Run after every milestone:

```bash
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test --all-targets
cargo build --release
```

Run at M8, and before any release:

| Check | Command | Target (PRD Section 5.1) |
|---|---|---|
| Startup time | `hyperfine --warmup 5 'target/release/ezcmd initializing repo'` | **< 20 ms** mean (aim for < 10 ms) |
| Binary size | `ls -l target/release/ezcmd` (or `dir` on Windows) | **< 3 MB** (aim for < 2 MB) |
| Peak memory | `/usr/bin/time -v target/release/ezcmd --help` on Linux | **< 10 MB** |
| Background activity | Confirm no threads/timers in the code (`grep -R "thread::\|spawn\|sleep"` in `src/` finds nothing) | **0** |
| Network | Confirm no networking crates (`cargo tree`) | **0** |
| Accuracy | `cargo test --test accuracy` | Top-1 ≥ 90%, top-3 ≥ 98% |
| Cross-platform | CI green on Windows, Linux, macOS | All pass |

**v0.1 is done when** every PRD v0.1 checkbox is satisfied, every milestone's "Done when" has passed, and the table above is green.

---

## 15. Decisions that extend the PRD

This guide makes the following choices where the PRD left room. If you disagree with any of them, update both files together.

| # | Decision | PRD reference |
|---|---|---|
| 1 | Color uses hand-written ANSI codes instead of an `owo-colors`/`anstyle` crate, to keep dependencies minimal | PRD 4.5 (tech table) |
| 2 | Frame width = widest line + 2, clamped between 60 columns and the terminal width (the PRD says only "follows the terminal width, min 60") | PRD 4.2 |
| 3 | `--plain` prints `# ---Title---` and then `command --- note` lines (the PRD says "only command --- note lines"; the title line keeps multi-section dumps readable) | PRD FR-11 |
| 4 | Pressing Enter at the `[1/2/3]` prompt selects nothing and re-prompts; three invalid answers or EOF abort with exit code 1 | PRD FR-3 |
| 5 | Any unrecognized OS is treated as Linux (`unix` commands) | PRD FR-5 |
| 6 | The chooser is used only when stdin **and** stdout are terminals | PRD FR-3 |
| 7 | `--help -<tool> -<section>` reuses the same matcher and chooser as normal queries | PRD FR-7 |
| 8 | Commands with no equivalent in OS view show `(no equivalent)` and a `[no equivalent on <Os>]` suffix | PRD FR-5 / FR-8 |
| 9 | Typo tolerance uses `strsim`; `nucleo-matcher` is added only if the accuracy gate requires it | PRD 4.5 |

---

## 16. Prompts to give the AI agent

### Kickoff prompt
```
You are implementing ezCMD, a lightweight offline Rust CLI cheatsheet.

1. Read PRD.md, README.md, and IMPLEMENTATION.md completely before writing code.
2. Follow IMPLEMENTATION.md exactly. Respect the hard constraints in Section 1.
3. Work one milestone at a time, starting with M0. Do not begin the next
   milestone until I approve.
4. After each milestone, run the Section 14 verification commands, then report:
   - what you built,
   - which tests you added and their results,
   - any deviation from the guide and why.
5. Do not add features outside the PRD. If something is ambiguous, ask me.

Begin with M0.
```

### Per-milestone prompt
```
Implement milestone M<N> from IMPLEMENTATION.md Section 13.
Re-read the sections it references first. Stop when its "Done when" checklist
passes and report using the format from the kickoff prompt.
```

### Content-writing prompt (M7)
```
Write data/git.toml and data/shell.toml following IMPLEMENTATION.md Section 10.
Use the reference table for per-OS commands, and verify each command before
including it. Where you are unsure a command behaves the same on an OS, omit
that OS instead of guessing, and list those cases in your report.
```
