use std::path::Path;

use anyhow::Result;
use regex::Regex;

use crate::{
    config::ToolkitConfig,
    report::FlatFindingSet,
    util::{collect_rust_policy_files, scan_with_marker},
};

pub fn run(repo_root: &Path, config: &ToolkitConfig) -> Result<FlatFindingSet> {
    let Some(check) = &config.checks.cloning_boundary else {
        return Ok(FlatFindingSet::default());
    };
    if !check.enabled || check.banned_derives.is_empty() {
        return Ok(FlatFindingSet::default());
    }
    // Build a pattern that matches any banned derive inside a derive(...)
    // attribute.
    let alts = check
        .banned_derives
        .iter()
        .map(|d| regex::escape(d))
        .collect::<Vec<_>>()
        .join("|");
    let derive_re = Regex::new(&format!(r"#\[derive\([^\]]*\b(?:{alts})\b"))?;
    let files = collect_rust_policy_files(
        repo_root,
        &check.include_paths,
        &check.exclude_path_parts,
    )?;
    let marker = &check.allow_comment_marker;
    scan_with_marker(
        files,
        repo_root,
        &derive_re,
        marker,
        3,
        |rel, line_no, _| {
            format!(
            "{rel}:{line_no}: `#[derive(...)]` with a cloning trait requires a preceding \
             `{marker}` rationale comment"
        )
        },
    )
}
