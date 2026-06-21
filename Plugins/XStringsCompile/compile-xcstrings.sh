#!/bin/bash
set -euo pipefail
OUTDIR="$1"; CATALOG="$2"
/usr/bin/xcrun xcstringstool compile --output-directory "$OUTDIR" "$CATALOG"
for lang in en ru; do
  mkdir -p "$OUTDIR/$lang.lproj"
  [ -f "$OUTDIR/$lang.lproj/Localizable.strings" ] || : > "$OUTDIR/$lang.lproj/Localizable.strings"
  [ -f "$OUTDIR/$lang.lproj/Localizable.stringsdict" ] || \
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n' \
      > "$OUTDIR/$lang.lproj/Localizable.stringsdict"
done
