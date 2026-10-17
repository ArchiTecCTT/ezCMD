use std::io::IsTerminal;

pub const BOLD: &str = "\x1b[1m";
pub const DIM: &str = "\x1b[90m";
pub const CYAN_BOLD: &str = "\x1b[1;36m";
pub const YELLOW: &str = "\x1b[33m";
pub const RED_BOLD: &str = "\x1b[1;31m";
pub const UNDERLINE: &str = "\x1b[4m";
pub const RESET: &str = "\x1b[0m";

#[cfg(windows)]
fn init_windows_vt() -> bool {
    enable_ansi_support::enable_ansi_support().is_ok()
}

#[cfg(not(windows))]
fn init_windows_vt() -> bool {
    true
}

/// True only if stdout is a terminal, plain is false, NO_COLOR is unset or empty,
/// and TERM is not dumb. On Windows, calls enable_ansi_support() first and returns
/// false if it fails.
pub fn color_enabled(plain: bool) -> bool {
    if plain {
        return false;
    }
    if !std::io::stdout().is_terminal() {
        return false;
    }
    if std::env::var_os("NO_COLOR").is_some_and(|v| !v.is_empty()) {
        return false;
    }
    if std::env::var("TERM").is_ok_and(|v| v == "dumb") {
        return false;
    }
    init_windows_vt()
}

/// Terminal width from terminal_size, falling back to 80.
pub fn width() -> usize {
    terminal_size::terminal_size()
        .map(|(w, _)| w.0 as usize)
        .unwrap_or(80)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_plain_always_disables_color() {
        assert!(!color_enabled(true));
    }

    #[test]
    fn test_width_fallback() {
        let w = width();
        assert!(w >= 20, "terminal width should be reasonable");
    }

    #[test]
    fn test_style_constants() {
        assert_eq!(BOLD, "\x1b[1m");
        assert_eq!(DIM, "\x1b[90m");
        assert_eq!(CYAN_BOLD, "\x1b[1;36m");
        assert_eq!(YELLOW, "\x1b[33m");
        assert_eq!(RED_BOLD, "\x1b[1;31m");
        assert_eq!(UNDERLINE, "\x1b[4m");
        assert_eq!(RESET, "\x1b[0m");
    }
}
