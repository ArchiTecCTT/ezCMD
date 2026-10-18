/// The Windows shell that commands are shown for. Linux and macOS ignore it.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum Shell {
    /// Command Prompt (cmd.exe). The default when the shell cannot be detected.
    #[default]
    Cmd,
    /// Windows PowerShell 5.1 or PowerShell 7 (pwsh).
    PowerShell,
}

impl Shell {
    /// Parse a `--shell` value ("cmd" | "powershell" | "pwsh", case-insensitive).
    pub fn from_flag(name: &str) -> Option<Shell> {
        if name.eq_ignore_ascii_case("cmd") {
            Some(Shell::Cmd)
        } else if name.eq_ignore_ascii_case("powershell") || name.eq_ignore_ascii_case("pwsh") {
            Some(Shell::PowerShell)
        } else {
            None
        }
    }

    /// Display string for the shell ("Command Prompt" | "PowerShell").
    pub fn display(self) -> &'static str {
        match self {
            Shell::Cmd => "Command Prompt",
            Shell::PowerShell => "PowerShell",
        }
    }

    /// Map a process executable name to the shell it is, if any.
    pub fn from_process_name(exe: &str) -> Option<Shell> {
        let name = exe.rsplit(['\\', '/']).next().unwrap_or(exe);
        let name = name.to_ascii_lowercase();
        let name = name.strip_suffix(".exe").unwrap_or(&name);
        match name {
            "cmd" => Some(Shell::Cmd),
            "powershell" | "pwsh" | "powershell_ise" => Some(Shell::PowerShell),
            _ => None,
        }
    }

    /// Detect the shell that launched ezcmd by walking up the parent processes,
    /// so shims and wrappers between the shell and ezcmd are skipped.
    /// Falls back to Command Prompt when no known shell is found.
    pub fn detect() -> Shell {
        #[cfg(windows)]
        if let Some(shell) = win::detect_parent_shell() {
            return shell;
        }
        Shell::Cmd
    }
}

#[cfg(windows)]
mod win {
    use super::Shell;
    use std::collections::HashMap;
    use windows_sys::Win32::Foundation::{CloseHandle, INVALID_HANDLE_VALUE};
    use windows_sys::Win32::System::Diagnostics::ToolHelp::{
        CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W,
        TH32CS_SNAPPROCESS,
    };

    /// How many ancestors to inspect before giving up.
    const MAX_DEPTH: usize = 4;

    pub fn detect_parent_shell() -> Option<Shell> {
        let procs = snapshot()?;
        let mut pid = std::process::id();
        for _ in 0..MAX_DEPTH {
            let (parent, _) = procs.get(&pid)?;
            let (_, name) = procs.get(parent)?;
            if let Some(shell) = Shell::from_process_name(name) {
                return Some(shell);
            }
            pid = *parent;
        }
        None
    }

    /// pid -> (parent pid, executable name) for every running process.
    fn snapshot() -> Option<HashMap<u32, (u32, String)>> {
        let mut procs = HashMap::new();
        // SAFETY: plain Win32 calls; the handle is closed before returning and
        // `entry.dwSize` is set as the API requires.
        unsafe {
            let snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
            if snap == INVALID_HANDLE_VALUE {
                return None;
            }
            let mut entry: PROCESSENTRY32W = std::mem::zeroed();
            entry.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;
            let mut ok = Process32FirstW(snap, &mut entry);
            while ok != 0 {
                let len = entry
                    .szExeFile
                    .iter()
                    .position(|&c| c == 0)
                    .unwrap_or(entry.szExeFile.len());
                let name = String::from_utf16_lossy(&entry.szExeFile[..len]);
                procs.insert(entry.th32ProcessID, (entry.th32ParentProcessID, name));
                ok = Process32NextW(snap, &mut entry);
            }
            CloseHandle(snap);
        }
        Some(procs)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_from_flag() {
        assert_eq!(Shell::from_flag("cmd"), Some(Shell::Cmd));
        assert_eq!(Shell::from_flag("CMD"), Some(Shell::Cmd));
        assert_eq!(Shell::from_flag("powershell"), Some(Shell::PowerShell));
        assert_eq!(Shell::from_flag("PowerShell"), Some(Shell::PowerShell));
        assert_eq!(Shell::from_flag("pwsh"), Some(Shell::PowerShell));
        assert_eq!(Shell::from_flag("bash"), None);
        assert_eq!(Shell::from_flag(""), None);
    }

    #[test]
    fn test_from_process_name() {
        assert_eq!(Shell::from_process_name("cmd.exe"), Some(Shell::Cmd));
        assert_eq!(Shell::from_process_name("CMD.EXE"), Some(Shell::Cmd));
        assert_eq!(
            Shell::from_process_name("powershell.exe"),
            Some(Shell::PowerShell)
        );
        assert_eq!(
            Shell::from_process_name("pwsh.exe"),
            Some(Shell::PowerShell)
        );
        assert_eq!(
            Shell::from_process_name(r"C:\Program Files\PowerShell\7\pwsh.exe"),
            Some(Shell::PowerShell)
        );
        assert_eq!(Shell::from_process_name("explorer.exe"), None);
        assert_eq!(Shell::from_process_name("bash.exe"), None);
    }

    #[test]
    fn test_default_is_cmd() {
        assert_eq!(Shell::default(), Shell::Cmd);
    }
}
