#!/usr/bin/env bash
# Compiler-private checks stay on their own pinned nightly.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
formatter=${1:?Formatter wrapper required}
nightly=${2:?Nightly toolchain path required}
"$nightly/bin/rustc" -Vv
"$root/scripts/test-nightly-dispatch.sh" "$formatter" "$nightly/bin/rustfmt"
for member in effects trait_contracts macros xtask lints; do
  "$formatter" --config "$root/rustfmt.toml" --manifest-path "$root/$member/Cargo.toml" --all -- --check
done
export RUSTC="$nightly/bin/rustc"
export RUSTDOC="$nightly/bin/rustdoc"
export CARGO_INCREMENTAL=0
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-Dwarnings"
export PATH="$nightly/bin:$PATH"
unset RUSTC_BOOTSTRAP RUSTC_WRAPPER RUSTC_WORKSPACE_WRAPPER
if [[ ! -f "$root/lints/Cargo.lock" ]]; then
  "$nightly/bin/cargo" generate-lockfile --manifest-path "$root/lints/Cargo.toml"
fi
"$nightly/bin/cargo" check --locked --manifest-path "$root/lints/Cargo.toml" --workspace --all-targets --target-dir "$root/xtask/target/nightly"
