use crate::term;
use std::io::{self, Write};
use std::path::PathBuf;

pub const ASCII_ART: &str = r#"
                      /$$$$$$  /$$      /$$ /$$$$$$$ 
                     /$$__  $$| $$$    /$$$| $$__  $$
  /$$$$$$  /$$$$$$$$| $$  \__/| $$$$  /$$$$| $$  \ $$
 /$$__  $$|____ /$$/| $$      | $$ $$/$$ $$| $$  | $$
| $$$$$$$$   /$$$$/ | $$      | $$  $$$| $$| $$  | $$
| $$_____/  /$$__/  | $$    $$| $$\  $ | $$| $$  | $$
|  $$$$$$$ /$$$$$$$$|  $$$$$$/| $$ \/  | $$| $$$$$$$/
 \_______/|________/ \______/ |__/     |__/|_______/ 
"#;

pub fn get_config_dir() -> Option<PathBuf> {
    if let Some(xdg) = std::env::var_os("XDG_CONFIG_HOME") {
        return Some(PathBuf::from(xdg).join("ezcmd"));
    }
    #[cfg(windows)]
    {
        if let Some(appdata) = std::env::var_os("APPDATA") {
            return Some(PathBuf::from(appdata).join("ezcmd"));
        }
        if let Some(userprofile) = std::env::var_os("USERPROFILE") {
            return Some(PathBuf::from(userprofile).join(".ezcmd"));
        }
    }
    #[cfg(not(windows))]
    {
        if let Some(home) = std::env::var_os("HOME") {
            return Some(PathBuf::from(home).join(".config").join("ezcmd"));
        }
    }
    None
}

pub fn get_marker_path() -> Option<PathBuf> {
    get_config_dir().map(|d| d.join(".installed"))
}

pub fn check_first_run() -> bool {
    if std::env::var("EZCMD_NO_WELCOME").is_ok() || std::env::var("CI").is_ok() {
        return false;
    }
    if let Some(marker) = get_marker_path() {
        if marker.exists() {
            return false;
        }
        if let Some(parent) = marker.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::write(&marker, "installed");
        return true;
    }
    false
}

pub fn run_install<W: Write>(w: &mut W, color: bool) -> io::Result<i32> {
    #[cfg(not(windows))]
    let bin_dir = std::env::var_os("HOME")
        .map(|h| PathBuf::from(h).join(".local/bin"))
        .unwrap_or_else(|| PathBuf::from("/usr/local/bin"));

    #[cfg(windows)]
    let bin_dir = std::env::var_os("USERPROFILE")
        .map(|u| PathBuf::from(u).join(".local/bin"))
        .unwrap_or_else(|| PathBuf::from("C:\\bin"));

    let _ = std::fs::create_dir_all(&bin_dir);

    #[cfg(windows)]
    let dest_exe = bin_dir.join("ezcmd.exe");
    #[cfg(not(windows))]
    let dest_exe = bin_dir.join("ezcmd");

    if let Ok(current_exe) = std::env::current_exe() {
        if current_exe != dest_exe {
            #[cfg(unix)]
            {
                let _ = std::fs::remove_file(&dest_exe);
                if std::os::unix::fs::symlink(&current_exe, &dest_exe).is_err() {
                    let _ = std::fs::copy(&current_exe, &dest_exe);
                }
            }
            #[cfg(not(unix))]
            {
                let _ = std::fs::copy(&current_exe, &dest_exe);
            }
        }
    }

    if let Some(marker) = get_marker_path() {
        if let Some(parent) = marker.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::write(&marker, "installed");
    }

    if color {
        writeln!(
            w,
            "{}✓ Successfully installed ezcmd to {}!{}",
            term::CYAN_BOLD,
            dest_exe.display(),
            term::RESET
        )?;
    } else {
        writeln!(w, "✓ Successfully installed ezcmd to {}!", dest_exe.display())?;
    }
    writeln!(w)?;

    print_welcome(w, color)?;
    Ok(0)
}


pub fn print_welcome<W: Write>(w: &mut W, color: bool) -> io::Result<()> {
    if color {
        writeln!(
            w,
            "{}{}{}",
            term::CYAN_BOLD,
            ASCII_ART.trim_matches('\n'),
            term::RESET
        )?;
        writeln!(w)?;
        writeln!(
            w,
            "  {}Welcome to ezCMD!{} Find the right command, in order.",
            term::BOLD,
            term::RESET
        )?;
        writeln!(
            w,
            "  Never browse Stack Overflow for everyday terminal commands again.\n"
        )?;

        writeln!(w, "  {}QUICK START / HOW TO USE:{}", term::CYAN_BOLD, term::RESET)?;
        writeln!(
            w,
            "    {}ezcmd <query>{}                   Search for workflows or commands",
            term::BOLD,
            term::RESET
        )?;
        writeln!(
            w,
            "    {}ezcmd --help{}                    Show all sections for your OS",
            term::BOLD,
            term::RESET
        )?;
        writeln!(
            w,
            "    {}ezcmd --help -git{}               Show Git workflow cheatsheet",
            term::BOLD,
            term::RESET
        )?;
        writeln!(
            w,
            "    {}ezcmd --help -shell{}             Show Shell command cheatsheet",
            term::BOLD,
            term::RESET
        )?;
        writeln!(
            w,
            "    {}ezcmd --uninstall{}               Uninstall ezcmd from your machine",
            term::BOLD,
            term::RESET
        )?;
        writeln!(w)?;
        writeln!(w, "  {}TRY THESE QUERIES:{}", term::CYAN_BOLD, term::RESET)?;
        writeln!(w, "    ezcmd initializing repo")?;
        writeln!(w, "    ezcmd undo last commit")?;
        writeln!(w, "    ezcmd how to branch")?;
        writeln!(w, "    ezcmd delete files")?;
        writeln!(w)?;
        writeln!(w, "  {}AUTHOR & CREDITS:{}", term::CYAN_BOLD, term::RESET)?;
        writeln!(
            w,
            "    Created by {}ItzEvhyx{} (Me)",
            term::BOLD,
            term::RESET
        )?;
        writeln!(
            w,
            "    GitHub: {}https://github.com/ItzEvhyx{}",
            term::UNDERLINE,
            term::RESET
        )?;
        writeln!(
            w,
            "    Repo:   {}https://github.com/ItzEvhyx/ezcmd{}",
            term::UNDERLINE,
            term::RESET
        )?;
    } else {
        writeln!(w, "{}", ASCII_ART.trim_matches('\n'))?;
        writeln!(w)?;
        writeln!(w, "  Welcome to ezCMD! Find the right command, in order.")?;
        writeln!(
            w,
            "  Never browse Stack Overflow for everyday terminal commands again.\n"
        )?;

        writeln!(w, "  QUICK START / HOW TO USE:")?;
        writeln!(w, "    ezcmd <query>                   Search for workflows or commands")?;
        writeln!(w, "    ezcmd --help                    Show all sections for your OS")?;
        writeln!(w, "    ezcmd --help -git               Show Git workflow cheatsheet")?;
        writeln!(w, "    ezcmd --help -shell             Show Shell command cheatsheet")?;
        writeln!(w, "    ezcmd --uninstall               Uninstall ezcmd from your machine")?;
        writeln!(w)?;
        writeln!(w, "  TRY THESE QUERIES:")?;
        writeln!(w, "    ezcmd initializing repo")?;
        writeln!(w, "    ezcmd undo last commit")?;
        writeln!(w, "    ezcmd how to branch")?;
        writeln!(w, "    ezcmd delete files")?;
        writeln!(w)?;
        writeln!(w, "  AUTHOR & CREDITS:")?;
        writeln!(w, "    Created by ItzEvhyx (Me)")?;
        writeln!(w, "    GitHub: https://github.com/ItzEvhyx")?;
        writeln!(w, "    Repo:   https://github.com/ItzEvhyx/ezcmd")?;
    }
    Ok(())
}
