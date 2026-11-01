# Pure key definition for a dependency-only Cargo warm tree.
# All paths are the exact producer store paths. Callers must supply every
# fingerprint input; this function does not inspect ambient process state.
schema: input:
let
  required = [
    "platform" "devShellPath" "toolchainPath" "vendorPath" "lockHash"
    "dummyManifestPath" "dummyConfigPath" "package" "profile" "features"
    "target" "rustflags" "cc" "wrapper" "incremental" "buildEnv"
    "host" "commands" "packages" "defaultFeatures" "allFeatures" "profileOverrides"
    "resolvedUnitsPath"
  ];
  missing = builtins.filter (name: !(builtins.hasAttr name input)) required;
  extra = builtins.filter (name: !(builtins.elem name required)) (builtins.attrNames input);
  textFields = builtins.filter
    (name: !(builtins.elem name [ "features" "incremental" "buildEnv"
      "commands" "packages" "defaultFeatures" "allFeatures" "profileOverrides" ])) required;
  badText = builtins.filter (name: !(builtins.isString input.${name})) textFields;
  badFeatures = !(builtins.isList input.features)
    || !(builtins.all builtins.isString input.features);
  badIncremental = !(builtins.isBool input.incremental);
  badBuildEnv = !(builtins.isAttrs input.buildEnv)
    || !(builtins.all builtins.isString (builtins.attrValues input.buildEnv));
  stringList = value: builtins.isList value && builtins.all builtins.isString value;
  badSelection = !(stringList input.packages) || input.packages == []
    || builtins.any (value: value == "") input.packages
    || !(builtins.isList input.commands) || input.commands == []
    || !(builtins.all (argv: stringList argv && argv != []
      && builtins.head argv != "") input.commands)
    || !(builtins.isBool input.defaultFeatures) || !(builtins.isBool input.allFeatures)
    || !(builtins.isAttrs input.profileOverrides)
    || !(builtins.all builtins.isString (builtins.attrValues input.profileOverrides));
  canonical = { inherit schema input; };
in
  if !(builtins.isString schema) || schema == "" then throw "build-cache-key: schema must be nonempty text"
  else if !(builtins.isAttrs input) then throw "build-cache-key: input must be an attribute set"
  else if missing != [] then throw "build-cache-key: missing required inputs"
  else if extra != [] then throw "build-cache-key: unexpected inputs"
  else if badText != [] || badFeatures || badIncremental || badBuildEnv || badSelection then
    throw "build-cache-key: invalid input types"
  else if builtins.any (name: input.${name} == "")
    [ "platform" "devShellPath" "toolchainPath" "vendorPath" "lockHash"
      "dummyManifestPath" "dummyConfigPath" "package" "profile" "target" "host" "resolvedUnitsPath" ] then
    throw "build-cache-key: required identity is empty"
  else builtins.hashString "sha256" (builtins.toJSON canonical)
