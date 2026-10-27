# Consuming The Toolkit

Repositories that adopt the toolkit should keep their own entrypoints and
repository-specific policy, but consume the toolkit through a flake input.

This guide assumes the consuming repo:

- exposes toolkit commands from its default `nix develop` shell
- sets `TOOLKIT_ROOT` to the toolkit flake input path in `shellHook`
- keeps a tiny repo-local `scripts/toolkit-shell.sh` bootstrap for `just`, CI,
  and hooks

## Ownership Split

- toolkit repo:
  generic Rust checks, generic Lean source-style checks, reusable lints,
  fixture harnesses, config parsing, proc macros / effect support, and tooling
  shells
- consuming repo:
  local `justfile`, CI wiring, hooks, and a repo-owned `toolkit/` directory

## Rust Vs Lean Adoption

Keep the split explicit in consuming repos:

- Rust-only repos may adopt the Rust command surface and Rust checks without any
  Lean configuration.
- Lean-heavy repos may adopt the Lean style checks without using toolkit-owned
  Rust lints.
- Mixed repos can use both, but should keep Rust policy config and Lean policy
  config visibly separated in `toolkit/toolkit.toml`.

## Recommended Layout

```text
repo/
  flake.nix
  flake.lock
  justfile
  .githooks/
  .github/
  toolkit/
    README.md
    toolkit.toml
    checks/
    lints/
    fixtures/
    docs/
```

The consuming repository keeps ownership of:

- `justfile`
- CI workflow commands
- pre-commit hooks
- the repo `flake.nix` and `flake.lock`
- small local bootstrap scripts such as `scripts/toolkit-shell.sh`
- `toolkit/`

Those entrypoints call into the toolkit commands exposed from the repo's own
default dev shell and pass the local config, usually
`--config toolkit/toolkit.toml`.

## Developer Workflow

1. Add the toolkit as a flake input and pin it in `flake.lock`.
2. Keep repo entrypoints local.
3. Add `toolkit/toolkit.toml`.
4. Add repo-local `toolkit/checks/`, `toolkit/lints/`, `toolkit/fixtures/`, and
   toolkit docs only as needed.
5. Import toolkit consumer shell support into the repo shell.
6. Add the toolkit command packages from that support surface.
7. Add a tiny `scripts/toolkit-shell.sh` bootstrap.
8. Run toolkit commands from `just`, CI, and hooks through that bootstrap.
9. Add domain-specific rules only under `toolkit/`.

## Toolkit Command Surface

Inside the toolkit Nix shell, the reusable command surface is:

- `toolkit-xtask`
  Runs the generic toolkit runner from the pinned toolkit checkout.
- `toolkit-fmt`
  Runs nightly `cargo fmt`, using either `--config <rustfmt.toml>` or the
  toolkit repo's own `rustfmt.toml`.
- `toolkit-clippy`
  Runs Clippy directly with the toolkit-pinned stable toolchain (Rust 1.99.1).
  Direct dispatch avoids Cargo-home plugins selecting a different compiler.
- `toolkit-xtask check lean-style`
  Runs the generic Lean source-style checker over repo-owned `.lean` trees
  using thresholds and exemptions from `toolkit/toolkit.toml`.
- `toolkit-xtask check lean_escape_hatches`
  Runs the generic Lean escape-hatch scanner over repo-owned `.lean` trees
  using per-kind thresholds and file exemptions from `toolkit/toolkit.toml`.
- `toolkit-xtask check workflow_actions`
  Validates remote GitHub Action references in repo-owned workflow YAML files
  and supports inline `pin` comment exemptions for intentionally pinned refs.
- `toolkit-xtask check docs_index`
  Validates a repo-owned markdown index table against the actual docs files and
  their H1 titles.
- `toolkit-xtask check formal_claim_scope`
  Enforces repo-owned required and forbidden documentation claim text.
- `toolkit-xtask check durable_boundaries`
  Enforces repo-owned durability boundary content and forbidden leakage patterns.
- `toolkit-xtask check search_boundaries`
  Enforces repo-owned generic search crate boundary content and forbidden leakage patterns.
- `toolkit-xtask check viewer_tooling_boundaries`
  Enforces repo-owned viewer/webapp boundary docs and forbidden leakage patterns.
- `toolkit-xtask check parity_ledger`
  Validates repo-owned parity ledger headings and required table structure.
- `toolkit-xtask check ci_assurance_lanes`
  Validates repo-owned justfile and workflow lane contracts for canonical CI entrypoints.
- `toolkit-xtask check git_dependency_pins`
  Validates repo-owned JSON git revision ledgers against checked-out dependency repos.
- `toolkit-xtask check protocol_machine_placeholders`
  Enforces forbidden placeholder and proof-import patterns over repo-owned protocol-machine implementation trees.
- `toolkit-install-dylint`
  Installs `cargo-dylint` and `dylint-link`, then links the pinned nightly
  toolchain name used by toolkit lint runs.
- `toolkit-dylint`
  Runs either a toolkit-owned lint (`--toolkit-lint <name>`) or a
  consumer-owned lint (`--lint-path <path>`) with the toolkit nightly setup.

Toolkit commands assume the consuming repo has imported the toolkit consumer
shell support into its own shell.

## Recommended Flake Wiring

The consuming repo should usually wire the toolkit in its own `flake.nix`:

```nix
inputs = {
  toolkit = {
    url = "github:hxrts/toolkit";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.rust-overlay.follows = "rust-overlay";
    inputs.flake-utils.follows = "flake-utils";
  };
};
```

and then import the consumer shell support:

```nix
let
  toolkitSupport = toolkit.lib.${system}.consumerShellSupport;
in
pkgs.mkShell {
  nativeBuildInputs = [
    rustToolchain
    pkg-config
    just
    perl
    ripgrep
  ] ++ toolkitSupport.packages;

  buildInputs = [
    openssl
  ] ++ toolkitSupport.buildInputs;

  shellHook = ''
    ${toolkitSupport.shellHook}
  '';
}
```

That keeps toolkit versioning repo-owned through the repo's flake lock while
making the toolkit command surface directly usable from `just`, CI, and hooks
without copying toolkit-owned runtime library setup into each consumer.

A minimal toolkit-owned shell surface includes:

```nix
toolkit.lib.${system}.consumerShellSupport.packages
toolkit.lib.${system}.consumerShellSupport.buildInputs
toolkit.lib.${system}.consumerShellSupport.shellHook
```

The consumer should still add its own repo-specific toolchain and build inputs.

The shell hook exported by the support surface sets:

```nix
shellHook = ''
  ${toolkitSupport.shellHook}
'';
```

## Copyable Bootstrap Script

Most consuming repos should keep one tiny wrapper at
`scripts/toolkit-shell.sh`. A canonical version lives in
[`docs/toolkit-shell.sh`](./toolkit-shell.sh) and can be copied directly.

Recommended content:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

sanitize_path() {
  perl -e '
    my $path = $ENV{PATH} // q();
    my $home = $ENV{HOME} // q();
    my $cargo_home = $ENV{CARGO_HOME} // ($home eq q() ? q() : "$home/.cargo");
    my @drop = grep { $_ ne q() } (
      $home eq q() ? q() : "$home/.cargo/bin",
      $cargo_home eq q() ? q() : "$cargo_home/bin",
    );
    my %drop = map { $_ => 1 } @drop;
    my @parts = grep { $_ ne q() && !$drop{$_} } split(/:/, $path, -1);
    print join(":", @parts);
  '
}

ensure_writable_toolkit_root() {
  local toolkit_root="${TOOLKIT_ROOT:-}"
  local cache_root cache_key writable_root
  if [ -z "$toolkit_root" ] || [ -w "$toolkit_root/xtask/Cargo.lock" ]; then
    printf '%s' "$toolkit_root"
    return
  fi

  cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/toolkit/consumer-roots"
  cache_key="$(basename "$toolkit_root" | tr -cs 'A-Za-z0-9._-' '_')"
  writable_root="$cache_root/$cache_key"
  if [ ! -d "$writable_root" ]; then
    mkdir -p "$cache_root"
    cp -R "$toolkit_root" "$writable_root"
    chmod -R u+w "$writable_root"
  fi
  printf '%s' "$writable_root"
}

run_sanitized() {
  local sanitized_path
  sanitized_path="$(sanitize_path)"
  env \
    -u CARGO \
    -u RUSTC \
    -u RUSTDOC \
    -u RUSTUP_TOOLCHAIN \
    PATH="$sanitized_path" \
    "$@"
}

if [ "${1:-}" = "--inside-nix" ]; then
  shift
  if [ -z "${IN_NIX_SHELL:-}" ] || [ -z "${TOOLKIT_ROOT:-}" ] || ! command -v toolkit-xtask >/dev/null 2>&1; then
    echo "toolkit-shell.sh: --inside-nix requires the toolkit nix shell" >&2
    exit 1
  fi
  export TOOLKIT_ROOT
  TOOLKIT_ROOT="$(ensure_writable_toolkit_root)"
  run_sanitized "$@"
  exit $?
fi

if [ "${TOOLKIT_CONSUMER_SHELL_ACTIVE:-}" = "1" ] \
  && [ -n "${IN_NIX_SHELL:-}" ] \
  && [ -n "${TOOLKIT_ROOT:-}" ] \
  && command -v toolkit-xtask >/dev/null 2>&1; then
  export TOOLKIT_ROOT
  TOOLKIT_ROOT="$(ensure_writable_toolkit_root)"
  run_sanitized "$@"
  exit $?
fi

sanitized_path="$(sanitize_path)"
env \
  -u CARGO \
  -u RUSTC \
  -u RUSTDOC \
  -u RUSTUP_TOOLCHAIN \
  -u TOOLKIT_ROOT \
  -u IN_NIX_SHELL \
  PATH="$sanitized_path" \
  TOOLKIT_CONSUMER_SHELL_ACTIVE=1 \
  nix develop --command \
  "$repo_root/scripts/toolkit-shell.sh" --inside-nix "$@"
```

This wrapper does two things:

- if the caller is already inside the consuming repo's flake shell, it runs the
  toolkit command directly with rustup shims removed from `PATH`
- otherwise, it enters the consuming repo's pinned shell without trusting any
  stale ambient `TOOLKIT_ROOT` or `IN_NIX_SHELL` values

If the pinned toolkit root lives in the read-only Nix store, the wrapper also
copies that exact revision into a writable cache before running `toolkit-xtask`.
That avoids `cargo run` lockfile writes against an immutable store path.

That shell-entry path keeps CI, `just`, hooks, and local command runs inside
the same repo-owned shell wiring that already includes toolkit consumer
support.

After copying it into `scripts/toolkit-shell.sh`, make it executable:

```bash
chmod +x scripts/toolkit-shell.sh
```

## Rule Placement

- if a rule is generic and only the scope is repo-specific, configure it in
  `toolkit/toolkit.toml`
- if a rule is a generic Rust source-policy rule, keep it in toolkit
- if a rule is a generic Lean source-style rule, keep it in toolkit
- if a rule depends on repo-specific architecture concepts, keep it under
  `toolkit/`
- if a repo-local rule later proves reusable, move it into the toolkit and
  delete the local copy

## Practical Command Shape

The consuming repo should usually call toolkit commands through that local
bootstrap:

```bash
./scripts/toolkit-shell.sh toolkit-xtask check <name> --repo-root . --config toolkit/toolkit.toml
./scripts/toolkit-shell.sh toolkit-xtask check docs_index --repo-root . --config toolkit/toolkit.toml
./scripts/toolkit-shell.sh toolkit-xtask check lean-style --repo-root . --config toolkit/toolkit.toml
./scripts/toolkit-shell.sh toolkit-xtask check lean_escape_hatches --repo-root . --config toolkit/toolkit.toml
./scripts/toolkit-shell.sh toolkit-xtask check workflow_actions --repo-root . --config toolkit/toolkit.toml
./scripts/toolkit-shell.sh toolkit-clippy --workspace --all-targets -- -D warnings
./scripts/toolkit-shell.sh toolkit-install-dylint
./scripts/toolkit-shell.sh toolkit-dylint --repo-root . --toolkit-lint trait_purity --all -- --all-targets
./scripts/toolkit-shell.sh toolkit-dylint --repo-root . --lint-path ./toolkit/lints/model_policy --all -- --all-targets
./scripts/toolkit-shell.sh toolkit-fmt --all -- --check
```

Repo-specific policy commands remain repo-owned. For example, a consuming repo
can still run its own policy runner directly:

```bash
cargo run --manifest-path toolkit/xtask/Cargo.toml -- check <name>
```

For Lean-heavy repos, the recommended local flow is usually:

```bash
./scripts/toolkit-shell.sh toolkit-xtask check lean-style --repo-root . --config toolkit/toolkit.toml
cd verification && lake build
```

Most consumers should wrap those two commands in a repo-local `just lean-check`
entrypoint rather than trying to intercept raw `lake build`.

## Minimal Adoption Checklist

1. Add `toolkit` as a flake input.
2. Import `toolkit.lib.${system}.consumerShellSupport` into the repo shell.
3. Expose toolkit packages from that support surface.
4. Copy [`docs/toolkit-shell.sh`](./toolkit-shell.sh) to
   `scripts/toolkit-shell.sh`.
5. `chmod +x scripts/toolkit-shell.sh`.
6. Add `toolkit/toolkit.toml`.
7. Point `just`, CI, and hooks at `./scripts/toolkit-shell.sh toolkit-...`.

## Dependency Scanning with `cargo deny`

Consuming repos should run `cargo deny check` in CI to enforce license and
advisory vulnerability scanning. The toolkit's `ci_assurance_lanes` check can
verify the recipe exists and invokes the right commands.

### Setup

1. Install `cargo-deny` (it is available in nixpkgs as `cargo-deny`; add it to
   your dev shell's `nativeBuildInputs`).
2. Create a `deny.toml` at the repo root. See
   [cargo-deny documentation](https://embarkstudios.github.io/cargo-deny/) for
   configuration options.
3. Add a `deny` recipe to the consuming repo's `justfile`:

```just
deny:
    cargo deny check advisories licenses
```

4. Wire a `ci_assurance_lanes` contract in `toolkit/toolkit.toml`:

```toml
[checks.ci_assurance_lanes]
enabled = true
justfile_path = "justfile"

[[checks.ci_assurance_lanes.recipe_contracts]]
recipe = "deny"
required_literals = ["cargo deny check"]
```

This ensures the `deny` recipe is present and invokes `cargo deny check`. The
specific `deny.toml` configuration (allowed licenses, advisory thresholds) is
the consuming repo's responsibility.

## Repo-Local Dylint Requirements

If the consuming repo adds its own `toolkit/lints/*` crates, those lint crates
still need the normal Dylint linker setup. The recommended shape is:

```text
toolkit/
  lints/
    .cargo/
      config.toml
```

with:

```toml
[target.'cfg(not(target_os = "windows"))']
linker = "toolkit-dylint-link"
```

That linker wrapper is provided by the toolkit Nix shell and is required so
`cargo dylint` produces the `@toolchain` library filename that Dylint expects.
