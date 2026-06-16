#!/usr/bin/env bats
# Palette data integrity. The light variant must mirror default's family set and
# order — the hash maps key -> families[hash % N], so reordering would land the
# same directory on a different family and switching themes would reshuffle every
# workspace's hue. And every shade — light or dark — must stay readable against
# its theme's text: both palettes clear the APCA |Lc| 60 floor, and light.tsv
# additionally clears WCAG body text.

load helper

# family names, in file order, one per line.
fam_column() {
  awk -F'\t' '$1 != "" && $1 != "family" && $1 !~ /^#/ { print $1 }' "$1"
}

@test "light.tsv mirrors default.tsv's families in the same order" {
  [ -f "$REPO_ROOT/palettes/light.tsv" ]
  d="$(fam_column "$REPO_ROOT/palettes/default.tsv")"
  l="$(fam_column "$REPO_ROOT/palettes/light.tsv")"
  [ "$d" = "$l" ]
}

@test "light.tsv is in sync with its generator (no stale shades)" {
  # Order-parity above only catches family-level drift; this catches a shade
  # edited in default.tsv without regenerating light.tsv. Regenerate to a temp
  # file (never the tracked one) and diff.
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  tmp="$(mktemp)"
  python3 "$REPO_ROOT/scripts/gen-light-palette.py" "$tmp" >/dev/null
  run diff "$REPO_ROOT/palettes/light.tsv" "$tmp"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
}

@test "every light.tsv row is 5 columns of #rrggbb hex" {
  # Portable: no ERE interval expressions ({6}) — BSD awk support is patchy.
  run awk -F'\t' '
    $1 != "" && $1 != "family" && $1 !~ /^#/ {
      if (NF != 5) { print "cols", $1, NF; bad=1 }
      for (i=2; i<=5; i++) {
        h=$i
        if (h !~ /^#/ || length(h) != 7 || substr(h,2) ~ /[^0-9a-fA-F]/) {
          print "hex", $1, h; bad=1
        }
      }
    }
    END { exit bad+0 }
  ' "$REPO_ROOT/palettes/light.tsv"
  [ "$status" -eq 0 ]
}

@test "light.tsv clears WCAG body text against dark foregrounds" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  run "$REPO_ROOT/scripts/contrast-check.sh" "$REPO_ROOT/palettes/light.tsv" light
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 unreadable, 0 marginal"* ]]
}

@test "contrast-check auto-detects the light palette as light" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  run "$REPO_ROOT/scripts/contrast-check.sh" "$REPO_ROOT/palettes/light.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"theme:   light background"* ]]
}

@test "contrast-check auto-detects the default palette as dark" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  run "$REPO_ROOT/scripts/contrast-check.sh" "$REPO_ROOT/palettes/default.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"theme:   dark background"* ]]
}

@test "contrast-check rejects an invalid theme argument" {
  run "$REPO_ROOT/scripts/contrast-check.sh" "$REPO_ROOT/palettes/light.tsv" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"theme must be"* ]]
}

# The dark palette has no generated mirror to keep it honest, so guard its tints
# directly: the APCA |Lc| of the dimmest light text (#d0d0d0) against every shade
# must clear 60 (the large-UI floor). This is the "Grenze" round 8 set after the
# saturated green/teal/yellow mid-shades read too faint on the tint.
@test "default.tsv clears the APCA 60 readability floor" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  run python3 "$REPO_ROOT/scripts/contrast.py" "$REPO_ROOT/palettes/default.tsv" dark --check-floor 60
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 below floor"* ]]
}

# light.tsv is generated to a WCAG luminance ladder; pin the same APCA floor so a
# generator tweak (or a default.tsv hue edit it derives from) can't quietly drop
# the deepest tint below readable against dark text.
@test "light.tsv clears the APCA 60 readability floor" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  run python3 "$REPO_ROOT/scripts/contrast.py" "$REPO_ROOT/palettes/light.tsv" light --check-floor 60
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 below floor"* ]]
}

@test "the APCA floor guard reports violations (teeth: nothing clears 90)" {
  # No tint reaches |Lc| 90 against dimmed text (the near-blacks top out near 80),
  # so this proves the guard flags offenders and exits 1, not vacuously 0.
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  run python3 "$REPO_ROOT/scripts/contrast.py" "$REPO_ROOT/palettes/default.tsv" dark --check-floor 90
  [ "$status" -eq 1 ]
  [[ "$output" == *"below floor"* ]]
}

@test "--check-floor rejects a non-numeric argument" {
  run python3 "$REPO_ROOT/scripts/contrast.py" "$REPO_ROOT/palettes/default.tsv" dark --check-floor abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs a number"* ]]
}
