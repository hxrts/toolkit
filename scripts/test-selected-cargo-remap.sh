#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ $# -le 1 ]] || exit 2
entry=(bash "$root/scripts/selected-cargo-remap.sh")
if [[ $# == 1 ]]; then
  [[ $1 == /* && -f $1 && -x $1 ]] || exit 2
  entry=("$1")
fi
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/bin"
cat > "$fixture/selected compiler" <<'COMPILER'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$REMAP_TEST_ARGV"
printf 'selected stdout\n'
printf 'selected stderr\n' >&2
exit "${REMAP_TEST_STATUS:-0}"
COMPILER
printf '#!/bin/sh\nexit 98\n' > "$fixture/bin/rustc"
chmod +x "$fixture/selected compiler" "$fixture/bin/rustc"
export PATH="$fixture/bin:$PATH" REMAP_TEST_ARGV="$fixture/argv"
command=("${entry[@]}" --compiler "$fixture/selected compiler" --from "$fixture/output" --to /consumer-output --)
for original in rustc "$fixture/selected compiler"; do
  "${command[@]}" "$original" --print cfg 'a b' '' $'line\nbreak' > "$fixture/stdout" 2> "$fixture/stderr"
  printf '%s\0' "--remap-path-prefix=$fixture/output=/consumer-output" --print cfg 'a b' '' $'line\nbreak' > "$fixture/expected"
  cmp "$fixture/argv" "$fixture/expected"
  [[ $(cat "$fixture/stdout") == 'selected stdout' && $(cat "$fixture/stderr") == 'selected stderr' ]]
done
actual=0
REMAP_TEST_STATUS=37 "${command[@]}" rustc --version > "$fixture/stdout" 2> "$fixture/stderr" || actual=$?
[[ $actual == 37 && $(cat "$fixture/stderr") == 'selected stderr' ]]
refusal() {
  local actual=0
  rm -f "$fixture/argv"
  "${entry[@]}" "$@" > "$fixture/stdout" 2> "$fixture/stderr" || actual=$?
  [[ $actual == 2 && ! -e $fixture/argv && ! -s $fixture/stdout ]]
  grep -F 'toolkit-cargo-remap:' "$fixture/stderr" >/dev/null
}
refusal
refusal --compiler "$fixture/selected compiler" --from "$fixture/output" --to /consumer-output --
refusal --compiler "$fixture/selected compiler" --from "$fixture/output" --to /consumer-output -- foreign-rustc
refusal --compiler relative --from "$fixture/output" --to /consumer-output -- rustc
refusal --compiler "$fixture/missing" --from "$fixture/output" --to /consumer-output -- rustc
refusal --compiler "$fixture" --from "$fixture/output" --to /consumer-output -- rustc
refusal --compiler "$fixture/selected compiler" --from / --to /consumer-output -- rustc
refusal --compiler "$fixture/selected compiler" --from relative --to /consumer-output -- rustc
refusal --compiler "$fixture/selected compiler" --from "$fixture/output" --to relative -- rustc
actual=0
rm -f "$fixture/argv"
"${entry[@]}" > "$fixture/stdout" 2>&- || actual=$?
[[ $actual == 2 && ! -e $fixture/argv && ! -s $fixture/stdout ]]
printf '%s\n' 'selected remap: exact argv/streams, PATH substitution refusal, native37,9 invalid requests and closed-stderr refusal2 passed'
