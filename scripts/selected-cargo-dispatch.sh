#!/usr/bin/env bash
# Repository adapters supply original selected tools and their opt-out policy.
set -euo pipefail
cargo='' clippy='' cache='' bypass='' formatter=''
while (( $# )); do
 case $1 in
  --cargo|--clippy|--selected-cache|--cache-bypass|--fmt)
   (( $# >= 2 )) || exit 2
   case $1 in --cargo) cargo=$2;; --clippy) clippy=$2;; --selected-cache) cache=$2;; --cache-bypass) bypass=$2;; --fmt) formatter=$2;; esac
   shift 2;;
  --) shift; break;;
  *) echo 'selected cargo dispatch: unknown adapter option' >&2; exit 2;;
 esac
done
[[ $cargo == /* && $clippy == /* && $cache == /* && ( $bypass == 0 || $bypass == 1 ) ]] || { echo 'selected cargo dispatch: explicit selected tools and bypass required' >&2; exit 2; }
selected=${RUSTC_WRAPPER:-}
if [[ $selected == sccache ]]; then
 native=0
 selected=$(command -v sccache) || native=$?
 if (( native != 0 && native != 1 )); then exit "$native"; fi
fi
if [[ $selected == "$cache" ]]; then
 if [[ $bypass == 1 ]]; then
  unset RUSTC_WRAPPER
 else
  # v0.11 Rust keys hash CARGO_* inputs; raw Apple deployment env is not keyed.
  # Recompute the reserved projection: inherited self-certified markers are inert.
  names=$(printf '%s\n' MACOSX_DEPLOYMENT_TARGET IPHONEOS_DEPLOYMENT_TARGET TVOS_DEPLOYMENT_TARGET WATCHOS_DEPLOYMENT_TARGET XROS_DEPLOYMENT_TARGET \
    ${!MACOSX_DEPLOYMENT_TARGET_@} ${!IPHONEOS_DEPLOYMENT_TARGET_@} ${!TVOS_DEPLOYMENT_TARGET_@} ${!WATCHOS_DEPLOYMENT_TARGET_@} ${!XROS_DEPLOYMENT_TARGET_@} | LC_ALL=C sort -u)
  projection='toolkit-apple-deployment-v1;'
  while IFS= read -r name; do
   if [[ ${!name+x} ]]; then
    value=${!name}
    # Byte lengths make absent, empty and arbitrary separator/newline values distinct.
    value_length=$(LC_ALL=C; printf '%s' "${#value}")
    projection+="${#name}:$name=V$value_length:$value;"
   else
    projection+="${#name}:$name=A;"
   fi
  done <<< "$names"
  export CARGO_TOOLKIT_APPLE_DEPLOYMENT_V1=$projection
 fi
fi

case ${1:-} in
 clippy) exec "$clippy" "$@";;
 fmt) if [[ -n $formatter ]]; then [[ $formatter == /* ]] || exit 2; exec "$formatter" "$@"; fi;;
esac
exec "$cargo" "$@"
