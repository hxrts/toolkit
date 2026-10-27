#!/usr/bin/env bash
# Real compiler contract; arguments are built Nix Cargo and Clippy wrappers.
set -euo pipefail
cargo_wrapper=${1:?Cargo wrapper path required}
clippy_wrapper=${2:?Clippy wrapper path required}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/toolkit-dispatch.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/home/bin" "$fixture/bin" "$fixture/src"
cat > "$fixture/Cargo.toml" <<'TOML'
[package]
name = "toolkit-stable-dispatch-probe"
version = "0.0.0"
edition = "2021"
[workspace]
TOML
cat > "$fixture/src/lib.rs" <<'RS'
pub fn identity(value: u32) -> u32 { value }
#[test]
fn preserves_value() { assert_eq!(identity(7), 7); }
RS
# Poison both plugin lookup and ambient rustc: scoped dispatch must win.
printf '#!/bin/sh\nexit 97\n' > "$fixture/home/bin/cargo-clippy"
printf '#!/bin/sh\nexit 98\n' > "$fixture/bin/rustc"
chmod +x "$fixture/home/bin/cargo-clippy" "$fixture/bin/rustc"
export CARGO_HOME="$fixture/home"
export PATH="$fixture/bin:$fixture/home/bin:$PATH"
export CARGO_INCREMENTAL=0
unset RUSTC_WRAPPER RUSTC_WORKSPACE_WRAPPER
"$cargo_wrapper" --version | grep -E '^cargo 1\.99\.1 '
"$cargo_wrapper" clippy --version | grep -E '^clippy 0\.1\.99 '
"$cargo_wrapper" test --manifest-path "$fixture/Cargo.toml" --offline
"$clippy_wrapper" --manifest-path "$fixture/Cargo.toml" --offline --all-targets -- -D warnings
printf 'compile_error!("toolkit-original-compiler-error");\n' > "$fixture/src/lib.rs"
set +e
"$cargo_wrapper" check --manifest-path "$fixture/Cargo.toml" --offline > "$fixture/error.log" 2>&1
status=$?
set -e
[[ $status == 101 ]] || { cat "$fixture/error.log"; exit 1; }
grep -F 'toolkit-original-compiler-error' "$fixture/error.log"
printf 'stable dispatch: real compilation, Clippy, doctests and original exit 101 passed\n'
