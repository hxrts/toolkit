#![feature(rustc_private)]
#![deny(unsafe_code)]

extern crate rustc_errors;
extern crate rustc_hir;
extern crate rustc_lint;
extern crate rustc_session;
extern crate rustc_span;

mod long_block;
mod long_file;
mod source_scan;

dylint_linting::dylint_library!();

use rustc_lint::LintStore;
use rustc_session::Session;

#[allow(unsafe_code)]
#[expect(clippy::no_mangle_with_rust_abi)]
#[unsafe(no_mangle)]
pub fn register_lints(sess: &Session, lint_store: &mut LintStore) {
    dylint_linting::init_config(sess);
    lint_store.register_lints(&[long_block::LONG_BLOCK, long_file::LONG_FILE]);
    lint_store.register_late_lint_pass(Box::new(|_| Box::new(long_block::LongBlock)));
    lint_store.register_late_lint_pass(Box::new(|_| {
        Box::new(long_file::LongFile::default())
    }));
}
