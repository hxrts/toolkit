#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd -P)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/cargo" <<'TOOL'
#!/usr/bin/env bash
printf '%s' "${CARGO_TOOLKIT_APPLE_DEPLOYMENT_V1-ABSENT}" > "$CAPTURE"
printf '%s\n' "${RUSTC_WRAPPER-ABSENT}" > "$CAPTURE.wrapper"
printf '%s\0' "$@" > "$CAPTURE.args"
exit "${RESULT:-0}"
TOOL
chmod +x "$scratch/cargo"
export CAPTURE=$scratch/capture
helper=$here/selected-cargo-dispatch.sh
different() { local native=0; cmp -s "$1" "$2" || native=$?; [[ $native == 1 ]] || { echo "expected distinct projection (cmp1), actual=$native" >&2; exit 78; }; }
run() { bash "$helper" --cargo "$scratch/cargo" --clippy "$scratch/cargo" --selected-cache "$scratch/selected-cache" --cache-bypass "${BYPASS:-0}" -- build 'space arg'; }
export RUSTC_WRAPPER=$scratch/selected-cache
unset MACOSX_DEPLOYMENT_TARGET
run; cp "$CAPTURE" "$scratch/absent"
MACOSX_DEPLOYMENT_TARGET='' run; cp "$CAPTURE" "$scratch/empty"
MACOSX_DEPLOYMENT_TARGET=11.0 run; cp "$CAPTURE" "$scratch/11"
MACOSX_DEPLOYMENT_TARGET=14.0 run; cp "$CAPTURE" "$scratch/14"
different "$scratch/absent" "$scratch/empty"
different "$scratch/empty" "$scratch/11"
different "$scratch/11" "$scratch/14"
echo 'PASS absent/empty/11/14 distinct projection'
CARGO_TOOLKIT_APPLE_DEPLOYMENT_V1=poison MACOSX_DEPLOYMENT_TARGET=11.0 run
cmp "$CAPTURE" "$scratch/11"
echo 'PASS inherited poison marker recomputed'
MACOSX_DEPLOYMENT_TARGET=11.0 MACOSX_DEPLOYMENT_TARGET_FOR_TARGET=14.0 run
different "$CAPTURE" "$scratch/11"
echo 'PASS selected suffix participates'
for key in IPHONEOS_DEPLOYMENT_TARGET TVOS_DEPLOYMENT_TARGET WATCHOS_DEPLOYMENT_TARGET XROS_DEPLOYMENT_TARGET; do
 env "$key=1.0" "$BASH" "$helper" --cargo "$scratch/cargo" --clippy "$scratch/cargo" --selected-cache "$scratch/selected-cache" --cache-bypass 0 -- build
 different "$CAPTURE" "$scratch/absent"
 echo "PASS $key participates"
done
RUSTC_WRAPPER=/foreign CARGO_TOOLKIT_APPLE_DEPLOYMENT_V1=caller run
[[ $(cat "$CAPTURE") == caller && $(cat "$CAPTURE.wrapper") == /foreign ]]
echo 'PASS foreign wrapper and caller marker untouched'
BYPASS=1 CARGO_TOOLKIT_APPLE_DEPLOYMENT_V1=caller run
[[ $(cat "$CAPTURE") == caller && $(cat "$CAPTURE.wrapper") == ABSENT ]]
echo 'PASS selected bypass retains prior env semantics'
native=0; RESULT=37 run || native=$?
[[ $native == 37 ]]
echo 'PASS native37 preserved'
printf 'build\0space arg\0' > "$scratch/expected.args"
cmp "$scratch/expected.args" "$CAPTURE.args"
echo 'PASS original argument bytes preserved'
MACOSX_DEPLOYMENT_TARGET=$'11;X=V2:\n14.0' run
cp "$CAPTURE" "$scratch/separators"
MACOSX_DEPLOYMENT_TARGET='11;X=V2:14.0' run
different "$CAPTURE" "$scratch/separators"
echo 'PASS embedded separators/newlines unambiguous'
MACOSX_DEPLOYMENT_TARGET=11.0 run
cmp "$CAPTURE" "$scratch/11"
echo 'PASS return11 recomputes identical held key'
MACOSX_DEPLOYMENT_TARGET='' MACOSX_DEPLOYMENT_TARGET_FOR_TARGET='' run
different "$CAPTURE" "$scratch/empty"
echo 'PASS empty suffix differs from absent suffix'
