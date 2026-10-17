use serde::Deserialize;
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Deserialize, Debug)]
struct RawToolFile {
    tool: String,
    #[serde(default)]
    section: Vec<RawSection>,
}

#[derive(Deserialize, Debug)]
struct RawSection {
    title: String,
    #[serde(default)]
    aliases: Vec<String>,
    #[serde(default)]
    command: Vec<RawCommand>,
}

#[derive(Deserialize, Debug)]
struct RawCommand {
    note: String,
    cmd: Option<String>,
    unix: Option<String>,
    windows: Option<String>,
    linux: Option<String>,
    macos: Option<String>,
}

fn is_balanced_brackets(s: &str) -> bool {
    let mut in_placeholder = false;
    let chars: Vec<char> = s.chars().collect();
    for (i, &c) in chars.iter().enumerate() {
        if c == '<' {
            if in_placeholder {
                return false; // nested <
            }
            in_placeholder = true;
        } else if c == '>' {
            if in_placeholder {
                in_placeholder = false;
            } else {
                // > outside a placeholder. Allow shell redirection operator e.g. ` > ` or ` 2> `
                let is_redirect = (i > 0
                    && (chars[i - 1].is_whitespace() || chars[i - 1].is_ascii_digit()))
                    && (i + 1 == chars.len() || chars[i + 1].is_whitespace());
                if !is_redirect {
                    return false;
                }
            }
        }
    }
    !in_placeholder
}

fn validate_tool_file(
    path_display: &str,
    raw: &RawToolFile,
    seen_tools: &mut HashSet<String>,
) -> Result<(), String> {
    let tool_name = raw.tool.trim();
    if tool_name.is_empty() {
        return Err(format!("{path_display}: tool name cannot be empty"));
    }
    if raw.tool != raw.tool.to_lowercase() {
        return Err(format!(
            "{path_display}: tool \"{}\" must be lowercase",
            raw.tool
        ));
    }
    if raw.tool.contains(char::is_whitespace) {
        return Err(format!(
            "{path_display}: tool \"{}\" cannot contain whitespace",
            raw.tool
        ));
    }
    if matches!(raw.tool.as_str(), "windows" | "linux" | "macos") {
        return Err(format!(
            "{path_display}: tool name \"{}\" conflicts with OS name",
            raw.tool
        ));
    }
    if !seen_tools.insert(raw.tool.clone()) {
        return Err(format!(
            "{path_display}: duplicate tool name \"{}\"",
            raw.tool
        ));
    }

    let mut seen_titles = HashSet::new();
    let mut seen_aliases = HashSet::new();

    for sec in &raw.section {
        let title = sec.title.trim();
        if title.is_empty() {
            return Err(format!("{path_display}: section title cannot be empty"));
        }
        if !seen_titles.insert(sec.title.clone()) {
            return Err(format!(
                "{path_display}: section \"{}\": duplicate section title",
                sec.title
            ));
        }

        if sec.aliases.len() < 3 {
            return Err(format!(
                "{path_display}: section \"{}\": must have at least 3 aliases, found {}",
                sec.title,
                sec.aliases.len()
            ));
        }

        for alias in &sec.aliases {
            if alias.trim().is_empty() {
                return Err(format!(
                    "{path_display}: section \"{}\": alias cannot be empty",
                    sec.title
                ));
            }
            if alias != &alias.to_lowercase() {
                return Err(format!(
                    "{path_display}: section \"{}\": alias \"{}\" must be lowercase",
                    sec.title, alias
                ));
            }
            if !seen_aliases.insert(alias.clone()) {
                return Err(format!(
                    "{path_display}: section \"{}\": duplicate alias \"{}\"",
                    sec.title, alias
                ));
            }
        }

        if sec.command.is_empty() {
            return Err(format!(
                "{path_display}: section \"{}\": must have at least 1 command",
                sec.title
            ));
        }

        for cmd in &sec.command {
            if cmd.note.trim().is_empty() {
                return Err(format!(
                    "{path_display}: section \"{}\": command note cannot be empty",
                    sec.title
                ));
            }
            if cmd.note.chars().count() > 60 {
                return Err(format!(
                    "{path_display}: section \"{}\": command note exceeds 60 characters: \"{}\"",
                    sec.title, cmd.note
                ));
            }
            if cmd.note.ends_with('.') {
                return Err(format!(
                    "{path_display}: section \"{}\": command note must not end with a period: \"{}\"",
                    sec.title, cmd.note
                ));
            }

            let cmd_strings = [
                ("cmd", &cmd.cmd),
                ("unix", &cmd.unix),
                ("windows", &cmd.windows),
                ("linux", &cmd.linux),
                ("macos", &cmd.macos),
            ];

            let has_any_cmd = cmd_strings.iter().any(|(_, opt)| opt.is_some());
            if !has_any_cmd {
                return Err(format!(
                    "{path_display}: section \"{}\": command must specify at least one of cmd, unix, windows, linux, macos",
                    sec.title
                ));
            }

            for (_, opt) in &cmd_strings {
                if let Some(s) = opt {
                    if s.contains(['\n', '\r', '\t']) {
                        return Err(format!(
                            "{path_display}: section \"{}\": command \"{}\" contains newline or tab",
                            sec.title, s
                        ));
                    }
                    if !is_balanced_brackets(s) {
                        return Err(format!(
                            "{path_display}: section \"{}\": command \"{}\" has unbalanced < >",
                            sec.title, s
                        ));
                    }
                }
            }
        }
    }

    Ok(())
}

fn emit_option_str(opt: &Option<String>) -> String {
    match opt {
        Some(s) => format!("Some({:?})", s),
        None => "None".to_string(),
    }
}

fn generate_content_rs(tools: &[RawToolFile]) -> String {
    let mut out = String::new();
    out.push_str("// Generated by build.rs - DO NOT EDIT\n\n");
    out.push_str("pub static TOOLS: &[Tool] = &[\n");

    for tool in tools {
        out.push_str("    Tool {\n");
        out.push_str(&format!("        name: {:?},\n", tool.tool));
        out.push_str("        sections: &[\n");
        for sec in &tool.section {
            out.push_str("            Section {\n");
            out.push_str(&format!("                title: {:?},\n", sec.title));
            out.push_str("                aliases: &[\n");
            for alias in &sec.aliases {
                out.push_str(&format!("                    {:?},\n", alias));
            }
            out.push_str("                ],\n");
            out.push_str("                commands: &[\n");
            for cmd in &sec.command {
                out.push_str("                    Command {\n");
                out.push_str(&format!("                        note: {:?},\n", cmd.note));
                out.push_str(&format!(
                    "                        cmd: {},\n",
                    emit_option_str(&cmd.cmd)
                ));
                out.push_str(&format!(
                    "                        unix: {},\n",
                    emit_option_str(&cmd.unix)
                ));
                out.push_str(&format!(
                    "                        windows: {},\n",
                    emit_option_str(&cmd.windows)
                ));
                out.push_str(&format!(
                    "                        linux: {},\n",
                    emit_option_str(&cmd.linux)
                ));
                out.push_str(&format!(
                    "                        macos: {},\n",
                    emit_option_str(&cmd.macos)
                ));
                out.push_str("                    },\n");
            }
            out.push_str("                ],\n");
            out.push_str("            },\n");
        }
        out.push_str("        ],\n");
        out.push_str("    },\n");
    }

    out.push_str("];\n");
    out
}

fn main() {
    println!("cargo:rerun-if-changed=data");
    println!("cargo:rerun-if-changed=build.rs");

    let data_dir = Path::new("data");
    if !data_dir.exists() {
        panic!("data directory does not exist");
    }

    let mut toml_files: Vec<PathBuf> = Vec::new();
    let entries = fs::read_dir(data_dir).expect("failed to read data directory");
    for entry in entries {
        let entry = entry.expect("failed to read dir entry");
        let path = entry.path();
        if path.is_file() && path.extension().is_some_and(|ext| ext == "toml") {
            println!("cargo:rerun-if-changed={}", path.display());
            toml_files.push(path);
        }
    }

    // Sort files for deterministic processing
    toml_files.sort();

    let mut parsed_tools: Vec<RawToolFile> = Vec::new();
    let mut seen_tools = HashSet::new();

    for path in toml_files {
        let path_str = path.to_string_lossy();
        let content = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("failed to read {}: {}", path_str, e));
        let raw_tool: RawToolFile = toml::from_str(&content)
            .unwrap_or_else(|e| panic!("{}: failed to parse TOML: {}", path_str, e));

        if let Err(msg) = validate_tool_file(&path_str, &raw_tool, &mut seen_tools) {
            panic!("{}", msg);
        }

        parsed_tools.push(raw_tool);
    }

    // Tools are sorted by name; sections keep file order
    parsed_tools.sort_by(|a, b| a.tool.cmp(&b.tool));

    let generated_code = generate_content_rs(&parsed_tools);

    let out_dir = std::env::var("OUT_DIR").expect("OUT_DIR not set");
    let dest_path = Path::new(&out_dir).join("content.rs");
    fs::write(&dest_path, generated_code).expect("failed to write generated content.rs");
}
