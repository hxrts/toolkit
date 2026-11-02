#!/usr/bin/env bash
# Preserve per-command Cargo unit evidence, not a metadata feature union.
set -euo pipefail
schema=${TOOLKIT_UNIT_INVENTORY_SCHEMA:-}
[[ $schema =~ ^[abcdefghijklmnopqrstuvwxyz][abcdefghijklmnopqrstuvwxyz0123456789-]{0,63}$ ]] || {
  printf '%s\n' 'warm units: explicit lowercase inventory schema required (1..64 bytes)' >&2 || :
  exit 2
}
[[ $# == 5 ]] || { echo 'warm units: expected output, selection, check/build/test logs' >&2; exit 2; }
output=$1
selection=$2
shift 2
[[ ! -e "$output" && ! -L "$output" && -d "${output%/*}" && ! -L "${output%/*}" ]] || {
  echo 'warm units: output must be absent in an ordinary directory' >&2; exit 2;
}
for file in "$selection" "$@"; do
  [[ -f "$file" && ! -L "$file" ]] || { echo 'warm units: missing or symlinked input' >&2; exit 2; }
done
temporary=$(mktemp "${output%/*}/.warm-units.XXXXXX")
finish_inventory() {
  local primary=$? cleanup=0
  trap - EXIT
  rm -f -- "$temporary" || cleanup=$?
  if (( cleanup != 0 )); then
    printf 'warm units: temporary cleanup failed native=%s primary=%s path=%s\n' \
      "$cleanup" "$primary" "$temporary" >&2 || :
    (( primary != 0 )) || primary=$cleanup
  fi
  exit "$primary"
}
trap finish_inventory EXIT
jq -n --arg schema "$schema" --slurpfile selection "$selection" \
  --slurpfile check "$1" --slurpfile build "$2" --slurpfile test "$3" '
  def text: type == "string" and length > 0;
  def strings: type == "array" and all(.[]; text);
  def artifact:
    (.package_id | text) and (.manifest_path | text)
    and (.features | strings) and (.filenames | strings)
    and (.filenames | length > 0) and (.fresh | type == "boolean")
    and (.target | type == "object") and (.target.name | text)
    and (.target.kind | strings) and (.target.kind | length > 0)
    and (.target.src_path | text) and (.profile | type == "object")
    and (.profile.test | type == "boolean");
  if ($selection | length) != 1 then error("ambiguous selection") else
  $selection[0] as $s
  | if ($s.commands | type) != "array" or ($s.commands | length) != 3
      or (all($s.commands[]; strings and length > 0) | not)
    then error("invalid selection commands") else
  [$check, $build, $test] | to_entries | map(
    .key as $index | .value as $records
    | if ($records | length) == 0
        or (all($records[]; type == "object" and (.reason | text)) | not)
        or ([$records[] | select(.reason == "build-finished")] | length) != 1
        or $records[-1].reason != "build-finished" or $records[-1].success != true
      then error("missing or unsuccessful terminal Cargo record") else
    [$records[] | select(.reason == "compiler-artifact")] as $units
    | if ($units | length) == 0 or (all($units[]; artifact) | not)
      then error("missing or malformed Cargo units") else
      # Only the resolved-unit view is published. Completion order, freshness,
      # ephemeral filenames and build-script OUT_DIRs are not feature identity.
      # Byte retention and build-script output validity require separate proof.
      {command: $s.commands[$index],
       units: ($units | map({package_id, manifest_path, target, profile, features})
         | sort_by(tojson))}
      end end)
  | {schema: $schema, scope: "resolved-unit-features",
     selection: $s, commands: .}
  end end
' > "$temporary"
# Publish only a complete inventory. Never replace pre-existing warm evidence.
ln "$temporary" "$output"
echo 'warm units: published three successful command inventories' >&2
