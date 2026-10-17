use assert_cmd::Command;
use predicates::prelude::*;

#[test]
fn test_version() {
    let mut cmd = Command::cargo_bin("ezcmd").expect("binary exists");
    cmd.arg("--version")
        .assert()
        .success()
        .stdout(predicate::str::contains("ezcmd 0.1.0"));
}

#[test]
fn test_usage_no_args() {
    let mut cmd = Command::cargo_bin("ezcmd").expect("binary exists");
    cmd.assert()
        .success()
        .stdout(predicate::str::contains("USAGE:"))
        .stdout(predicate::str::contains("ezcmd <query>"));
}

#[test]
fn test_query_initializing_repo() {
    let mut cmd = Command::cargo_bin("ezcmd").expect("binary exists");
    cmd.args(["initializing", "repo"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Initializing a Repo"))
        .stdout(predicate::str::contains("git init"))
        .stdout(predicate::str::contains("git push -u origin main"));
}

#[test]
fn test_plain_output_no_ansi() {
    let mut cmd = Command::cargo_bin("ezcmd").expect("binary exists");
    cmd.args(["--plain", "initializing", "repo"])
        .assert()
        .success()
        .stdout(predicate::str::contains("# ---Initializing a Repo---"))
        .stdout(predicate::str::contains(
            "git init --- Initializes a repo in the current folder",
        ))
        .stdout(predicate::str::contains("\x1b[").not());
}

#[test]
fn test_no_color_env_no_ansi() {
    let mut cmd = Command::cargo_bin("ezcmd").expect("binary exists");
    cmd.args(["initializing", "repo"])
        .env("NO_COLOR", "1")
        .assert()
        .success()
        .stdout(predicate::str::contains("Initializing a Repo"))
        .stdout(predicate::str::contains("\x1b[").not());
}

#[test]
fn test_no_match_exit_code_1() {
    let mut cmd = Command::cargo_bin("ezcmd").expect("binary exists");
    cmd.args(["xyznonexistentrandomquery123"])
        .assert()
        .code(1)
        .stdout(predicate::str::contains("No match for"));
}

#[test]
fn test_unknown_flag_exit_code_2() {
    let mut cmd = Command::cargo_bin("ezcmd").expect("binary exists");
    cmd.args(["--bogus-flag"])
        .assert()
        .code(2)
        .stderr(predicate::str::contains("unknown flag"));
}

#[test]
fn test_piped_stdin_does_not_block() {
    // assert_cmd runs commands with piped stdin (not a terminal)
    let mut cmd = Command::cargo_bin("ezcmd").expect("binary exists");
    cmd.args(["repo"]).assert().success();
}

#[test]
fn test_help_git_single_section() {
    let mut cmd = Command::cargo_bin("ezcmd").expect("binary exists");
    cmd.args(["--help", "-git", "-initialize", "repo"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Initializing a Repo"))
        .stdout(predicate::str::contains("git init"));
}
