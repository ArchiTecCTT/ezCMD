use crate::os::Os;
use crate::shell::Shell;

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
    pub powershell: Option<&'static str>, // windows, PowerShell only
    pub linux: Option<&'static str>,
    pub macos: Option<&'static str>,
}

impl Command {
    /// Precedence: exact OS key > unix (linux/macos only) > cmd.
    /// On Windows this is the Command Prompt form; see `resolve_for`.
    pub fn resolve(&self, os: Os) -> Option<&'static str> {
        self.resolve_for(os, Shell::Cmd)
    }

    /// Like `resolve`, but in PowerShell on Windows the `powershell` key wins:
    /// powershell > windows > cmd. `shell` is ignored on Linux and macOS.
    pub fn resolve_for(&self, os: Os, shell: Shell) -> Option<&'static str> {
        match os {
            Os::Windows => match shell {
                Shell::Cmd => self.windows.or(self.cmd),
                Shell::PowerShell => self.powershell.or(self.windows).or(self.cmd),
            },
            Os::Linux => self.linux.or(self.unix).or(self.cmd),
            Os::Macos => self.macos.or(self.unix).or(self.cmd),
        }
    }
}

impl Section {
    /// True if at least one command resolves for `os`.
    pub fn available_on(&self, os: Os) -> bool {
        self.available_for(os, Shell::Cmd)
    }

    /// True if at least one command resolves for `os` in `shell`.
    pub fn available_for(&self, os: Os, shell: Shell) -> bool {
        self.commands
            .iter()
            .any(|c| c.resolve_for(os, shell).is_some())
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
            powershell: None,
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
            powershell: None,
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
            powershell: None,
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
            powershell: None,
            linux: None,
            macos: None,
        };
        assert_eq!(cmd.resolve(Os::Windows), Some("win-only"));
        assert_eq!(cmd.resolve(Os::Linux), None);
        assert_eq!(cmd.resolve(Os::Macos), None);
    }

    #[test]
    fn test_resolve_powershell_precedence() {
        let cmd = Command {
            note: "test note",
            cmd: Some("generic-cmd"),
            unix: Some("unix-cmd"),
            windows: Some("win-cmd"),
            powershell: Some("ps-cmd"),
            linux: None,
            macos: None,
        };
        assert_eq!(
            cmd.resolve_for(Os::Windows, Shell::PowerShell),
            Some("ps-cmd")
        );
        assert_eq!(cmd.resolve_for(Os::Windows, Shell::Cmd), Some("win-cmd"));
        assert_eq!(cmd.resolve(Os::Windows), Some("win-cmd"));
        assert_eq!(
            cmd.resolve_for(Os::Linux, Shell::PowerShell),
            Some("unix-cmd")
        );
        assert_eq!(
            cmd.resolve_for(Os::Macos, Shell::PowerShell),
            Some("unix-cmd")
        );
    }

    #[test]
    fn test_resolve_powershell_falls_back() {
        let cmd = Command {
            note: "test note",
            cmd: Some("generic-cmd"),
            unix: None,
            windows: Some("win-cmd"),
            powershell: None,
            linux: None,
            macos: None,
        };
        assert_eq!(
            cmd.resolve_for(Os::Windows, Shell::PowerShell),
            Some("win-cmd")
        );

        let shared = Command {
            note: "test note",
            cmd: Some("generic-cmd"),
            unix: None,
            windows: None,
            powershell: None,
            linux: None,
            macos: None,
        };
        assert_eq!(
            shared.resolve_for(Os::Windows, Shell::PowerShell),
            Some("generic-cmd")
        );
    }

    #[test]
    fn test_section_available_for_powershell_only() {
        static CMD_PS: [Command; 1] = [Command {
            note: "ps",
            cmd: None,
            unix: None,
            windows: None,
            powershell: Some("Get-Thing"),
            linux: None,
            macos: None,
        }];
        let sec = Section {
            title: "PS Section",
            aliases: &["ps"],
            commands: &CMD_PS,
        };
        assert!(sec.available_for(Os::Windows, Shell::PowerShell));
        assert!(!sec.available_for(Os::Windows, Shell::Cmd));
        assert!(!sec.available_on(Os::Windows));
        assert!(!sec.available_for(Os::Linux, Shell::PowerShell));
    }

    #[test]
    fn test_section_available_on() {
        static CMD_WIN: [Command; 1] = [Command {
            note: "win",
            cmd: None,
            unix: None,
            windows: Some("win-only"),
            powershell: None,
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
