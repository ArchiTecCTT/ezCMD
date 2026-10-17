<p align="center">
  <img src="assets/banners/ezcmd_banner.png" alt="ezCMD Banner" width="100%">
</p>

<div align="center">

  <img src="assets/logos/ezcmd_logo.png" alt="ezCMD Logo" width="110" height="110">

  <h1>ezCMD</h1>
  <p><b>Type what you want to do. Get the commands, in order.</b><br>
  <i>A fast, offline, OS-aware terminal cheatsheet that remembers so you don't have to.</i></p>

  <p>
    <a href="https://github.com/ItzEvhyx/ezcmd/releases"><img src="https://img.shields.io/github/v/release/ItzEvhyx/ezcmd?color=00d2ff&style=for-the-badge&logo=github" alt="Release"></a>
    <img src="https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-7928CA?style=for-the-badge&logo=linux" alt="Platform">
    <img src="https://img.shields.io/badge/Startup-%3C%2015ms-00e676?style=for-the-badge&logo=speedtest" alt="Startup">
    <img src="https://img.shields.io/badge/Size-%3C%201.2MB-00b0ff?style=for-the-badge" alt="Size">
    <img src="https://img.shields.io/badge/Rust-1.70%2B-dea584?style=for-the-badge&logo=rust" alt="Rust">
  </p>

</div>

```text
                      /$$$$$$  /$$      /$$ /$$$$$$$ 
                     /$$__  $$| $$$    /$$$| $$__  $$
  /$$$$$$  /$$$$$$$$| $$  \__/| $$$$  /$$$$| $$  \ $$
 /$$__  $$|____ /$$/| $$      | $$ $$/$$ $$| $$  | $$
| $$$$$$$$   /$$$$/ | $$      | $$  $$$| $$| $$  | $$
| $$_____/  /$$__/  | $$    $$| $$\  $ | $$| $$  | $$
|  $$$$$$$ /$$$$$$$$|  $$$$$$/| $$ \/  | $$| $$$$$$$/
 \_______/|________/ \______/ |__/     |__/|_______/ 
```

---

## ⚡ Preview

```text
$ ezcmd initializing repo

 ___[ Initializing a Repo ]_________________________________________________________|
|                                                                                   |
|  git init                          --- Initializes a repo in the current folder   |
|  git add .                         --- Stages all new and changed files           |
|  git commit -m "Initial commit"    --- Saves the staged files as the first commit |
|  git branch -M main                --- Renames the current branch to main         |
|  git remote add origin <repo-url>  --- Links the repo to a remote on GitHub       |
|  git push -u origin main           --- Uploads main and sets it as the upstream   |
|___________________________________________________________________________________|
```

> **Aesthetic Terminal Box:** In modern terminals, borders and notes are styled with subtle dimming, commands are rendered in **bold**, and `<placeholders>` are highlighted in **yellow**. Color automatically switches off in pipes or when `NO_COLOR` is detected.

---

## 🚀 Features

- 🎯 **Task-Oriented Search:** Search for what you intend to accomplish (`initializing repo`, `undo last commit`, `delete files`) rather than trying to remember syntax.
- 🔍 **Intelligent Fuzzy Matcher:** Handles typos, transposed words, and natural phrasing using custom token-stemming and Damerau-Levenshtein distance.
- 💻 **OS-Aware Resolution:** Automatically detects whether you are on Linux, macOS, or Windows CMD and presents commands that work for your operating system.
- 📦 **Fully Offline & Self-Contained:** Cheatsheet data is compiled directly into the binary at build time. Zero network requests, zero telemetry, zero background daemons.
- ⚡ **Blazing Performance:** Launches, matches, formats, and terminates in **under 15 milliseconds** with less than 1.2 MB footprint.
- 🎨 **Fully Enclosed Box Frame:** Retro-modern ASCII borders enclose every output neatly on all sides.

---

## 📥 Installation Guide

<details open>
<summary><b>Quick Automated Install (Recommended)</b></summary>
<br>

#### Linux & macOS (Bash / Zsh / Fish)
Run the automated installation script:
```bash
curl -fsSL https://raw.githubusercontent.com/ItzEvhyx/ezcmd/main/install.sh | bash
```
*The installer automatically downloads the prebuilt binary for your OS and architecture, copies it to `~/.local/bin/ezcmd`, confirms successful installation, and prints the ASCII welcome banner.*

#### Windows (PowerShell)
Open PowerShell and run:
```powershell
irm https://raw.githubusercontent.com/ItzEvhyx/ezcmd/main/install.ps1 | iex
```

</details>

<details>
<summary><b>Terminal-Specific Setup (Fish, Bash, Zsh, CMD)</b></summary>
<br>

### 🐟 Fish Terminal
Fish handles paths and shell commands differently than POSIX shells. If installing manually or building from source:

```fish
# 1. Create ~/.local/bin if not present
mkdir -p ~/.local/bin

# 2. Symlink the ezcmd binary
ln -sf (pwd)/target/release/ezcmd ~/.local/bin/ezcmd

# 3. Permanently add ~/.local/bin to Fish's universal PATH:
set -Ua fish_user_paths ~/.local/bin

# 4. Verify installation
ezcmd --version
```

---

### 🐚 Bash Terminal
```bash
# 1. Create directory and symlink
mkdir -p ~/.local/bin
ln -sf "$(pwd)/target/release/ezcmd" ~/.local/bin/ezcmd

# 2. Add ~/.local/bin to PATH if needed
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

### ⚡ Zsh Terminal
```zsh
# 1. Create directory and symlink
mkdir -p ~/.local/bin
ln -sf "$(pwd)/target/release/ezcmd" ~/.local/bin/ezcmd

# 2. Add ~/.local/bin to PATH if needed
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

---

### 🪟 Windows CMD
```cmd
mkdir %USERPROFILE%\.local\bin
copy target\release\ezcmd.exe %USERPROFILE%\.local\bin\
setx PATH "%PATH%;%USERPROFILE%\.local\bin"
```

</details>

<details>
<summary><b>From Source (Rust / Cargo)</b></summary>
<br>

```bash
git clone https://github.com/ItzEvhyx/ezcmd.git
cd ezcmd
cargo build --release

# Run self-installer to place into ~/.local/bin and show welcome banner
./target/release/ezcmd --install
```

</details>

---

## 📖 Usage & Cheatsheet

```text
ezcmd <query>                          Find a workflow or command
ezcmd --help                           Show all sections for your current OS
ezcmd --help -<tool>                   Show all sections for a tool (e.g. -git, -shell)
ezcmd --help -<tool> -<section>        Show a specific section
ezcmd --help -<os>                     View cheatsheet as Linux, macOS, or Windows
ezcmd --plain <query>                  Raw plain output (no ANSI, no box frames)
ezcmd --welcome                        Display ASCII welcome banner & quickstart
ezcmd --uninstall                      Uninstall ezcmd completely from system
ezcmd --version                        Print installed ezcmd version
```

### Examples

```bash
# Everyday workflows
ezcmd initializing repo
ezcmd undo last commit
ezcmd how to branch
ezcmd stash changes
ezcmd delete folder

# Search by exact command syntax
ezcmd -- reset --hard

# OS-specific exploration
ezcmd --help -git
ezcmd --help -shell
ezcmd --help -windows -shell
```

### Handling Ambiguous Queries

When multiple sections match your query equally well, ezCMD provides an interactive numbered prompt:

```text
$ ezcmd undo

Multiple matches for "undo":
  1. Undo & Rollback
  2. Undoing the Last Commit
  3. Restoring a Deleted File
Choose [1/2/3]: 2
```

*(In scripts or non-interactive pipes, ezCMD automatically selects the top match without blocking).*

---

## 🗑️ Uninstalling

You can easily uninstall ezCMD anytime using the built-in uninstall command:

```bash
ezcmd --uninstall
```

You can also find it through fuzzy search:
```bash
ezcmd uninstall
ezcmd remove tool
```

This cleans up the binary, symlinks from `~/.local/bin`, and any configuration files.

---

## 🖥️ Supported Platforms

| Operating System | Architecture | Status |
|:---|:---|:---:|
| **Linux** | x86_64, aarch64 (ARM64) | ✅ Supported |
| **macOS** | Apple Silicon (M1/M2/M3), Intel x86_64 | ✅ Supported |
| **Windows** | Windows 10, 11 (x86_64 CMD & PowerShell) | ✅ Supported |

---

## ✍️ Author & Credits

Created by **ItzEvhyx**

- **GitHub:** [@ItzEvhyx](https://github.com/ItzEvhyx)
- **Repository:** [https://github.com/ItzEvhyx/ezcmd](https://github.com/ItzEvhyx/ezcmd)

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
