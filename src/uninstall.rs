use crate::welcome;
use std::io::{self, IsTerminal, Write};
use std::path::PathBuf;

pub fn run_uninstall<W: Write>(w: &mut W, yes: bool) -> io::Result<i32> {
    if !yes && io::stdin().is_terminal() {
        print!("Are you sure you want to uninstall ezcmd from your machine? [y/N]: ");
        io::stdout().flush()?;
        let mut line = String::new();
        io::stdin().read_line(&mut line)?;
        let trimmed = line.trim();
        if !trimmed.eq_ignore_ascii_case("y") && !trimmed.eq_ignore_ascii_case("yes") {
            writeln!(w, "Uninstall aborted.")?;
            return Ok(0);
        }
    }

    let mut removed_count = 0;

    // 1. Remove current running executable
    if let Ok(current_exe) = std::env::current_exe() {
        if current_exe.exists() {
            #[cfg(windows)]
            {
                let temp_name = current_exe.with_extension("exe.old");
                if let Ok(_) = std::fs::rename(&current_exe, &temp_name) {
                    let _ = std::fs::remove_file(&temp_name);
                    writeln!(w, "Removed executable: {}", current_exe.display())?;
                    removed_count += 1;
                } else {
                    writeln!(
                        w,
                        "Note: Active binary locked by Windows. Please delete: {}",
                        current_exe.display()
                    )?;
                }
            }
            #[cfg(not(windows))]
            {
                match std::fs::remove_file(&current_exe) {
                    Ok(_) => {
                        writeln!(w, "Removed executable: {}", current_exe.display())?;
                        removed_count += 1;
                    }
                    Err(err) => {
                        writeln!(w, "Note: Could not delete {}: {err}", current_exe.display())?;
                    }
                }
            }
        }
    }

    // 2. Check standard symlink / install locations
    let mut check_paths = Vec::new();
    #[cfg(not(windows))]
    {
        if let Some(home) = std::env::var_os("HOME") {
            let home_path = PathBuf::from(home);
            check_paths.push(home_path.join(".local/bin/ezcmd"));
            check_paths.push(home_path.join(".cargo/bin/ezcmd"));
            check_paths.push(home_path.join("bin/ezcmd"));
        }
        check_paths.push(PathBuf::from("/usr/local/bin/ezcmd"));
    }
    #[cfg(windows)]
    {
        if let Some(userprofile) = std::env::var_os("USERPROFILE") {
            let user_path = PathBuf::from(userprofile);
            check_paths.push(user_path.join(".local/bin/ezcmd.exe"));
            check_paths.push(user_path.join(".cargo/bin/ezcmd.exe"));
            check_paths.push(user_path.join("bin/ezcmd.exe"));
        }
    }

    for path in check_paths {
        if path.exists() {
            if let Ok(_) = std::fs::remove_file(&path) {
                writeln!(w, "Removed installed path: {}", path.display())?;
                removed_count += 1;
            }
        }
    }

    // 3. Remove configuration & marker directory
    if let Some(cfg_dir) = welcome::get_config_dir() {
        if cfg_dir.exists() {
            if let Ok(_) = std::fs::remove_dir_all(&cfg_dir) {
                writeln!(w, "Removed configuration: {}", cfg_dir.display())?;
                removed_count += 1;
            }
        }
    }

    writeln!(w)?;
    if removed_count > 0 {
        writeln!(
            w,
            "✓ ezcmd has been successfully uninstalled from your machine."
        )?;
    } else {
        writeln!(
            w,
            "✓ ezcmd cleanup completed."
        )?;
    }
    writeln!(w, "Thank you for using ezcmd!")?;
    Ok(0)
}
