# Repository Layout

This repository should stay focused on portable enforcement machinery.

## Language Split

The toolkit serves two generic policy surfaces:

- Rust enforcement:
  source-policy checks, `dylint` crates, proc macros, trait-contract support,
  formatter/clippy/dylint shell commands.
- Lean enforcement:
  source-style checks over `.lean` files, along with the shared config parsing
  and shell support needed to run them in consuming repos.

Keep those surfaces separated in docs and config examples. A consuming repo may
adopt one or both. The toolkit should not assume every consumer is a mixed
Rust-and-Lean repo.

## Top-Level Layout

```text
toolkit/
  README.md
  AGENTS.md
  rustfmt.toml
  clippy.toml
  effects/
  trait_contracts/
  macros/
  xtask/
  lints/
    .cargo/
  fixtures/
  docs/
  flake.nix
  flake.lock
  config/
```

## Directory Roles

- `effects/`
  Generic support traits and hidden marker types for effect vocabularies and
  handlers.
- `trait_contracts/`
  Shared expansion logic for portable trait-surface proc macros.
- `macros/`
  Public proc-macro crate for portable purity and effect-boundary annotations.
- `xtask/`
  Generic runner, config loading, source discovery, reusable Rust checks, and
  reusable Lean source-style checks.
- `lints/`
  Portable `dylint` crates and shared dylint support files. The shared
  `lints/.cargo/config.toml` wires `toolkit-dylint-link` for non-Windows
  targets.
- `fixtures/`
  Reusable fixture repositories and expected results for validation, including
  miniature pass/fail repo fixtures for config-driven checks.
- `docs/`
  Consumer workflow, ownership rules, contributor guidance, and copyable
  bootstrap snippets such as `docs/toolkit-shell.sh`.
- `flake.nix`
  Pinned stable Cargo/Clippy and separate nightly rustfmt/Dylint tooling:
  `toolkit-xtask`, `toolkit-fmt`, `toolkit-install-dylint`,
  `toolkit-clippy`, `toolkit-dylint`, and `toolkit-dylint-link`.
- `flake.lock`
  Pinned toolkit flake dependencies.
- `config/`
  Notes about shared config schema, defaults, and migration shape.

## Command Ownership

The toolkit repo owns the reusable commands exposed from `flake.nix`:

- `toolkit-xtask`
- `toolkit-fmt`
- `toolkit-clippy`
- `toolkit-install-dylint`
- `toolkit-dylint`
- `toolkit-dylint-link`

When invoking those commands from the toolkit repo itself, use `nix develop`
from the repo root. The dev shell exports `TOOLKIT_ROOT` automatically so the
commands can find the checkout they are supposed to operate on.

The consuming repo should not reimplement those mechanics unless it is fixing a
toolkit bug temporarily on the way to moving that fix back here.
The only expected repo-local wrapper is a tiny bootstrap such as the copyable
`docs/toolkit-shell.sh` snippet documented in `docs/consuming_repos.md`.

## Ownership Rules

This repo owns:

- generic Rust check semantics
- generic Lean source-style check semantics
- generic lint semantics
- shared tooling shells
- shared shell commands
- shared fixture harnesses
- reusable proc macros and effect-support traits

This repo does not own:

- Jacquard-specific policy
- another repo's exemptions
- another repo's architecture boundaries
- hardcoded crate names or repo paths that only make sense for one consumer

## Design Constraints

- Prefer config-driven scope over hardcoded exceptions.
- Keep the toolkit path-independent.
- Do not assume the checkout lives at `repo/toolkit`.
- Assume the toolkit is consumed through a flake input plus `TOOLKIT_ROOT`, not
  through sibling-path dependencies or ad hoc checkout resolvers.
- Keep `README.md` short and move substantial guidance into `docs/`.
- Add tests or fixtures when introducing non-trivial enforcement behavior.

## Compiler identities

Ordinary Cargo, Clippy and xtask use exact Rust 1.99.1. The default Nix shell
and rustup toolchain agree. Compiler-private Dylint and nightly rustfmt retain
nightly-2026-08-21; they are not interchangeable with the stable compiler.
The flake exports toolkit-rust-stable and toolkit-rust-nightly for explicit
identity inspection and guarded toolchain realization. Consumers retain their
own scoped compiler dispatch and validate integration before updating pins.

Private compiler or Dylint changes also require `just test-dylint-driver`.
This maintained CI check installs the pinned driver, dynamically loads each of
Toolkit's four lint libraries and executes Rust 1.99-minimum consumer fixtures.
Each library must accept its clean control and reject its actual violation with
native driver status1 and the expected diagnostic. Compilation-only success does not
establish this driver/consumer contract; repository-specific gates remain required.
