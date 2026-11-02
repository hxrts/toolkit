{ pkgs, helper }:
pkgs.runCommand "toolkit-command-evidence-environment" {
  nativeBuildInputs = [ pkgs.jq pkgs.coreutils ];
} ''
  mkdir "$out"
  command='printf "%s\n%s\n" "''${prefix-__unset__}" "''${TOOLKIT_COMMAND_EVIDENCE_PREFIX-__unset__}"'
  probe() {
    local name=$1
    ${pkgs.bash}/bin/bash -c "$command" > "$TMPDIR/$name.before"
    ${helper}/bin/toolkit-command-evidence --frame-prefix TOOLKIT_ENV_PROBE -- \
      "$TMPDIR/$name.raw" -- ${pkgs.bash}/bin/bash -c "$command" > "$out/$name.frame"
    cmp "$TMPDIR/$name.before" "$TMPDIR/$name.raw"
  }
  probe native-stdenv
  export prefix='original caller prefix'
  unset TOOLKIT_COMMAND_EVIDENCE_PREFIX
  probe explicit-prefix
  export TOOLKIT_COMMAND_EVIDENCE_PREFIX='original caller config'
  probe original-framing-environment
''
