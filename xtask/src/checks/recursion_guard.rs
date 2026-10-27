use std::{fs, path::Path};

use anyhow::{Context, Result};
use syn::{
    spanned::Spanned, visit::Visit, Expr, ExprCall, ExprMethodCall, ImplItem,
    ImplItemFn, ItemFn, ItemImpl, Stmt, Visibility,
};

use crate::{
    config::ToolkitConfig,
    report::FlatFindingSet,
    util::{collect_rust_policy_files, normalize_rel_path},
};

pub fn run(repo_root: &Path, config: &ToolkitConfig) -> Result<FlatFindingSet> {
    let Some(check) = &config.checks.recursion_guard else {
        return Ok(FlatFindingSet::default());
    };
    if !check.enabled {
        return Ok(FlatFindingSet::default());
    }

    let mut findings = FlatFindingSet::default();
    for path in collect_rust_policy_files(
        repo_root,
        &check.include_paths,
        &check.exclude_path_parts,
    )? {
        let rel = normalize_rel_path(repo_root, &path);
        let source = fs::read_to_string(&path)
            .with_context(|| format!("reading {}", path.display()))?;
        let file = syn::parse_file(&source)
            .with_context(|| format!("parsing {}", path.display()))?;
        let mut visitor = RecursionGuardVisitor {
            rel_path: &rel,
            allow_comment_marker: &check.allow_comment_marker,
            source: &source,
            findings: &mut findings,
        };
        visitor.visit_file(&file);
    }
    Ok(findings)
}

struct RecursionGuardVisitor<'a> {
    rel_path: &'a str,
    allow_comment_marker: &'a str,
    source: &'a str,
    findings: &'a mut FlatFindingSet,
}

impl RecursionGuardVisitor<'_> {
    fn inspect_body(
        &mut self,
        vis: &Visibility,
        sig: &syn::Signature,
        block: &syn::Block,
    ) {
        if !matches!(vis, Visibility::Public(_)) {
            return;
        }

        let start = block.span().start();
        let end = block.span().end();
        if start.line == 0 || end.line == 0 {
            return;
        }

        let body_text = block_source_text(self.source, start.line, end.line);
        if body_text.contains(self.allow_comment_marker) {
            return;
        }

        let mut finder = DirectRecursionFinder {
            target_name: sig.ident.to_string(),
            found: false,
        };
        finder.visit_block(block);
        if finder.found {
            self.findings.entries.insert(format!(
                "{}:{}: direct recursion in `{}` requires an explicit exception marker",
                self.rel_path, start.line, sig.ident
            ));
        }
    }
}

impl<'ast> Visit<'ast> for RecursionGuardVisitor<'_> {
    fn visit_item_fn(&mut self, item_fn: &'ast ItemFn) {
        self.inspect_body(&item_fn.vis, &item_fn.sig, &item_fn.block);
    }

    fn visit_item_impl(&mut self, item_impl: &'ast ItemImpl) {
        for item in &item_impl.items {
            if let ImplItem::Fn(method) = item {
                self.visit_impl_item_fn(method);
            }
        }
    }

    fn visit_impl_item_fn(&mut self, method: &'ast ImplItemFn) {
        self.inspect_body(&method.vis, &method.sig, &method.block);
    }
}

struct DirectRecursionFinder {
    target_name: String,
    found: bool,
}

impl<'ast> Visit<'ast> for DirectRecursionFinder {
    fn visit_stmt(&mut self, stmt: &'ast Stmt) {
        if self.found {
            return;
        }
        syn::visit::visit_stmt(self, stmt);
    }

    fn visit_expr_call(&mut self, expr_call: &'ast ExprCall) {
        if self.found {
            return;
        }
        if call_targets_name(&expr_call.func, &self.target_name) {
            self.found = true;
            return;
        }
        syn::visit::visit_expr_call(self, expr_call);
    }

    fn visit_expr_method_call(&mut self, method_call: &'ast ExprMethodCall) {
        if self.found {
            return;
        }
        if method_call.receiver_is_self()
            && method_call.method == self.target_name.as_str()
        {
            self.found = true;
            return;
        }
        syn::visit::visit_expr_method_call(self, method_call);
    }
}

trait ReceiverIsSelf {
    fn receiver_is_self(&self) -> bool;
}

impl ReceiverIsSelf for ExprMethodCall {
    fn receiver_is_self(&self) -> bool {
        matches!(
            &*self.receiver,
            Expr::Path(path)
                if path.path.is_ident("self")
        )
    }
}

fn call_targets_name(expr: &Expr, target_name: &str) -> bool {
    let Expr::Path(expr_path) = expr else {
        return false;
    };
    if expr_path.qself.is_some() {
        return false;
    }
    let segments: Vec<_> = expr_path.path.segments.iter().collect();
    match segments.as_slice() {
        | [segment] => segment.ident == target_name,
        | [prefix, segment] => {
            segment.ident == target_name
                && matches!(prefix.ident.to_string().as_str(), "Self" | "self")
        },
        | _ => false,
    }
}

fn block_source_text(source: &str, start_line: usize, end_line: usize) -> &str {
    let mut current_offset = 0usize;
    let mut start_offset = 0usize;
    let mut end_offset = source.len();

    for (current_line, line) in (1usize..).zip(source.lines()) {
        let line_start = current_offset;
        let line_end = line_start + line.len();
        if current_line == start_line {
            start_offset = line_start;
        }
        if current_line == end_line {
            end_offset = line_end;
            break;
        }
        current_offset = line_end + 1;
    }

    &source[start_offset.min(source.len())..end_offset.min(source.len())]
}
