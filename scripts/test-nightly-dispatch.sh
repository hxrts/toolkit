#!/usr/bin/env bash
set -euo pipefail
formatter=${1:?Formatter wrapper required}
rustfmt=${2:?Pinned rustfmt required}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/toolkit-nightly-dispatch.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/home/bin" "$fixture/src"
printf '#!/bin/sh\nexit 97\n' > "$fixture/home/bin/cargo-fmt"
printf '#!/bin/sh\nexit 98\n' > "$fixture/home/bin/rustfmt"
chmod +x "$fixture/home/bin/cargo-fmt" "$fixture/home/bin/rustfmt"
export CARGO_HOME="$fixture/home"
export PATH="$fixture/home/bin:$PATH"
expected=$("$rustfmt" --version)
actual=$("$formatter" --config "$root/rustfmt.toml" --version)
[[ "$actual" == "$expected" && "$actual" == *nightly* ]]
cat > "$fixture/Cargo.toml" <<'TOML'
[package]
name = "toolkit-nightly-dispatch-probe"
version = "0.0.0"
edition = "2021"
[workspace]
TOML
printf 'max_width = 40\n' > "$fixture/custom.toml"
printf 'pub fn values()->[u8;24]{[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24]}\n' > "$fixture/src/lib.rs"
cp "$fixture/src/lib.rs" "$fixture/before.rs"
"$formatter" --config "$fixture/custom.toml" --manifest-path "$fixture/Cargo.toml"
! cmp -s "$fixture/before.rs" "$fixture/src/lib.rs"
"$rustfmt" --check --config-path "$fixture/custom.toml" "$fixture/src/lib.rs"
printf 'nightly dispatch: exact version and real formatting passed with poisoned plugins\n'
