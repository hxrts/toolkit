#!/usr/bin/env bash
# Exercise the real wrapper with a small Toolkit-shaped project and Cargo.
set -euo pipefail
wrapper=${1:?toolkit-xtask wrapper required}
cargo_bin=${2:?selected Cargo required}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/toolkit/xtask/src"
cat > "$fixture/toolkit/xtask/Cargo.toml" <<'TOML'
[package]
name = "toolkit-target-marker-fixture"
version = "0.0.0"
edition = "2021"
TOML
printf 'fn main() {}\n' > "$fixture/toolkit/xtask/src/main.rs"
TOOLKIT_ROOT="$fixture/toolkit" XDG_CACHE_HOME="$fixture/cache" CARGO_NET_OFFLINE=true "$wrapper"
targets=("$fixture"/cache/toolkit/xtask-target/*)
[[ ${#targets[@]} == 1 && -d ${targets[0]} ]] || { echo 'toolkit xtask target: expected one target' >&2; exit 1; }
[[ -f ${targets[0]}/CACHEDIR.TAG ]] || { echo 'toolkit xtask target: missing CACHEDIR.TAG' >&2; exit 1; }
"$cargo_bin" clean --manifest-path "$fixture/toolkit/xtask/Cargo.toml" --target-dir "${targets[0]}"
echo 'toolkit xtask target: Cargo created its marker and clean succeeded'
