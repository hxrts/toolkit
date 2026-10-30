#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd -P)
fixture=$(mktemp -d /tmp/shared-dispatch.XXXXXX)
trap 'native=$?; echo "dispatch fixture retained: $fixture"; exit "$native"' EXIT
export CAPTURE="$fixture/capture"
mkdir "$fixture/selected" "$fixture/foreign"
for tool in cargo clippy fmt; do
 cat > "$fixture/$tool" <<'TOOL'
#!/usr/bin/env bash
tool=${0##*/}
printf '%s\n' "$tool" > "$CAPTURE.tool"
printf '%s\0' "$@" > "$CAPTURE.argv"
printf '%s\n' "${RUSTC_WRAPPER-<none>}" "$@" > "$CAPTURE"
printf 'stdout:%s\n' "$tool"
printf 'stderr:%s\n' "$tool" >&2
exit "${RESULT:-0}"
TOOL
 chmod +x "$fixture/$tool"
done
printf '#!/bin/sh\nexit 97\n' > "$fixture/selected/sccache"
cp "$fixture/selected/sccache" "$fixture/foreign/sccache"
chmod +x "$fixture/selected/sccache" "$fixture/foreign/sccache"
helper=${SHARED_DISPATCH_HELPER:-"$here/selected-cargo-dispatch.sh"}
for mode in cargo-fmt selected-fmt; do
 cat > "$fixture/$mode.sh" <<'ADAPTER'
#!/usr/bin/env bash
set -euo pipefail
bypass=0
[[ ${TEST_NO_SCCACHE:-0} != 1 && ${CARGO_INCREMENTAL:-0} != 1 ]] || bypass=1
if [[ ${0##*/} == selected-fmt.sh && ${1:-} == fmt ]]; then
 exec "$TOOLKIT_CARGO_DISPATCH_BIN" --cargo "$TEST_NIX_CARGO_BIN" --clippy "$TEST_NIX_CLIPPY_BIN" --selected-cache "$TEST_NIX_SCCACHE_BIN" --cache-bypass "$bypass" --fmt "$TEST_NIX_FMT_BIN" -- "$@"
fi
exec "$TOOLKIT_CARGO_DISPATCH_BIN" --cargo "$TEST_NIX_CARGO_BIN" --clippy "$TEST_NIX_CLIPPY_BIN" --selected-cache "$TEST_NIX_SCCACHE_BIN" --cache-bypass "$bypass" -- "$@"
ADAPTER
 chmod +x "$fixture/$mode.sh"
done
for adapter in cargo-fmt selected-fmt; do
export TOOLKIT_CARGO_DISPATCH_BIN="$helper"
 prefix=TEST
 export "${prefix}_NIX_CARGO_BIN=$fixture/cargo" "${prefix}_NIX_CLIPPY_BIN=$fixture/clippy" "${prefix}_NIX_SCCACHE_BIN=$fixture/selected/sccache" "${prefix}_NIX_FMT_BIN=$fixture/fmt"
 dispatch() { local bypass=$1;shift; env "${prefix}_NO_SCCACHE=$bypass" bash "$fixture/$adapter.sh" "$@" > "$fixture/stdout" 2> "$fixture/stderr"; }
 for bypass in 0 1; do
  RUSTC_WRAPPER="$fixture/selected/sccache" dispatch "$bypass" build 'path with spaces'
  if [[ $bypass == 1 ]]; then expected='<none>';else expected="$fixture/selected/sccache";fi
  printf '%s\n' "$expected" build 'path with spaces' > "$fixture/expected"
  cmp "$fixture/expected" "$CAPTURE"
 done
 PATH="$fixture/selected:$PATH" RUSTC_WRAPPER=sccache dispatch 1 test
 [[ $(head -n1 "$CAPTURE") == '<none>' ]]
 CARGO_INCREMENTAL=1 RUSTC_WRAPPER="$fixture/selected/sccache" dispatch 0 build
 [[ $(head -n1 "$CAPTURE") == '<none>' ]]
 PATH="$fixture/foreign:$PATH" RUSTC_WRAPPER=sccache dispatch 1 test
 [[ $(head -n1 "$CAPTURE") == sccache ]]
 RUSTC_WRAPPER=/caller/custom-sccache dispatch 1 test
 [[ $(head -n1 "$CAPTURE") == /caller/custom-sccache ]]
 RUSTC_WRAPPER='' dispatch 1 build
 [[ $(head -n1 "$CAPTURE") == '' ]]
 for command in clippy fmt build; do
  native=0
  RESULT=37 dispatch 0 "$command" --manifest-path 'path with spaces' || native=$?
  [[ $native == 37 ]]
  case $command in clippy) expected_tool=clippy;; fmt) if [[ $adapter == cargo-fmt ]]; then expected_tool=cargo;else expected_tool=fmt;fi;; *) expected_tool=cargo;; esac
  actual_tool=$(cat "$CAPTURE.tool")
  if [[ $actual_tool != "$expected_tool" ]]; then
   printf 'EXPECTED_TOOL_MISMATCH adapter=%s command=%s expected=%s actual=%s\n' "$adapter" "$command" "$expected_tool" "$actual_tool" >&2
   exit 78
  fi
  printf 'stdout:%s\n' "$expected_tool" > "$fixture/expected-stdout"
  printf 'stderr:%s\n' "$expected_tool" > "$fixture/expected-stderr"
  cmp "$fixture/expected-stdout" "$fixture/stdout"
  cmp "$fixture/expected-stderr" "$fixture/stderr"
  printf '%s\0' "$command" --manifest-path 'path with spaces' > "$fixture/expected-argv"
  cmp "$fixture/expected-argv" "$CAPTURE.argv"
  tail -n3 "$CAPTURE" > "$fixture/actual"
  printf '%s\n' "$command" --manifest-path 'path with spaces' > "$fixture/expected"
  cmp "$fixture/expected" "$fixture/actual"
 done
 echo "PASS $adapter parameter adapter: selected/bare/foreign/custom wrapper, argv boundaries, Clippy/fmt/Cargo native37"
done
native=0
bash "$helper" --cargo relative --clippy /selected --selected-cache /selected --cache-bypass 0 -- build || native=$?
[[ $native == 2 ]]
echo 'PASS malformed adapter selection refuses exact2'
if [[ ${SKIP_MUTANT_CONTROL:-0} != 1 ]]; then
 # Preserve selection/bypass; mutate only actual dispatch to route every command to Cargo.
 awk '/^case \$\{1:-\} in$/ {print "exec \"$cargo\" \"$@\""; exit} {print}' "$helper" > "$fixture/all-through-cargo.sh"
 chmod +x "$fixture/all-through-cargo.sh"
 native=0
 SKIP_MUTANT_CONTROL=1 SHARED_DISPATCH_HELPER="$fixture/all-through-cargo.sh" bash "$0" > "$fixture/mutant.stdout" 2> "$fixture/mutant.stderr" || native=$?
 [[ $native == 78 ]]
 expected='EXPECTED_TOOL_MISMATCH adapter=cargo-fmt command=clippy expected=clippy actual=cargo'
 [[ $(cat "$fixture/mutant.stderr") == "$expected" ]]
 echo 'PASS all-through-Cargo mutant rejected exact78 with expected Clippy routing cause'
fi
