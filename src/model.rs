use crate::os::Os;

#[derive(Debug, PartialEq, Eq)]
pub struct Tool {
    pub name: &'static str,
    pub sections: &'static [Section],
}

#[derive(Debug, PartialEq, Eq)]
pub struct Section {
    pub title: &'static str,
    pub aliases: &'static [&'static str],
    pub commands: &'static [Command],
}

#[derive(Debug, PartialEq, Eq)]
pub struct Command {
    pub note: &'static str,
    pub cmd: Option<&'static str>,  // all OSes
    pub unix: Option<&'static str>, // linux + macos
    pub windows: Option<&'static str>,
    pub linux: Option<&'static str>,
    pub macos: Option<&'static str>,
}

impl Command {
    /// Precedence: exact OS key > unix (linux/macos only) > cmd.
    pub fn resolve(&self, os: Os) -> Option<&'static str> {
        match os {
            Os::Windows => self.windows.or(self.cmd),
            Os::Linux => self.linux.or(self.unix).or(self.cmd),
            Os::Macos => self.macos.or(self.unix).or(self.cmd),
        }
    }
}

impl Section {
    /// True if at least one command resolves for `os`.
    pub fn available_on(&self, os: Os) -> bool {
        self.commands.iter().any(|c| c.resolve(os).is_some())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_resolve_cmd_fallback() {
        let cmd = Command {
            note: "test note",
            cmd: Some("generic-cmd"),
            unix: None,
            windows: None,
            linux: None,
            macos: None,
        };
        assert_eq!(cmd.resolve(Os::Windows), Some("generic-cmd"));
        assert_eq!(cmd.resolve(Os::Linux), Some("generic-cmd"));
        assert_eq!(cmd.resolve(Os::Macos), Some("generic-cmd"));
    }

    #[test]
    fn test_resolve_unix_precedence() {
        let cmd = Command {
            note: "test note",
            cmd: Some("generic-cmd"),
            unix: Some("unix-cmd"),
            windows: None,
            linux: None,
            macos: None,
        };
        assert_eq!(cmd.resolve(Os::Windows), Some("generic-cmd"));
        assert_eq!(cmd.resolve(Os::Linux), Some("unix-cmd"));
        assert_eq!(cmd.resolve(Os::Macos), Some("unix-cmd"));
    }

    #[test]
    fn test_resolve_exact_os_precedence() {
        let cmd = Command {
            note: "test note",
            cmd: Some("generic-cmd"),
            unix: Some("unix-cmd"),
            windows: Some("win-cmd"),
            linux: Some("linux-cmd"),
            macos: Some("macos-cmd"),
        };
        assert_eq!(cmd.resolve(Os::Windows), Some("win-cmd"));
        assert_eq!(cmd.resolve(Os::Linux), Some("linux-cmd"));
        assert_eq!(cmd.resolve(Os::Macos), Some("macos-cmd"));
    }

    #[test]
    fn test_resolve_none_when_no_match() {
        let cmd = Command {
            note: "test note",
            cmd: None,
            unix: None,
            windows: Some("win-only"),
            linux: None,
            macos: None,
        };
        assert_eq!(cmd.resolve(Os::Windows), Some("win-only"));
        assert_eq!(cmd.resolve(Os::Linux), None);
        assert_eq!(cmd.resolve(Os::Macos), None);
    }

    #[test]
    fn test_section_available_on() {
        static CMD_WIN: [Command; 1] = [Command {
            note: "win",
            cmd: None,
            unix: None,
            windows: Some("win-only"),
            linux: None,
            macos: None,
        }];
        let sec = Section {
            title: "Test Section",
            aliases: &["test"],
            commands: &CMD_WIN,
        };
        assert!(sec.available_on(Os::Windows));
        assert!(!sec.available_on(Os::Linux));
        assert!(!sec.available_on(Os::Macos));
    }
}
