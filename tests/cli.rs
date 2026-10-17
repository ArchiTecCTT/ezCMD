use assert_cmd::Command;

#[test]
fn test_version() {
    let mut cmd = Command::cargo_bin("ezcmd").expect("binary exists");
    cmd.assert()
        .success()
        .stdout(predicates::str::contains("ezcmd 0.1.0"));
}
