use std::collections::BTreeSet;

use rustc_errors::DiagDecorator;
use rustc_hir::Item;
use rustc_lint::{LateContext, LateLintPass, LintContext};

use crate::source_scan::source_file_contents;

pub const MAX_LONG_FILE_LINES: usize = 1000;
const EXCEPTION_SCAN_LINES: usize = 20;

rustc_session::declare_lint! {
    pub LONG_FILE,
    Deny,
    "source files must stay within 1000 lines and should be split into coherent smaller files",
}

pub(crate) struct LongFile {
    seen_files: BTreeSet<String>,
}

rustc_session::impl_lint_pass!(LongFile => [LONG_FILE]);

impl Default for LongFile {
    fn default() -> Self {
        Self { seen_files: BTreeSet::new() }
    }
}

impl<'tcx> LateLintPass<'tcx> for LongFile {
    fn check_item(&mut self, cx: &LateContext<'tcx>, item: &'tcx Item<'tcx>) {
        if item.span.from_expansion() {
            return;
        }

        let source_map = cx.sess().source_map();
        let Some((path, contents)) = source_file_contents(source_map, item) else {
            return;
        };
        let rel = path.to_string_lossy().replace('\\', "/");
        if !self.seen_files.insert(rel) {
            return;
        }

        let line_count = contents.lines().count();
        if line_count <= MAX_LONG_FILE_LINES {
            return;
        }

        if has_long_file_exception(&contents) {
            return;
        }

        let message = format!(
            "source file is {line_count} lines; limit is {MAX_LONG_FILE_LINES}. \
             Split the file into two or more coherent files that separate concerns. \
             Only as a last resort, when the file is genuinely one cohesive unit that splitting would obscure, \
             add a `// long-file-exception: <reason>` marker within the first {EXCEPTION_SCAN_LINES} lines."
        );
        cx.emit_span_lint(
            LONG_FILE,
            item.span,
            DiagDecorator(|diag| {
                diag.primary_message(message.clone());
            }),
        );
    }
}

fn has_long_file_exception(contents: &str) -> bool {
    for line in contents.lines().take(EXCEPTION_SCAN_LINES) {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("// long-file-exception:") {
            return !rest.trim().is_empty();
        }
    }
    false
}
