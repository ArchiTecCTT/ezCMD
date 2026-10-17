use crate::term;
use crate::welcome;
use std::io::{self, IsTerminal, Write};
use std::path::PathBuf;

/// Collect all known installation paths for ezcmd.
fn installed_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();

    #[cfg(not(windows))]
    {
        if let Some(home) = std::env::var_os("HOME") {
            let home_path = PathBuf::from(home);
            paths.push(home_path.join(".local/bin/ezcmd"));
            paths.push(home_path.join(".cargo/bin/ezcmd"));
            paths.push(home_path.join("bin/ezcmd"));
        }
        paths.push(PathBuf::from("/usr/local/bin/ezcmd"));
    }

    #[cfg(windows)]
    {
        if let Some(userprofile) = std::env::var_os("USERPROFILE") {
            let user_path = PathBuf::from(userprofile);
            paths.push(user_path.join(".local/bin/ezcmd.exe"));
            paths.push(user_path.join(".cargo/bin/ezcmd.exe"));
            paths.push(user_path.join("bin/ezcmd.exe"));
        }
    }

    paths
}

/// Check whether ezcmd appears to be installed (any known binary or config marker exists).
fn is_installed() -> bool {
    // Check installation marker
    if let Some(marker) = welcome::get_marker_path() {
        if marker.exists() {
            return true;
        }
    }
    // Check known binary locations
    for path in installed_paths() {
        if path.exists() {
            return true;
        }
    }
    false
}

pub fn run_uninstall<W: Write>(w: &mut W, yes: bool) -> io::Result<i32> {
    // ── Guard: ezcmd must be installed ──────────────────────────────────
    if !is_installed() {
        writeln!(
            w,
            "{}error:{} ezcmd is not installed on this machine.",
            term::RED_BOLD,
            term::RESET
        )?;
        writeln!(
            w,
            "Nothing to uninstall. If you installed ezcmd to a custom location, remove it manually."
        )?;
        return Ok(1);
    }

    // ── Confirmation ───────────────────────────────────────────────────
    if !yes {
        if io::stdin().is_terminal() {
            print!("Are you sure you want to uninstall ezcmd from your machine? [y/N]: ");
            io::stdout().flush()?;
            let mut line = String::new();
            io::stdin().read_line(&mut line)?;
            let trimmed = line.trim();
            if !trimmed.eq_ignore_ascii_case("y") && !trimmed.eq_ignore_ascii_case("yes") {
                writeln!(w, "Uninstall aborted.")?;
                return Ok(0);
            }
        } else {
            let mut line = String::new();
            if io::stdin().read_line(&mut line).is_ok() && !line.trim().is_empty() {
                let trimmed = line.trim();
                if !trimmed.eq_ignore_ascii_case("y") && !trimmed.eq_ignore_ascii_case("yes") {
                    writeln!(w, "Uninstall aborted.")?;
                    return Ok(0);
                }
            } else {
                writeln!(
                    w,
                    "Uninstall requires confirmation. Pass '-y' or '--yes' to proceed non-interactively."
                )?;
                return Ok(1);
            }
        }
    }

    // ── Remove installed binaries ──────────────────────────────────────
    let mut removed_count = 0;

    for path in installed_paths() {
        if path.exists() {
            match std::fs::remove_file(&path) {
                Ok(_) => {
                    writeln!(w, "  Removed: {}", path.display())?;
                    removed_count += 1;
                }
                Err(err) => {
                    writeln!(w, "  Note: Could not delete {}: {err}", path.display())?;
                }
            }
        }
    }

    // ── Remove configuration & marker directory ────────────────────────
    if let Some(cfg_dir) = welcome::get_config_dir() {
        if cfg_dir.exists() && std::fs::remove_dir_all(&cfg_dir).is_ok() {
            writeln!(w, "  Removed config: {}", cfg_dir.display())?;
            removed_count += 1;
        }
    }

    // ── Summary ────────────────────────────────────────────────────────
    writeln!(w)?;
    if removed_count > 0 {
        writeln!(
            w,
            "{}✓ ezcmd has been successfully uninstalled from your machine.{}",
            term::CYAN_BOLD,
            term::RESET
        )?;
    } else {
        writeln!(
            w,
            "{}✓ ezcmd cleanup completed — no files needed removal.{}",
            term::CYAN_BOLD,
            term::RESET
        )?;
    }
    writeln!(w, "Thank you for using ezcmd!")?;
    Ok(0)
}
