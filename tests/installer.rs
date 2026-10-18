/// Windows PowerShell 5.1 reads a script without a BOM as Windows-1252, so a single
/// UTF-8 character (such as a check mark) breaks `powershell -File install.ps1`.
#[test]
fn test_install_ps1_is_ascii() {
    let script = include_str!("../install.ps1");
    for (i, line) in script.lines().enumerate() {
        assert!(
            line.is_ascii(),
            "install.ps1 line {} has a non-ASCII character; use [char]0x.... instead: {line}",
            i + 1
        );
    }
}
