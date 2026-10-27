# AGENTS.md

This repository contains reusable policy tooling for Rust and Lean repos. It is
not the place for repository-specific architecture checks.

## Mission

The toolkit owns portable enforcement machinery:

- generic Rust source-policy checks
- generic `xtask` checks
- reusable `dylint` crates
- reusable proc macros and effect-support traits
- fixture-backed validation
- shared config parsing and source discovery
- formatter, clippy, and dylint shell support
- generic Lean source-style checks over `.lean` files
- the toolkit command surface exposed from `flake.nix`

A consuming repository owns:

- `toolkit/toolkit.toml`
- domain-specific checks
- domain-specific lint crates
- repo-specific exemptions
- local `just`, CI, and hook entrypoints
- the local flake wiring that adds toolkit packages to the repo shell
- any direct `cargo run --manifest-path toolkit/xtask/Cargo.toml -- ...` usage

If a proposed rule needs to name repo-specific concepts, crate topology, or
domain language, it does not belong here.

## Rust Vs Lean Scope

Keep the split explicit:

- Rust checks belong here when they apply generically across Rust workspaces and
  can be parameterized by config.
- Lean checks belong here when they are source-style or file-structure rules
  over `.lean` files and do not encode one repository's theorem-pack language.
- Lean declaration-semantic linting that depends on one repository's proof
  architecture does not belong here.
- Repo-specific architecture rules still belong in the consuming repo's
  `toolkit/` directory, whether the repo is Rust-heavy, Lean-heavy, or mixed.

The toolkit should not blur these surfaces. Keep Rust policy docs, Lean policy
docs, config keys, and examples visibly separated so consuming repos can adopt
only the pieces they need.

## Working Rules

- Keep this repo path-independent. Do not assume it lives under
  `repo/toolkit/`; resolve paths from `CARGO_MANIFEST_DIR`, explicit arguments,
  or environment variables.
- Prefer config-driven generic behavior over hardcoded repository names,
  exemptions, or crate paths.
- Prefer expanding the toolkit command surface here over adding command-specific
  wrapper scripts in a consumer repo.
- Add new generic checks under `xtask/src/checks/`.
- Add reusable compiler-backed lints under `lints/`.
- Add reusable trait-surface proc macros under `macros/` and shared expansion
  logic under `trait_contracts/`.
- Keep effect support traits and hidden marker types in `effects/`.
- Keep reusable shell commands in `flake.nix`; do not bury them in
  consumer-specific scripts.
- Add fixture coverage under `fixtures/` and `xtask/tests/` when behavior is
  subtle or easy to regress.
- Keep docs in `docs/` and keep the root `README.md` short. The three files in
  `docs/` are:
  - `docs/toolkit_repo.md` — layout, directory roles, command ownership, and
    design constraints for contributors working inside this repo.
  - `docs/consuming_repos.md` — ownership split, recommended layout, flake
    wiring, bootstrap script, rule placement, and adoption checklist for
    repos that consume the toolkit as a flake input.
  - `docs/toolkit-shell.sh` — copyable bootstrap wrapper script that consuming
    repos place at `scripts/toolkit-shell.sh`; handles nix shell entry,
    `TOOLKIT_ROOT` wiring, and rustup shim removal.
- Do not add consuming-repo policy examples that imply this repo owns a local
  `toolkit/` directory.

## Compiler selection

Ordinary Cargo, Clippy and xtask use pinned stable Rust 1.99.1. Nightly
rustfmt and compiler-private Dylint use nightly-2026-08-21 with a dated
rustup link so other consumer toolchains cannot overwrite its identity.
Keep direct Cargo/Clippy/rustfmt dispatch and explicit formatter configuration;
Cargo-home plugins must not select a different compiler. Run `just test-stable`
and `just test-nightly` for the shared local/CI contracts. Preserve the tracked
xtask lockfile; generate a library/lint lockfile only when absent.

## Commands

Run commands from the toolkit repo root.

```bash
nix develop --command toolkit-install-dylint
nix develop --command toolkit-xtask show-config --repo-root <repo> --config <repo>/toolkit/toolkit.toml
nix develop --command toolkit-xtask check <name> --repo-root <repo> --config <repo>/toolkit/toolkit.toml
nix develop --command toolkit-xtask parity <name> --repo-root <repo> --config <repo>/toolkit/toolkit.toml
nix develop --command toolkit-fmt --config ./rustfmt.toml --all -- --check
nix develop --command toolkit-dylint --repo-root <repo> --toolkit-lint trait_purity --all -- --all-targets
nix develop --command toolkit-dylint --repo-root <repo> --lint-path <repo>/toolkit/lints/<lint> --all -- --all-targets
```

The toolkit shell commands rely on `TOOLKIT_ROOT` when they need to find the
toolkit checkout itself. The toolkit repo's own `nix develop` shell sets
`TOOLKIT_ROOT` automatically; a consuming repo should export `TOOLKIT_ROOT` to
the toolkit input path from its own `flake.nix`.

## Adding New Enforcement

Use this decision rule:

1. If the rule is generic and only its scope varies by repo, add config support.
2. If the rule semantics are reusable across repos, implement it here.
3. If the rule depends on one repo's architecture language, leave it in that
   repo's `toolkit/`.

When adding a generic rule:

1. Add the implementation.
2. Wire it into the `xtask` command surface.
3. Add or update fixture coverage.
4. Document any config keys or ownership constraints in `docs/`.

When adding or changing shell mechanics:

1. Prefer adding or extending a toolkit-owned command in `flake.nix`.
2. Keep the interface parameter-driven (`--repo-root`, `--config`, `--lint-path`)
   rather than encoding one consumer's layout.
3. Update `docs/consuming_repos.md` if the consuming-repo workflow changes.

## Editing Constraints

- Default to ASCII.
- Use succinct comments only when the code is not self-explanatory.
- Do not silently bake Jacquard-specific assumptions back into shared code.
- Do not add sibling-path, local checkout resolver, or hardcoded local path
  assumptions back into the docs or code.
- Preserve existing user changes in this repo unless explicitly asked to revert
  them.
