use std::{collections::BTreeMap, fs, path::Path};

use anyhow::{Context, Result};

use crate::{
    checks::formal_claim_scope::scan_file,
    config::{JustRecipeContract, ToolkitConfig},
    report::FlatFindingSet,
};

pub fn run(repo_root: &Path, config: &ToolkitConfig) -> Result<FlatFindingSet> {
    let Some(check) = &config.checks.ci_assurance_lanes else {
        return Ok(FlatFindingSet::default());
    };
    if !check.enabled {
        return Ok(FlatFindingSet::default());
    }

    let justfile_path = repo_root.join(&check.justfile_path);
    let recipes = parse_justfile_recipes(&justfile_path)?;
    let mut findings = FlatFindingSet::default();
    for recipe in &check.recipe_contracts {
        scan_recipe(recipe, &recipes, &mut findings);
    }
    for contract in &check.file_contracts {
        scan_file(repo_root, contract, &mut findings)?;
    }
    Ok(findings)
}

fn parse_justfile_recipes(path: &Path) -> Result<BTreeMap<String, String>> {
    let contents = fs::read_to_string(path)
        .with_context(|| format!("reading {}", path.display()))?;
    let mut recipes = BTreeMap::new();
    let mut current_name: Option<String> = None;
    let mut current_body: Vec<String> = Vec::new();

    for line in contents.lines() {
        let is_recipe_header = !line.is_empty()
            && !line.starts_with(' ')
            && !line.starts_with('\t')
            && line.contains(':');
        if is_recipe_header {
            if let Some(name) = current_name.take() {
                recipes.insert(name, current_body.join("\n"));
            }
            current_body.clear();
            let name = line.split(':').next().unwrap_or_default();
            let name = name.split_whitespace().next().unwrap_or_default();
            current_name = Some(name.to_string());
            continue;
        }
        if current_name.is_some() && (line.starts_with(' ') || line.starts_with('\t')) {
            current_body.push(line.to_string());
        }
    }

    if let Some(name) = current_name {
        recipes.insert(name, current_body.join("\n"));
    }
    Ok(recipes)
}

fn scan_recipe(
    recipe: &JustRecipeContract,
    recipes: &BTreeMap<String, String>,
    findings: &mut FlatFindingSet,
) {
    let Some(body) = recipes.get(&recipe.recipe) else {
        findings
            .entries
            .insert(format!("missing just recipe `{}`", recipe.recipe));
        return;
    };
    for literal in &recipe.required_literals {
        if !body.contains(literal) {
            findings.entries.insert(format!(
                "just recipe `{}` missing required text `{}`",
                recipe.recipe, literal
            ));
        }
    }
    for literal in &recipe.forbidden_literals {
        if body.contains(literal) {
            findings.entries.insert(format!(
                "just recipe `{}` contains forbidden text `{}`",
                recipe.recipe, literal
            ));
        }
    }
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::{parse_justfile_recipes, run};
    use crate::config;

    #[test]
    fn parses_recipe_bodies() {
        let dir = std::env::temp_dir()
            .join(format!("toolkit-justfile-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("create dir");
        let justfile = dir.join("justfile");
        std::fs::write(
            &justfile,
            "alpha:\n    echo one\nbeta arg='x':\n    echo two\n",
        )
        .expect("write justfile");
        let recipes = parse_justfile_recipes(&justfile).expect("parse justfile");
        assert_eq!(recipes.get("alpha").expect("alpha"), "    echo one");
        assert_eq!(recipes.get("beta").expect("beta"), "    echo two");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn ci_assurance_lanes_reports_clean_contracts() {
        let dir = std::env::temp_dir().join(format!(
            "toolkit-ci-lanes-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("time")
                .as_nanos()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join(".github/workflows")).expect("create workflows");
        fs::write(
            dir.join("toolkit.toml"),
            "[workspace]\ncrate_roots=[]\ninclude_crates=[]\nexclude_crates=[]\n\n[checks.ci_assurance_lanes]\nenabled=true\njustfile_path=\"justfile\"\n\n[[checks.ci_assurance_lanes.recipe_contracts]]\nrecipe=\"ci-dry-run\"\nrequired_literals=[\"just check-pr-critical\"]\nforbidden_literals=[]\n\n[[checks.ci_assurance_lanes.file_contracts]]\npath=\".github/workflows/check.yml\"\nrequired_literals=[\"run: just check-pr-critical\"]\nforbidden_literals=[\"Run fast structural verification lane\"]\n",
        )
        .expect("write config");
        fs::write(
            dir.join("justfile"),
            "ci-dry-run:\n    just check-pr-critical\n",
        )
        .expect("write justfile");
        fs::write(
            dir.join(".github/workflows/check.yml"),
            "jobs:\n  check:\n    steps:\n      - run: just check-pr-critical\n",
        )
        .expect("write workflow");
        let cfg = config::load(&dir.join("toolkit.toml")).expect("load config");
        assert!(run(&dir, &cfg).expect("run").is_empty());
        let _ = fs::remove_dir_all(&dir);
    }
}
