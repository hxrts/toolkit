use rustc_errors::DiagDecorator;
use rustc_hir::{intravisit::FnKind, Body, FnDecl};
use rustc_lint::{LateContext, LateLintPass, LintContext};
use rustc_span::{def_id::LocalDefId, source_map::SourceMap, Span};

use crate::source_scan::source_file_path_for_span;

pub const MAX_LONG_BLOCK_LINES: usize = 60;

rustc_session::declare_lint! {
    pub LONG_BLOCK,
    Deny,
    "function bodies must stay within 60 source lines",
}

pub(crate) struct LongBlock;

rustc_session::impl_lint_pass!(LongBlock => [LONG_BLOCK]);

impl<'tcx> LateLintPass<'tcx> for LongBlock {
    fn check_fn(
        &mut self,
        cx: &LateContext<'tcx>,
        _kind: FnKind<'tcx>,
        _decl: &'tcx FnDecl<'tcx>,
        body: &'tcx Body<'tcx>,
        fn_span: Span,
        _id: LocalDefId,
    ) {
        if fn_span.from_expansion() || body.value.span.from_expansion() {
            return;
        }

        let source_map = cx.sess().source_map();
        let body_span = body.value.span;
        let lo = source_map.lookup_char_pos(body_span.lo());
        let hi = source_map.lookup_char_pos(body_span.hi());
        let line_count = hi.line.saturating_sub(lo.line).saturating_add(1);
        if line_count <= MAX_LONG_BLOCK_LINES {
            return;
        }

        if has_long_block_exception(source_map, fn_span) {
            return;
        }

        let message = format!(
            "function body is {line_count} lines; limit is {MAX_LONG_BLOCK_LINES}. \
             Split the function or add a `// long-block-exception: <reason>` marker above the signature."
        );
        cx.emit_span_lint(
            LONG_BLOCK,
            fn_span,
            DiagDecorator(|diag| {
                diag.primary_message(message.clone());
            }),
        );
    }
}

fn has_long_block_exception(source_map: &SourceMap, fn_span: Span) -> bool {
    let path = source_file_path_for_span(source_map, fn_span);
    let Ok(contents) = std::fs::read_to_string(&path) else {
        return false;
    };
    let fn_line_index = source_map
        .lookup_char_pos(fn_span.lo())
        .line
        .saturating_sub(1);
    if fn_line_index == 0 {
        return false;
    }
    let lines: Vec<&str> = contents.lines().collect();
    let upper = fn_line_index.min(lines.len());

    let mut block: Vec<&str> = Vec::new();
    let mut in_block = false;
    for line in lines[..upper].iter().rev() {
        let trimmed = line.trim();
        let is_regular_line_comment = trimmed.starts_with("//")
            && !trimmed.starts_with("///")
            && !trimmed.starts_with("//!");

        if is_regular_line_comment {
            block.push(trimmed);
            in_block = true;
            continue;
        }

        if in_block {
            break;
        }

        if trimmed.is_empty()
            || trimmed.starts_with("///")
            || trimmed.starts_with("//!")
            || trimmed.starts_with("#[")
            || trimmed.starts_with("#![")
        {
            continue;
        }
        return false;
    }

    if block.is_empty() {
        return false;
    }

    block.reverse();
    let joined: String = block
        .iter()
        .map(|line| line.trim_start_matches("//").trim())
        .collect::<Vec<_>>()
        .join(" ");

    if let Some(rest) = joined.strip_prefix("long-block-exception:") {
        return !rest.trim().is_empty();
    }
    false
}
