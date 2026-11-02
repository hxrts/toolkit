#!/usr/bin/env bash
# Retain an original command's byte-framed stdout without replacing its failure.
set -euo pipefail
# Inspect in a subshell so even the preflight's temporary names cannot replace
# an exported original-command input in this process.
(
  for name in _toolkit_frame_prefix log metadata command_status; do
    declaration=$(declare -p "$name" 2>/dev/null) || continue
    flags=${declaration#declare }; flags=${flags%% *}
    [[ $flags != -*x* ]] || {
      printf 'command evidence: reserved internal export refused: %s\n' "$name" >&2 || :
      exit 2
    }
  done
) || exit "$?"
_toolkit_frame_prefix=${TOOLKIT_COMMAND_EVIDENCE_PREFIX:-}
if [[ ${1:-} == --frame-prefix ]]; then
  [[ $# -ge 3 && $3 == -- ]] || {
    printf '%s\n' 'command evidence: expected --frame-prefix PREFIX -- LOG -- COMMAND...' >&2 || :
    exit 2
  }
  _toolkit_frame_prefix=$2
  shift 3
fi
[[ $_toolkit_frame_prefix =~ ^[ABCDEFGHIJKLMNOPQRSTUVWXYZ][ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]{0,63}$ ]] || {
  printf '%s\n' 'command evidence: explicit uppercase frame prefix required (1..64 bytes)' >&2 || :
  exit 2
}
[[ $# -ge 3 && $2 == -- && $1 == /* ]] || {
  printf '%s\n' 'command evidence: expected absolute LOG -- COMMAND...' >&2 || :
  exit 2;
}
log=$1; shift 2
metadata=$(mktemp -d)
cleanup_evidence() {
  local primary=$? cleanup=0
  trap - EXIT
  rm -rf -- "$metadata" || cleanup=$?
  if (( cleanup != 0 )); then
    printf '%s\n' "command evidence: metadata cleanup failed native=$cleanup primary=$primary path=$metadata" >&2 || :
    (( primary != 0 )) || primary=$cleanup
  fi
  exit "$primary"
}
trap cleanup_evidence EXIT
jq -cn --args '$ARGS.positional' -- "$@" > "$metadata/argv.json"
# Retain even an original failing command's partial stdout. Cargo owns its
# original stderr directly; do not infer ordering between the two streams.
command_status=0
"$@" > "$log" || command_status=$?
# Logging happens only AFTER the original command returns. Ignore SIGPIPE here,
# so a closed log channel cannot terminate this shell before primary selection.
# The original command did not inherit this changed signal disposition.
trap '' PIPE
publish_evidence() {
  local argv_bytes stdout_bytes
  argv_bytes=$(wc -c < "$metadata/argv.json") || return "$?"
  stdout_bytes=$(wc -c < "$log") || return "$?"
  printf '%s_BEGIN_V1\nargv-json-bytes:%s\nargv-json-base64:\n' "$_toolkit_frame_prefix" "$argv_bytes" || return "$?"
  base64 < "$metadata/argv.json" || return "$?"
  printf '\n%s_ARGV_END_V1\nstdout-bytes:%s\nstdout-base64:\n' "$_toolkit_frame_prefix" "$stdout_bytes" || return "$?"
  base64 < "$log" || return "$?"
  printf '\n%s_STDOUT_END_V1\ncommand-status:%s\n%s_END_V1\n' "$_toolkit_frame_prefix" "$command_status" "$_toolkit_frame_prefix" || return "$?"
}
publication_status=0
publish_evidence || publication_status=$?
if (( publication_status != 0 )); then
  printf '%s\n' "command evidence: log publication failed native=$publication_status primary=$command_status" >&2 || :
fi
(( command_status == 0 )) || exit "$command_status"
exit "$publication_status"
