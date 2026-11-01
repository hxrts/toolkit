let
  key = import ../cargo-dependency-cache-key.nix;
  schema = "aura-cargo-deps-key-v2";
  input = {
    platform = "aarch64-darwin";
    devShellPath = "/nix/store/shell.drv";
    toolchainPath = "/nix/store/toolchain";
    vendorPath = "/nix/store/vendor";
    lockHash = "lock";
    dummyManifestPath = "/nix/store/source/Cargo.toml";
    dummyConfigPath = "/nix/store/vendor/config.toml";
    package = "example";
    packages = [ "example" ];
    profile = "dev";
    features = [];
    defaultFeatures = true;
    allFeatures = false;
    target = "aarch64-apple-darwin";
    host = "aarch64-apple-darwin";
    commands = [ [ "cargo" "check" "--locked" ] ];
    profileOverrides = {};
    resolvedUnitsPath = "/nix/store/output/dependency-units.json";
    rustflags = "";
    cc = "/nix/store/cc/bin/cc";
    wrapper = "";
    incremental = false;
    buildEnv = { CARGO_INCREMENTAL = "0"; };
  };
  baseline = key schema input;
  rejected = value: !(builtins.tryEval value).success;
  changed = value: key schema value != baseline;
  textFields = [
    "platform" "devShellPath" "toolchainPath" "vendorPath" "lockHash"
    "dummyManifestPath" "dummyConfigPath" "package" "profile" "target"
    "host" "resolvedUnitsPath" "rustflags" "cc" "wrapper"
  ];
  requiredIdentities = [
    "platform" "devShellPath" "toolchainPath" "vendorPath" "lockHash"
    "dummyManifestPath" "dummyConfigPath" "package" "profile" "target"
    "host" "resolvedUnitsPath"
  ];
  override = name: value: input // { ${name} = value; };
in
assert baseline == builtins.hashString "sha256" (builtins.toJSON { inherit schema input; });
assert key "another-schema" input != baseline;
assert builtins.all (name: changed (override name "different")) textFields;
assert builtins.all (name: rejected (key schema (override name 1))) textFields;
assert builtins.all (name: rejected (key schema (override name ""))) requiredIdentities;
assert builtins.all (name: rejected (key schema (builtins.removeAttrs input [ name ]))) (builtins.attrNames input);
assert changed (input // { vendorPath = "/nix/store/other-vendor"; });
assert changed (input // { features = [ "feature" ]; });
assert changed (input // { incremental = true; });
assert changed (input // { commands = [ [ "cargo" "test" ] ]; });
assert changed (input // { buildEnv = { CARGO_INCREMENTAL = "1"; }; });
assert rejected (key "" input);
assert rejected (key 3 input);
assert rejected (key schema (builtins.removeAttrs input [ "vendorPath" ]));
assert rejected (key schema (input // { unexpected = "value"; }));
assert rejected (key schema (input // { features = [ 1 ]; }));
assert rejected (key schema (input // { incremental = "false"; }));
assert rejected (key schema (input // { defaultFeatures = "true"; }));
assert rejected (key schema (input // { allFeatures = "false"; }));
assert rejected (key schema (input // { buildEnv = { BAD = 1; }; }));
assert rejected (key schema (input // { profileOverrides = { BAD = 1; }; }));
assert rejected (key schema (input // { commands = [ [] ]; }));
assert rejected (key schema (input // { packages = []; }));
assert rejected (key schema (input // { vendorPath = ""; }));
"ok"
