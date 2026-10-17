use ezcmd::content::TOOLS;
use ezcmd::os::Os;
use std::collections::HashSet;

#[test]
fn test_tools_exist_and_sorted() {
    assert!(!TOOLS.is_empty(), "TOOLS must not be empty");
    for w in TOOLS.windows(2) {
        assert!(
            w[0].name < w[1].name,
            "TOOLS must be sorted by name: {} vs {}",
            w[0].name,
            w[1].name
        );
    }
}

#[test]
fn test_seed_tools_present() {
    let names: Vec<&str> = TOOLS.iter().map(|t| t.name).collect();
    assert!(names.contains(&"git"), "git tool missing");
    assert!(names.contains(&"shell"), "shell tool missing");
}

#[test]
fn test_section_rules() {
    for tool in TOOLS {
        let mut seen_titles = HashSet::new();
        let mut seen_aliases = HashSet::new();

        for sec in tool.sections {
            assert!(
                seen_titles.insert(sec.title),
                "duplicate section title: {}",
                sec.title
            );
            assert!(
                sec.aliases.len() >= 3,
                "section {} must have >= 3 aliases",
                sec.title
            );

            for &alias in sec.aliases {
                assert_eq!(
                    alias,
                    alias.to_lowercase(),
                    "alias {} must be lowercase",
                    alias
                );
                assert!(
                    seen_aliases.insert(alias),
                    "duplicate alias {} in tool {}",
                    alias,
                    tool.name
                );
            }

            assert!(
                !sec.commands.is_empty(),
                "section {} has no commands",
                sec.title
            );

            for cmd in sec.commands {
                assert!(
                    !cmd.note.is_empty() && cmd.note.chars().count() <= 60,
                    "invalid note length in {}: {}",
                    sec.title,
                    cmd.note
                );
                assert!(
                    !cmd.note.ends_with('.'),
                    "note ends with period in {}: {}",
                    sec.title,
                    cmd.note
                );
            }

            // Every seed section is available on all three OSes
            for os in Os::ALL {
                assert!(
                    sec.available_on(os),
                    "section {} not available on {:?}",
                    sec.title,
                    os
                );
            }
        }
    }
}

#[test]
fn test_initializing_repo_section() {
    let git = TOOLS.iter().find(|t| t.name == "git").expect("git found");
    let init_sec = git
        .sections
        .iter()
        .find(|s| s.title == "Initializing a Repo")
        .expect("Initializing a Repo section found");

    let expected_cmds = [
        ("git init", "Initializes a repo in the current folder"),
        ("git add .", "Stages all new and changed files"),
        (
            "git commit -m \"Initial commit\"",
            "Saves the staged files as the first commit",
        ),
        ("git branch -M main", "Renames the current branch to main"),
        (
            "git remote add origin <repo-url>",
            "Links the repo to a remote on GitHub",
        ),
        (
            "git push -u origin main",
            "Uploads main and sets it as the upstream",
        ),
    ];

    assert_eq!(init_sec.commands.len(), expected_cmds.len());
    for (i, (expected_cmd, expected_note)) in expected_cmds.iter().enumerate() {
        let cmd = &init_sec.commands[i];
        assert_eq!(cmd.resolve(Os::Linux), Some(*expected_cmd));
        assert_eq!(cmd.resolve(Os::Windows), Some(*expected_cmd));
        assert_eq!(cmd.resolve(Os::Macos), Some(*expected_cmd));
        assert_eq!(cmd.note, *expected_note);
    }
}
