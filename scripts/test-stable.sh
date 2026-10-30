#!/usr/bin/env bash
# Shared local/CI stable validation. Build the two Nix wrappers first.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/test-selected-cargo-dispatch.sh"
"$root/scripts/test-selected-cargo-cache-key.sh"
cargo_wrapper=${1:?Cargo wrapper required}
clippy_wrapper=${2:?Clippy wrapper required}
"$root/scripts/test-stable-dispatch.sh" "$cargo_wrapper" "$clippy_wrapper"
for member in effects trait_contracts macros xtask; do
  "$cargo_wrapper" test --locked --manifest-path "$root/$member/Cargo.toml" --target-dir "$root/xtask/target"
  "$clippy_wrapper" --locked --manifest-path "$root/$member/Cargo.toml" --target-dir "$root/xtask/target" --all-targets -- -D warnings
done
