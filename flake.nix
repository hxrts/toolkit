{
  description = "Reusable Rust policy tooling and command surface";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Match Aura's compiler derivation without upgrading unrelated packages.
    rust-nixpkgs.url = "github:NixOS/nixpkgs/5e2a59a5b1a82f89f2c7e598302a9cacebb72a67";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      rust-nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        toolkitRuntimeLibPath = pkgs.lib.makeLibraryPath (
          [ pkgs.openssl pkgs.zlib ]
          ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.libssh2 pkgs.dbus ]
        );
        compilerPkgs = import rust-nixpkgs {
          inherit system overlays;
        };
        rustToolchainStable = compilerPkgs.rust-bin.stable."1.99.1".default.override {
          extensions = [
            "rust-src"
            "rust-analyzer"
            "clippy"
          ];
          targets = [ "wasm32-unknown-unknown" ];
        };
        nightlyDate = "2026-08-21";
        rustToolchainNightly = pkgs.rust-bin.nightly.${nightlyDate}.default.override {
          extensions = [
            "rust-src"
            "rust-analyzer"
            "rustc-dev"
            "llvm-tools-preview"
            "rustfmt"
          ];
        };

        # Stable Cargo/Clippy are the ordinary repository compiler. Nightly is
        # reserved for rustfmt and compiler-private Dylint integration.
        cargoWrapper = pkgs.writeShellScriptBin "cargo" ''
          set -euo pipefail
          export RUSTC="${rustToolchainStable}/bin/rustc"
          export RUSTDOC="${rustToolchainStable}/bin/rustdoc"
          export CARGO="${rustToolchainStable}/bin/cargo"
          if [ "''${1:-}" = clippy ]; then
            exec ${rustToolchainStable}/bin/cargo-clippy "$@"
          fi
          exec ${rustToolchainStable}/bin/cargo "$@"
        '';

        toolkitXtask = pkgs.writeShellScriptBin "toolkit-xtask" ''
          set -euo pipefail
          toolkit_root="''${TOOLKIT_ROOT:-}"
          if [ -z "$toolkit_root" ]; then
            echo "toolkit-xtask requires TOOLKIT_ROOT" >&2
            exit 1
          fi
          target_key="$(basename "$toolkit_root" | tr -cs 'A-Za-z0-9._-' '_')"
          target_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/toolkit/xtask-target/$target_key"
          mkdir -p "$target_dir"
          export RUSTC="${rustToolchainStable}/bin/rustc"
          export RUSTDOC="${rustToolchainStable}/bin/rustdoc"
          exec ${rustToolchainStable}/bin/cargo run --target-dir "$target_dir" --manifest-path "$toolkit_root/xtask/Cargo.toml" -- "$@"
        '';

        installDylint = pkgs.writeShellScriptBin "toolkit-install-dylint" ''
          set -euo pipefail
          toolkit_root="''${TOOLKIT_ROOT:-}"
          dylint_repo="''${XDG_CACHE_HOME:-$HOME/.cache}/toolkit/dylint"
          dylint_rev="a63e31eac4f4db8cea6d1d960c6cdb8e1e52457a"
          git_bin="${pkgs.git}/bin/git"
          host="$(${rustToolchainNightly}/bin/rustc -vV | awk '/^host: / { print $2 }')"
          toolchain_name="toolkit-nightly-${nightlyDate}-''${host}"
          toolchain_root="${rustToolchainNightly}"

          mkdir -p "$(dirname "$dylint_repo")"
          if [ ! -d "$dylint_repo/.git" ]; then
            "$git_bin" clone https://github.com/trailofbits/dylint.git "$dylint_repo"
          fi
          "$git_bin" -C "$dylint_repo" fetch --tags origin
          "$git_bin" -C "$dylint_repo" checkout --force "$dylint_rev"

          ${pkgs.rustup}/bin/rustup toolchain remove "$toolchain_name" >/dev/null 2>&1 || true
          ${pkgs.rustup}/bin/rustup toolchain link "$toolchain_name" "$toolchain_root"

          # Keep the pinned nightly ahead of rustup shims for cargo-install builds.
          export PATH="${rustToolchainNightly}/bin:$HOME/.cargo/bin:$PATH"
          export CARGO="${rustToolchainNightly}/bin/cargo"
          export RUSTC="${rustToolchainNightly}/bin/rustc"
          export RUSTDOC="${rustToolchainNightly}/bin/rustdoc"
          export RUSTUP_TOOLCHAIN="$toolchain_name"
          ${rustToolchainNightly}/bin/cargo install --locked --force --path "$dylint_repo/cargo-dylint"
          ${rustToolchainNightly}/bin/cargo install --locked --force --path "$dylint_repo/dylint-link"

          if [ -n "$toolkit_root" ] && [ -d "$toolkit_root/lints" ]; then
            (
              cd "$toolkit_root/lints"
              ${pkgs.rustup}/bin/rustup override set "$toolchain_name" >/dev/null
            )
          fi
        '';

        dylintLinkWrapper = pkgs.writeShellScriptBin "toolkit-dylint-link" ''
          set -euo pipefail
          if [ -z "''${RUSTUP_TOOLCHAIN:-}" ]; then
            host="$(${rustToolchainNightly}/bin/rustc -vV | awk '/^host: / { print $2 }')"
            export RUSTUP_TOOLCHAIN="toolkit-nightly-${nightlyDate}-''${host}"
          fi
          export PATH="$HOME/.cargo/bin:$PATH"
          exec dylint-link "$@"
        '';

        toolkitRustfmt = pkgs.writeShellScript "toolkit-rustfmt" ''
          set -euo pipefail
          : "''${RUSTFMT_CONFIG_PATH:?toolkit formatter config required}"
          exec ${rustToolchainNightly}/bin/rustfmt --config-path "$RUSTFMT_CONFIG_PATH" "$@"
        '';

        toolkitFmt = pkgs.writeShellScriptBin "toolkit-fmt" ''
          set -euo pipefail
          toolkit_root="''${TOOLKIT_ROOT:-}"
          config_path=""

          if [ "''${1:-}" = "--config" ]; then
            if [ "$#" -lt 2 ]; then
              echo "toolkit-fmt: --config requires a path" >&2
              exit 1
            fi
            config_path="$2"
            shift 2
          fi

          if [ -z "$config_path" ]; then
            if [ -z "$toolkit_root" ]; then
              echo "toolkit-fmt requires either --config or TOOLKIT_ROOT" >&2
              exit 1
            fi
            config_path="$toolkit_root/rustfmt.toml"
          fi

          export RUSTFMT_CONFIG_PATH="$config_path"
          export RUSTFMT="${toolkitRustfmt}"
          export CARGO="${rustToolchainNightly}/bin/cargo"
          exec ${rustToolchainNightly}/bin/cargo-fmt fmt "$@"
        '';

        toolkitClippy = pkgs.writeShellScriptBin "toolkit-clippy" ''
          set -euo pipefail
          export RUSTC="${rustToolchainStable}/bin/rustc"
          export RUSTDOC="${rustToolchainStable}/bin/rustdoc"
          export CARGO="${rustToolchainStable}/bin/cargo"
          exec ${rustToolchainStable}/bin/cargo-clippy clippy "$@"
        '';

        toolkitCargoFmtNightly = pkgs.writeShellScriptBin "toolkit-cargo-fmt-nightly" ''
          set -euo pipefail
          exec toolkit-fmt "$@"
        '';

        toolkitDylint = pkgs.writeShellScriptBin "toolkit-dylint" ''
          set -euo pipefail

          toolkit_root="''${TOOLKIT_ROOT:-}"
          repo_root=""
          lint_path=""
          toolkit_lint=""

          while [ "$#" -gt 0 ]; do
            case "$1" in
              --repo-root)
                if [ "$#" -lt 2 ]; then
                  echo "toolkit-dylint: --repo-root requires a path" >&2
                  exit 1
                fi
                repo_root="$2"
                shift 2
                ;;
              --lint-path)
                if [ "$#" -lt 2 ]; then
                  echo "toolkit-dylint: --lint-path requires a path" >&2
                  exit 1
                fi
                lint_path="$2"
                shift 2
                ;;
              --toolkit-lint)
                if [ "$#" -lt 2 ]; then
                  echo "toolkit-dylint: --toolkit-lint requires a lint name" >&2
                  exit 1
                fi
                toolkit_lint="$2"
                shift 2
                ;;
              --)
                break
                ;;
              *)
                break
                ;;
            esac
          done

          if [ -n "$toolkit_lint" ] && [ -n "$lint_path" ]; then
            echo "toolkit-dylint: use either --toolkit-lint or --lint-path" >&2
            exit 1
          fi

          if [ -n "$toolkit_lint" ]; then
            if [ -z "$toolkit_root" ]; then
              echo "toolkit-dylint: --toolkit-lint requires TOOLKIT_ROOT" >&2
              exit 1
            fi
            lint_path="$toolkit_root/lints/$toolkit_lint"
          fi

          if [ -z "$lint_path" ]; then
            echo "toolkit-dylint: missing --lint-path or --toolkit-lint" >&2
            exit 1
          fi

          if [ ! -d "$lint_path" ]; then
            echo "toolkit-dylint: lint path does not exist: $lint_path" >&2
            exit 1
          fi

          if [ -n "$repo_root" ]; then
            cd "$repo_root"
          fi

          export CARGO_INCREMENTAL="''${CARGO_INCREMENTAL:-0}"
          export PATH="$HOME/.cargo/bin:$PATH"

          host="$(${rustToolchainNightly}/bin/rustc -vV | awk '/^host: / { print $2 }')"
          toolchain_name="toolkit-nightly-${nightlyDate}-''${host}"
          resolved_lint_path="$lint_path"
          copied_lint_dir=""
          temp_toolchain_file=""
          created_temp_toolchain=0

          if [ ! -w "$lint_path" ]; then
            copied_lint_dir="$(mktemp -d "''${TMPDIR:-/tmp}/toolkit-dylint.XXXXXX")"
            if [ -n "$toolkit_lint" ]; then
              mkdir -p "$copied_lint_dir/$toolkit_lint"
              if [ -d "$toolkit_root/lints/.cargo" ]; then
                mkdir -p "$copied_lint_dir/.cargo"
                cp -R "$toolkit_root/lints/.cargo/." "$copied_lint_dir/.cargo/"
              fi
              cp -R "$lint_path/." "$copied_lint_dir/$toolkit_lint/"
              resolved_lint_path="$copied_lint_dir/$toolkit_lint"
            else
              cp -R "$lint_path/." "$copied_lint_dir/"
              resolved_lint_path="$copied_lint_dir"
            fi
            chmod -R u+w "$copied_lint_dir"
          fi

          temp_toolchain_file="$resolved_lint_path/rust-toolchain.toml"
          if [ ! -f "$resolved_lint_path/rust-toolchain" ] && [ ! -f "$temp_toolchain_file" ]; then
            cat >"$temp_toolchain_file" <<EOF
[toolchain]
channel = "$toolchain_name"
EOF
            created_temp_toolchain=1
          fi

          cleanup() {
            if [ "$created_temp_toolchain" -eq 1 ]; then
              rm -f "$temp_toolchain_file"
            fi
            if [ -n "$copied_lint_dir" ]; then
              rm -rf "$copied_lint_dir"
            fi
          }
          trap cleanup EXIT

          ${rustToolchainNightly}/bin/cargo dylint --path "$resolved_lint_path" "$@"
        '';

        toolkitPackages = {
          toolkit-cargo = cargoWrapper;
          toolkit-rust-stable = rustToolchainStable;
          toolkit-rust-nightly = rustToolchainNightly;
          toolkit-xtask = toolkitXtask;
          toolkit-install-dylint = installDylint;
          toolkit-dylint-link = dylintLinkWrapper;
          toolkit-fmt = toolkitFmt;
          toolkit-clippy = toolkitClippy;
          toolkit-cargo-fmt-nightly = toolkitCargoFmtNightly;
          toolkit-dylint = toolkitDylint;
        };
        consumerShellSupport = {
          packages = [
            toolkitPackages.toolkit-xtask
            toolkitPackages.toolkit-fmt
            toolkitPackages.toolkit-cargo-fmt-nightly
          ];
          buildInputs =
            with pkgs;
            [ zlib ]
            ++ lib.optionals stdenv.isDarwin [ libiconv ]
            ++ lib.optionals stdenv.isLinux [ dbus ];
          shellHook = ''
            export TOOLKIT_ROOT="${self.outPath}"
            export TOOLKIT_RUNTIME_LIBRARY_PATH="${toolkitRuntimeLibPath}"
            if [ -n "''${LD_LIBRARY_PATH:-}" ]; then
              export LD_LIBRARY_PATH="$TOOLKIT_RUNTIME_LIBRARY_PATH:$LD_LIBRARY_PATH"
            else
              export LD_LIBRARY_PATH="$TOOLKIT_RUNTIME_LIBRARY_PATH"
            fi
            if [ -n "''${DYLD_LIBRARY_PATH:-}" ]; then
              export DYLD_LIBRARY_PATH="$TOOLKIT_RUNTIME_LIBRARY_PATH:$DYLD_LIBRARY_PATH"
            else
              export DYLD_LIBRARY_PATH="$TOOLKIT_RUNTIME_LIBRARY_PATH"
            fi
          '';
        };
      in
      {
        packages = toolkitPackages;
        lib = {
          inherit consumerShellSupport;
        };

        devShells.default = pkgs.mkShell {
          packages =
            consumerShellSupport.packages
            ++ (with pkgs; [
              cargoWrapper
              rustToolchainStable
              git
              just
              ripgrep
              perl
              pkg-config
              openssl
              rustup
            ])
            ;
          buildInputs = consumerShellSupport.buildInputs;

          shellHook = ''
            ${consumerShellSupport.shellHook}
            if [ -f "$PWD/flake.nix" ] && [ -d "$PWD/xtask" ] && [ -d "$PWD/lints" ]; then
              export TOOLKIT_ROOT="$PWD"
            else
              export TOOLKIT_ROOT="${self.outPath}"
            fi
            [[ -r "$HOME/.local/state/secrets/cargo-registry-token" ]] && export CARGO_REGISTRY_TOKEN="$(cat "$HOME/.local/state/secrets/cargo-registry-token")"
            echo "Toolkit stable environment (nightly rustfmt/Dylint)"
            echo "Rust: $(${rustToolchainStable}/bin/rustc --version)"
            echo "Run 'toolkit-install-dylint' once in this shell if cargo-dylint is not installed."
          '';
        };
      }
    );
}
