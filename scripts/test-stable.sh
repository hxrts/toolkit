#!/usr/bin/env bash
# Shared local/CI stable validation. Build the two Nix wrappers first.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/test-selected-cargo-dispatch.sh"
"$root/scripts/test-selected-cargo-cache-key.sh"
bash "$root/scripts/test-selected-cargo-remap.sh"
[[ $(nix eval --raw --file "$root/nix/tests/cargo-dependency-cache-key.nix") == ok ]]
cargo_wrapper=${1:?Cargo wrapper required}
clippy_wrapper=${2:?Clippy wrapper required}
remap_wrapper=$(nix build --no-link --print-out-paths "$root#toolkit-cargo-remap")
bash "$root/scripts/test-selected-cargo-remap.sh" "$remap_wrapper/bin/toolkit-cargo-remap"
xtask_wrapper=$(nix build --no-link --print-out-paths "$root#toolkit-xtask")
bash "$root/scripts/test-xtask-target-marker.sh" "$xtask_wrapper/bin/toolkit-xtask" "$cargo_wrapper"
"$root/scripts/test-stable-dispatch.sh" "$cargo_wrapper" "$clippy_wrapper"
for member in effects trait_contracts macros xtask; do
  "$cargo_wrapper" test --locked --manifest-path "$root/$member/Cargo.toml" --target-dir "$root/xtask/target"
  "$clippy_wrapper" --locked --manifest-path "$root/$member/Cargo.toml" --target-dir "$root/xtask/target" --all-targets -- -D warnings
done
