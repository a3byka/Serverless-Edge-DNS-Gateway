#!/bin/bash
# Daily sync of rules/hosts_rules.txt from the GeoHide EU hosts list.
# - Downloads upstream list, validates it (refuses to overwrite on bad/short download)
# - Appends optional rules/hosts_custom.txt (custom lines override upstream for the same domain)
# - Replaces rules/hosts_rules.txt ONLY if the real content (ignoring comments/blank lines) changed

set -euo pipefail

DIR="rules"
OUT="./$DIR/hosts_rules.txt"
CUSTOM="./$DIR/hosts_custom.txt"
UPSTREAM_URL="${UPSTREAM_URL:-https://raw.githubusercontent.com/Internet-Helper/GeoHideDNS/refs/heads/main/hosts/eu/hosts}"
MIN_ENTRIES="${MIN_ENTRIES:-500}"   # sanity check: upstream currently has ~7000 entries

RAW_TMP="$(mktemp)"
NEW_TMP="$(mktemp)"
trap 'rm -f "$RAW_TMP" "$NEW_TMP" "$NEW_TMP.norm" "$OUT.norm.old"; exit' INT TERM EXIT

mkdir -p "./$DIR"

echo "Downloading upstream hosts list..."
curl -fsSL --max-time 60 "$UPSTREAM_URL" | tr -d '\r' > "$RAW_TMP"

# Count valid "IP domain" entries
ENTRIES=$(awk '{sub(/#.*/,""); if (NF>=2 && ($1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ || $1 ~ /:/)) n++} END{print n+0}' "$RAW_TMP")
echo "Upstream entries: $ENTRIES"
if [ "$ENTRIES" -lt "$MIN_ENTRIES" ]; then
  echo "ERROR: upstream list looks broken (only $ENTRIES entries, expected >= $MIN_ENTRIES). Keeping the current file." >&2
  exit 1
fi

# Build the new file: upstream (minus domains overridden by custom) + custom
if [ -s "$CUSTOM" ]; then
  tr -d '\r' < "$CUSTOM" > "$NEW_TMP.custom"
  awk '
    NR==FNR { line=$0; sub(/#.*/,"",line); n=split(line,a,/[ \t]+/);
              for (i=1;i<=n;i++) if (a[i]!="" && i>1) skip[tolower(a[i])]=1; next }
    { line=$0; sub(/#.*/,"",line); n=split(line,a,/[ \t]+/); drop=0;
      for (i=1;i<=n;i++) if (i>1 && a[i]!="" && (tolower(a[i]) in skip)) drop=1;
      if (!drop) print $0 }
  ' "$NEW_TMP.custom" "$RAW_TMP" > "$NEW_TMP"
  { echo; echo "# ---- custom rules (rules/hosts_custom.txt) ----"; cat "$NEW_TMP.custom"; } >> "$NEW_TMP"
  rm -f "$NEW_TMP.custom"
else
  cp "$RAW_TMP" "$NEW_TMP"
fi

# Normalize (drop comments, blank lines, extra spaces) to compare real content only
normalize() { awk '{sub(/#.*/,""); gsub(/^[ \t]+|[ \t]+$/,""); if ($0!="") print}' "$1"; }

if [ -f "$OUT" ] && [ "$(normalize "$OUT" | sha256sum)" = "$(normalize "$NEW_TMP" | sha256sum)" ]; then
  echo "No changes in hosts list. Nothing to do."
  exit 0
fi

mv "$NEW_TMP" "$OUT"
echo "Updated $OUT"
