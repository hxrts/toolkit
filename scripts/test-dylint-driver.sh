#!/usr/bin/env bash
# Exercise actual dynamic lint loading, not just lint-library compilation.
set -euo pipefail
fixture=$(mktemp -d "${TMPDIR:-/tmp}/toolkit-dylint-consumer.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/src"
cat > "$fixture/Cargo.toml" <<'TOML'
[package]
name = "toolkit-dylint-consumer"
version = "0.0.0"
edition = "2021"
rust-version = "1.99"
[workspace]
TOML
toolkit-install-dylint
export CARGO_INCREMENTAL=0
for lint in trait_purity trait_must_use naked_map_err style_limits; do
  printf 'pub fn clean() {}\n' > "$fixture/src/lib.rs"
  toolkit-dylint --repo-root "$fixture" --toolkit-lint "$lint" --all -- --all-targets
  case "$lint" in
    trait_purity)
      printf 'pub trait MissingPurity { fn act(&self); }\n' > "$fixture/src/lib.rs"
      name=trait_purity
      cause='public trait is missing'
      ;;
    trait_must_use)
      printf 'pub trait MissingMustUse { fn value(&self) -> u8; }\n' > "$fixture/src/lib.rs"
      name=trait_method_must_use
      cause='public trait method returns a meaningful value'
      ;;
    naked_map_err)
      cat > "$fixture/src/lib.rs" <<'RUST'
pub enum RouteError { Runtime(String) }
pub fn discard(value: Result<(), std::io::Error>) -> Result<(), RouteError> {
    value.map_err(|_| RouteError::Runtime(String::from("lost")))
}
RUST
      name=naked_map_err_route_error
      cause='discards the original error'
      ;;
    style_limits)
      {
        printf 'pub fn long_body() {\n'
        for ((i=0; i<65; i++)); do printf '    let _ = 1;\n'; done
        printf '}\n'
      } > "$fixture/src/lib.rs"
      name=long_block
      cause='limit is 60'
      ;;
  esac
  status=0
  DYLINT_RUSTFLAGS="-D $name" toolkit-dylint --repo-root "$fixture" --toolkit-lint "$lint" --all -- --all-targets > "$fixture/$lint.log" 2>&1 || status=$?
  cat "$fixture/$lint.log"
  [[ "$status" == 1 ]]
  grep -Fq "$cause" "$fixture/$lint.log"
  printf 'dynamic driver: %s positive and exact-cause rejection passed\n' "$lint"
done
