#!/usr/bin/env bash
# Direct selected compiler execution; callers own producer identity and admission.
set -euo pipefail
refuse() { printf '%s\n' "toolkit-cargo-remap: $1" >&2 || :; exit 2; }
[[ $# -ge 8 && $1 == --compiler && $3 == --from && $5 == --to && $7 == -- ]] ||
  refuse 'expected --compiler ABS --from ABS --to ABS -- ORIGINAL_COMPILER [ARGS...]'
selected=$2 from=$4 destination=$6
shift 7
[[ $selected == /* && -f $selected && -x $selected ]] || refuse 'selected absolute compiler unavailable'
[[ $from == /* && $from != / && $destination == /* ]] || refuse 'absolute remap roots required; source root must not be /'
[[ $1 == rustc || $1 == "$selected" ]] || refuse 'original compiler differs from selected compiler'
shift
exec "$selected" "--remap-path-prefix=$from=$destination" "$@"
