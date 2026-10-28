#!/usr/bin/env bash
# usage: gen_dtb.sh csr.json out.dtb      env: DTS_SRC (optional), DTS_ARGS (optional)
set -euo pipefail
CSR="$1"; DTB="$2"; DTS="${DTB%.dtb}.dts"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "${DTS_SRC:-}" ] && [ -f "$DTS_SRC" ]; then
  echo "using ready-made DTS: $DTS_SRC"
  cp "$DTS_SRC" "$DTS"
else
  echo "generating DTS from $CSR"
  # shellcheck disable=SC2086
  litex_json2dts_linux ${DTS_ARGS:-} "$CSR" > "$DTS"
fi

# optional fixes: put sed scripts in dts/*.sed (e.g. remove the duplicate reserved-memory node)
for p in "$HERE"/../dts/*.sed; do
  if [ -e "$p" ]; then echo "applying $(basename "$p")"; sed -i -f "$p" "$DTS"; fi
done

dtc -I dts -O dtb -o "$DTB" "$DTS"
echo "wrote $DTB"
