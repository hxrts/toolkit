#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd -P)
runner=${1:-$here/unit-inventory.sh}
[[ $# -le 1 && $runner == /* && -f $runner ]] || exit 2
invocation=("$BASH" "$runner")
if [[ $# == 1 ]]; then [[ -x $runner ]] || exit 2; invocation=("$runner"); fi
export TOOLKIT_UNIT_INVENTORY_SCHEMA=toolkit-test-unit-inventory-v1
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
printf '%s\n' '{"commands":[["cargo","check"],["cargo","build"],["cargo","test"]]}' > "$scratch/selection"
jq -nc '{reason:"compiler-artifact",package_id:"registry+example#unit@1.0.0",
  manifest_path:"/immutable/unit/Cargo.toml",features:["selected"],
  target:{name:"unit",kind:["lib"],src_path:"/immutable/unit/lib.rs"},
  profile:{test:false},fresh:true,filenames:["/target/libunit.rmeta"]},
  {reason:"build-finished",success:true}' > "$scratch/good"
run() { "${invocation[@]}" "$scratch/output" "$scratch/selection" "$1" "$scratch/good" "$scratch/good"; }
run "$scratch/good" > "$scratch/stdout" 2> "$scratch/stderr"
jq -e '.schema=="toolkit-test-unit-inventory-v1" and .scope=="resolved-unit-features" and (.commands | length == 3 and .[0].units[0].features == ["selected"])' "$scratch/output" >/dev/null
# Independent Cargo completion order must not change the feature inventory.
jq -sc '.[0], (.[0] | .package_id="registry+example#second@1.0.0"), .[1]' "$scratch/good" > "$scratch/two"
jq -sc '.[1], .[0], .[2]' "$scratch/two" > "$scratch/reversed"
rm "$scratch/output"
run "$scratch/two" > "$scratch/stdout" 2> "$scratch/stderr"
cp "$scratch/output" "$scratch/ordered-output"
rm "$scratch/output"
run "$scratch/reversed" > "$scratch/stdout" 2> "$scratch/stderr"
cmp "$scratch/ordered-output" "$scratch/output"
# Same package with different per-command features remains distinct.
jq -c 'if .reason == "compiler-artifact" then .features=["other"] else . end' "$scratch/good" > "$scratch/other"
rm "$scratch/output"
run "$scratch/other" > "$scratch/stdout" 2> "$scratch/stderr"
jq -e '.commands[0].units[0].features == ["other"] and .commands[1].units[0].features == ["selected"]' "$scratch/output" >/dev/null
for mutation in 'select(.reason != "build-finished")' \
  'if .reason == "build-finished" then .success=false else . end' \
  'if .reason == "compiler-artifact" then .features="selected" else . end' \
  'if .reason == "compiler-artifact" then .features=[null] else . end' \
  'select(.reason != "compiler-artifact")'; do
  jq -c "$mutation" "$scratch/good" > "$scratch/bad"
  rm "$scratch/output"
  status=0
  run "$scratch/bad" > "$scratch/stdout" 2> "$scratch/stderr" || status=$?
  [[ "$status" == 5 && ! -e "$scratch/output" ]]
  grep -Eq 'missing or (unsuccessful terminal Cargo record|malformed Cargo units)' "$scratch/stderr"
  run "$scratch/good" > "$scratch/stdout" 2> "$scratch/stderr"
done
cp "$scratch/output" "$scratch/held"
status=0
run "$scratch/good" > "$scratch/stdout" 2> "$scratch/stderr" || status=$?
[[ "$status" == 2 ]]
cmp "$scratch/held" "$scratch/output"
echo 'warm units: per-command features, terminal/schema refusals and held-output preservation passed'

for invalid in '' UPPER 'has_underscore' $'line\nbreak' $'\xc3\xa9' "$(printf 'a%.0s' {1..65})"; do
 status=0
 TOOLKIT_UNIT_INVENTORY_SCHEMA=$invalid "${invocation[@]}" "$scratch/schema-output" \
  "$scratch/selection" "$scratch/good" "$scratch/good" "$scratch/good" \
  > "$scratch/schema.stdout" 2> "$scratch/schema.stderr" || status=$?
 [[ $status == 2 && ! -s $scratch/schema.stdout && ! -e $scratch/schema-output ]]
 grep -Fx 'warm units: explicit lowercase inventory schema required (1..64 bytes)' "$scratch/schema.stderr" >/dev/null
 cmp "$scratch/held" "$scratch/output"
done
longest=$(printf 'a%.0s' {1..64})
TOOLKIT_UNIT_INVENTORY_SCHEMA=$longest "${invocation[@]}" "$scratch/schema-output" \
 "$scratch/selection" "$scratch/good" "$scratch/good" "$scratch/good" \
 > "$scratch/schema.stdout" 2> "$scratch/schema.stderr"
jq -e --arg schema "$longest" '.schema==$schema' "$scratch/schema-output" >/dev/null
printf '%s\n' 'unit inventory schema:6 exact refusals and maximum64-byte acceptance passed'

real_jq=$(type -P jq)
real_ln=$(type -P ln)
# Establish the actual native primary error without the cleanup fault first.
jq -c 'if .reason=="compiler-artifact" then .features="invalid" else . end' \
 "$scratch/good" > "$scratch/malformed"
status=0
"${invocation[@]}" "$scratch/baseline-output" "$scratch/selection" "$scratch/malformed" \
 "$scratch/good" "$scratch/good" > "$scratch/baseline.stdout" 2> "$scratch/baseline.stderr" || status=$?
[[ $status == 5 && ! -e $scratch/baseline-output ]]
grep -F 'missing or malformed Cargo units' "$scratch/baseline.stderr" >/dev/null
for case_name in success primary closed-primary publication; do
 directory="$scratch/$case_name"
 mkdir -p "$directory/bin"
 cat > "$directory/bin/rm" <<'REMOVE'
#!/bin/bash
printf '%s\0' "$@" > "$INVENTORY_CLEANUP_ACK"
exit 43
REMOVE
 cat > "$directory/bin/jq" <<'QUERY'
#!/bin/bash
result=0
"$INVENTORY_REAL_JQ" "$@" || result=$?
printf '%s\n' "$result" > "$INVENTORY_PRIMARY_ACK"
exit "$result"
QUERY
 cat > "$directory/bin/ln" <<'LINK'
#!/bin/bash
if [[ $INVENTORY_PUBLICATION_FAULT == 1 ]]; then
 printf '44\n' > "$INVENTORY_PUBLICATION_ACK"
 exit 44
fi
exec "$INVENTORY_REAL_LN" "$@"
LINK
 chmod +x "$directory/bin/"*
 input="$scratch/good" expected=43 fault=0
 case $case_name in primary|closed-primary) input="$scratch/malformed"; expected=5;; publication) fault=1; expected=44;; esac
 status=0
 (
  if [[ $case_name == closed-primary ]]; then
   exec 2>&-
   if : >&2; then exit 98; fi
   printf 'original stderr EBADF acknowledged\n' > "$directory/closed-ack"
  fi
  export PATH="$directory/bin:$PATH" INVENTORY_REAL_JQ="$real_jq" INVENTORY_REAL_LN="$real_ln"
  export INVENTORY_CLEANUP_ACK="$directory/cleanup-ack" INVENTORY_PRIMARY_ACK="$directory/primary-ack"
  export INVENTORY_PUBLICATION_FAULT="$fault" INVENTORY_PUBLICATION_ACK="$directory/publication-ack"
  "${invocation[@]}" "$directory/output" "$scratch/selection" "$input" "$scratch/good" "$scratch/good"
 ) > "$directory/stdout" 2> "$directory/stderr" || status=$?
 [[ $status == "$expected" && -s $directory/cleanup-ack ]]
 remaining=$(find "$directory" -maxdepth 1 -type f -name '.warm-units.*')
 [[ -n $remaining && -f $remaining ]]
 case $case_name in
  success) [[ $remaining -ef $directory/output && $(cat "$directory/primary-ack") == 0 ]];;
  publication) [[ ! -e $directory/output && $(cat "$directory/primary-ack") == 0 && $(cat "$directory/publication-ack") == 44 ]];;
  *) [[ ! -e $directory/output && $(cat "$directory/primary-ack") == 5 ]];;
 esac
 if [[ $case_name == closed-primary ]]; then
  [[ -s $directory/closed-ack && ! -s $directory/stderr ]]
 else
  primary=$expected; [[ $case_name != success ]] || primary=0
  grep -F "temporary cleanup failed native=43 primary=$primary" "$directory/stderr" >/dev/null
 fi
 printf 'PASS inventory %s: original error retained with actual cleanup43; terminal%s\n' "$case_name" "$status"
done
