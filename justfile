default:
    @just --list

# Check xtask compiles
check:
    nix develop --command cargo check --manifest-path xtask/Cargo.toml

# Run xtask tests
test:
    nix develop --command cargo test --manifest-path xtask/Cargo.toml

# Format xtask source (nightly rustfmt)
fmt:
    nix develop --command toolkit-fmt --config ./rustfmt.toml --manifest-path xtask/Cargo.toml --all

# Check xtask formatting
fmt-check:
    nix develop --command toolkit-fmt --config ./rustfmt.toml --manifest-path xtask/Cargo.toml --all -- --check

# Run clippy over xtask
lint:
    nix develop --command toolkit-clippy --manifest-path xtask/Cargo.toml --all-targets -- -D warnings

# Enter the toolkit nix dev shell
shell:
    nix develop

# Publish toolkit crates to crates.io and cut a release.
# Usage:
#   just release <version> [dry_run] [no_tag] [push] [allow_dirty] [no_require_main]
# Example:
#   just release 0.1.2 true true false true false   # dry-run, no-tag, allow-dirty
release \
  version="" \
  dry_run="false" \
  no_tag="false" \
  push="false" \
  allow_dirty="false" \
  no_require_main="false":
    #!/usr/bin/env bash
    set -euo pipefail
    args=()
    if [ -n "{{version}}" ]; then
      args+=(--version "{{version}}")
    fi
    if [ "{{dry_run}}" = "true" ]; then
      args+=(--dry-run)
    fi
    if [ "{{no_tag}}" = "true" ]; then
      args+=(--no-tag)
    fi
    if [ "{{push}}" = "true" ]; then
      args+=(--push)
    fi
    if [ "{{allow_dirty}}" = "true" ]; then
      args+=(--allow-dirty)
    fi
    if [ "{{no_require_main}}" = "true" ]; then
      args+=(--no-require-main)
    fi
    ./scripts/release-publish.sh "${args[@]}"

# Real stable compiler/Clippy dispatch and original-error contract.
test-stable-dispatch:
    nix develop --command bash -c 'scripts/test-stable-dispatch.sh "$(command -v cargo)" "$(command -v toolkit-clippy)"'

# Same stable contract used by hosted CI; existing lockfiles remain selected.
test-stable:
    nix develop --command bash -c 'scripts/test-stable.sh "$(command -v cargo)" "$(command -v toolkit-clippy)"'

# Pinned nightly formatter dispatch and compiler-private compilation contract.
test-nightly:
    #!/usr/bin/env bash
    set -euo pipefail
    outputs=$(nix build .#toolkit-fmt .#toolkit-rust-nightly --no-link --json)
    fmt_path=$(printf '%s' "$outputs" | jq -er '.[0].outputs.out')
    nightly_path=$(printf '%s' "$outputs" | jq -er '.[1].outputs.out')
    scripts/test-nightly.sh "$fmt_path/bin/toolkit-fmt" "$nightly_path"
