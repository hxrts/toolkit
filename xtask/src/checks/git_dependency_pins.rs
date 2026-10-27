use std::{fs, path::Path, process::Command};

use anyhow::{Context, Result};
use serde_json::Value;

use crate::{config::ToolkitConfig, report::FlatFindingSet};

pub fn run(repo_root: &Path, config: &ToolkitConfig) -> Result<FlatFindingSet> {
    let Some(check) = &config.checks.git_dependency_pins else {
        return Ok(FlatFindingSet::default());
    };
    if !check.enabled {
        return Ok(FlatFindingSet::default());
    }

    let pins_path = repo_root.join(&check.pins_file);
    let contents = fs::read_to_string(&pins_path)
        .with_context(|| format!("reading {}", pins_path.display()))?;
    let json: Value = serde_json::from_str(&contents)
        .with_context(|| format!("parsing {}", pins_path.display()))?;
    let mut findings = FlatFindingSet::default();
    let Some(dependencies) = json.get("dependencies").and_then(Value::as_array) else {
        findings.entries.insert(format!(
            "{}: missing or invalid `dependencies` array",
            check.pins_file
        ));
        return Ok(findings);
    };
    if dependencies.is_empty() {
        findings.entries.insert(format!(
            "{}: dependencies array must not be empty",
            check.pins_file
        ));
        return Ok(findings);
    }

    for dependency in dependencies {
        let Some(name) = dependency.get("name").and_then(Value::as_str) else {
            findings.entries.insert(format!(
                "{}: invalid dependency pin entry missing `name`",
                check.pins_file
            ));
            continue;
        };
        let Some(path) = dependency.get("path").and_then(Value::as_str) else {
            findings.entries.insert(format!(
                "{}: {name}: invalid dependency pin entry missing `path`",
                check.pins_file
            ));
            continue;
        };
        let Some(expected) = dependency.get("revision").and_then(Value::as_str) else {
            findings.entries.insert(format!(
                "{}: {name}: invalid dependency pin entry missing `revision`",
                check.pins_file
            ));
            continue;
        };
        let checkout = repo_root.join(path);
        if !checkout.exists() {
            findings
                .entries
                .insert(format!("{name}: missing checkout at {path}"));
            continue;
        }
        let output = Command::new("git")
            .current_dir(&checkout)
            .args(["rev-parse", "HEAD"])
            .output()
            .with_context(|| {
                format!("running git rev-parse in {}", checkout.display())
            })?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            findings
                .entries
                .insert(format!("{name}: failed to read git revision ({stderr})"));
            continue;
        }
        let actual = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if actual != expected {
            findings
                .entries
                .insert(format!("{name}: expected {expected}, found {actual}"));
        }
    }

    Ok(findings)
}

#[cfg(test)]
mod tests {
    use std::{fs, path::Path, process::Command};

    use super::run;
    use crate::config;

    #[test]
    fn git_dependency_pins_reports_clean_repo() {
        let root = temp_dir("pass");
        init_git_repo(&root.join("dep"));
        let revision = git_head(&root.join("dep"));
        fs::create_dir_all(root.join("lean")).expect("create lean");
        fs::write(
            root.join("toolkit.toml"),
            "[workspace]\ncrate_roots=[]\ninclude_crates=[]\nexclude_crates=[]\n\n[checks.git_dependency_pins]\nenabled=true\npins_file=\"lean/dependency_pins.json\"\n",
        )
        .expect("write config");
        fs::write(
            root.join("lean/dependency_pins.json"),
            format!(
                "{{\"dependencies\":[{{\"name\":\"dep\",\"path\":\"dep\",\"revision\":\"{revision}\"}}]}}"
            ),
        )
        .expect("write pins");
        let cfg = config::load(&root.join("toolkit.toml")).expect("load config");
        assert!(run(&root, &cfg).expect("run").is_empty());
        cleanup(&root);
    }

    #[test]
    fn git_dependency_pins_reports_mismatch() {
        let root = temp_dir("fail");
        init_git_repo(&root.join("dep"));
        fs::create_dir_all(root.join("lean")).expect("create lean");
        fs::write(
            root.join("toolkit.toml"),
            "[workspace]\ncrate_roots=[]\ninclude_crates=[]\nexclude_crates=[]\n\n[checks.git_dependency_pins]\nenabled=true\npins_file=\"lean/dependency_pins.json\"\n",
        )
        .expect("write config");
        fs::write(
            root.join("lean/dependency_pins.json"),
            "{\"dependencies\":[{\"name\":\"dep\",\"path\":\"dep\",\"revision\":\"deadbeef\"}]}",
        )
        .expect("write pins");
        let cfg = config::load(&root.join("toolkit.toml")).expect("load config");
        let findings = run(&root, &cfg).expect("run");
        assert!(findings
            .entries
            .iter()
            .any(|entry| entry.contains("expected deadbeef")));
        cleanup(&root);
    }

    fn temp_dir(label: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "toolkit-git-pins-{label}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("time")
                .as_nanos()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("create temp dir");
        dir
    }

    fn init_git_repo(path: &Path) {
        fs::create_dir_all(path).expect("create repo");
        run_cmd(path, "git", &["init"]);
        run_cmd(
            path,
            "git",
            &["config", "user.email", "toolkit@example.com"],
        );
        run_cmd(path, "git", &["config", "user.name", "Toolkit"]);
        fs::write(path.join("README.md"), "hello\n").expect("write readme");
        run_cmd(path, "git", &["add", "README.md"]);
        run_cmd(path, "git", &["commit", "-m", "init"]);
    }

    fn git_head(path: &Path) -> String {
        let output = Command::new("git")
            .current_dir(path)
            .args(["rev-parse", "HEAD"])
            .output()
            .expect("git rev-parse");
        assert!(output.status.success());
        String::from_utf8_lossy(&output.stdout).trim().to_string()
    }

    fn run_cmd(path: &Path, program: &str, args: &[&str]) {
        let status = Command::new(program)
            .args(args)
            .current_dir(path)
            .status()
            .expect("run command");
        assert!(status.success());
    }

    fn cleanup(path: &Path) {
        let _ = fs::remove_dir_all(path);
    }
}
