#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Os {
    Windows,
    Linux,
    Macos,
}

impl Os {
    pub const ALL: [Os; 3] = [Os::Windows, Os::Linux, Os::Macos];

    /// Detect the current operating system from std::env::consts::OS.
    /// Any non-windows/non-macos OS is treated as Linux (unix).
    pub fn current() -> Os {
        match std::env::consts::OS {
            "windows" => Os::Windows,
            "macos" => Os::Macos,
            _ => Os::Linux,
        }
    }

    /// Parse an OS flag name ("windows" | "linux" | "macos", case-insensitive).
    pub fn from_flag(name: &str) -> Option<Os> {
        if name.eq_ignore_ascii_case("windows") {
            Some(Os::Windows)
        } else if name.eq_ignore_ascii_case("linux") {
            Some(Os::Linux)
        } else if name.eq_ignore_ascii_case("macos") {
            Some(Os::Macos)
        } else {
            None
        }
    }

    /// Lowercase OS identifier ("windows" | "linux" | "macos").
    pub fn name(self) -> &'static str {
        match self {
            Os::Windows => "windows",
            Os::Linux => "linux",
            Os::Macos => "macos",
        }
    }

    /// Display string for the OS ("Windows" | "Linux" | "macOS").
    pub fn display(self) -> &'static str {
        match self {
            Os::Windows => "Windows",
            Os::Linux => "Linux",
            Os::Macos => "macOS",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_from_flag() {
        assert_eq!(Os::from_flag("windows"), Some(Os::Windows));
        assert_eq!(Os::from_flag("WINDOWS"), Some(Os::Windows));
        assert_eq!(Os::from_flag("Windows"), Some(Os::Windows));
        assert_eq!(Os::from_flag("linux"), Some(Os::Linux));
        assert_eq!(Os::from_flag("Linux"), Some(Os::Linux));
        assert_eq!(Os::from_flag("macos"), Some(Os::Macos));
        assert_eq!(Os::from_flag("MacOS"), Some(Os::Macos));
        assert_eq!(Os::from_flag("bsd"), None);
        assert_eq!(Os::from_flag("git"), None);
    }

    #[test]
    fn test_name_and_display() {
        assert_eq!(Os::Windows.name(), "windows");
        assert_eq!(Os::Windows.display(), "Windows");
        assert_eq!(Os::Linux.name(), "linux");
        assert_eq!(Os::Linux.display(), "Linux");
        assert_eq!(Os::Macos.name(), "macos");
        assert_eq!(Os::Macos.display(), "macOS");
    }

    #[test]
    fn test_current_returns_valid_os() {
        let current = Os::current();
        assert!(Os::ALL.contains(&current));
    }
}
