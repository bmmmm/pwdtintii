#!/usr/bin/env bats
# CLI companion: bin/pwdtintii (drives the fzf preview pane).

load helper

setup() {
  setup_sandbox
  CLI="$REPO_ROOT/bin/pwdtintii"
}
teardown() { teardown_sandbox; }

@test "list prints every family from the palette" {
  run "$CLI" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"blue"* ]]
  [[ "$output" == *"charcoal"* ]]
  # header row must not leak in
  [[ "$output" != *"family"* ]]
}

@test "palette prints the resolved palette path" {
  run "$CLI" palette
  [ "$status" -eq 0 ]
  [ "$output" = "$PWDTINTII_PALETTE" ]
}

@test "preview-family renders a known family" {
  run "$CLI" preview-family blue
  [ "$status" -eq 0 ]
  [[ "$output" == *"family: blue"* ]]
}

@test "preview-family fills the pane to FZF_PREVIEW_LINES (no empty lower half)" {
  run env FZF_PREVIEW_LINES=30 FZF_PREVIEW_COLUMNS=50 "$CLI" preview-family blue
  [ "$status" -eq 0 ]
  # Count raw rows with wc -l: bats' $lines array drops the blank header/gap
  # rows, so the bands stretching to fill ~30 rows (vs a fixed ~18 that left the
  # lower half empty) only shows up in the raw line count.
  local rows; rows=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
  [ "$rows" -ge 28 ]
  [ "$rows" -le 30 ]
}

@test "preview-family fails on an unknown family" {
  run "$CLI" preview-family nosuchfamily
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown family"* ]]
}

@test "live-preview dim tone is darker than shade0" {
  # Unit-test the dimming used for the focus background: shade0 #001f70 at 50%.
  source <(sed -n '/^_pt_dim_hex()/,/^}/p' "$CLI")
  run _pt_dim_hex "#001f70" 50
  [ "$status" -eq 0 ]
  [ "$output" = "#000f38" ]
}

@test "preview text tone flips to dark on a light band, light on a dark band" {
  # The picker preview must read on the light palette too: a pale band gets a
  # dim-dark ghost + near-black label, a dark band keeps the light tones (so the
  # default palette is byte-identical — no regression).
  source <(sed -n '/^_pt_text_fg()/,/^}/p' "$CLI")
  run _pt_text_fg 229 234 246   # a pale light-palette shade (lum ~233)
  [ "$status" -eq 0 ]
  [ "$output" = "72 72 72 16 16 16" ]
  run _pt_text_fg 0 31 112      # blue shade0 from the dark default (lum ~26)
  [ "$status" -eq 0 ]
  [ "$output" = "220 220 220 235 235 235" ]
}

@test "preview-family uses high-contrast dark text on the light palette" {
  # End-to-end through the real renderer: on the light palette the label row
  # carries the near-black SGR, never the dark-palette near-white.
  run env PWDTINTII_PALETTE="$REPO_ROOT/palettes/light.tsv" "$CLI" preview-family blue
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;2;16;16;16"* ]]
  [[ "$output" != *"38;2;235;235;235"* ]]
}

@test "preview-family keeps light text on the dark default palette" {
  run "$CLI" preview-family blue
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;2;235;235;235"* ]]
  [[ "$output" != *"38;2;16;16;16"* ]]
}

@test "actions lists the seven hub actions, machine name in field 1" {
  run "$CLI" actions
  [ "$status" -eq 0 ]
  local rows; rows=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
  [ "$rows" -eq 7 ]
  # Field 1 (tab-delimited) is the machine name the shell dispatcher re-runs;
  # pin the catalog so any add/remove forces a deliberate test update.
  local names; names=$(printf '%s\n' "$output" | cut -f1 | tr '\n' ' ')
  [ "$names" = "pick list auto off reload preview contrast " ]
}

@test "describe-action renders a known action" {
  run "$CLI" describe-action pick
  [ "$status" -eq 0 ]
  [[ "$output" == *"pin a color family"* ]]
  [[ "$output" == *"ptpick"* ]]
}

@test "describe-action is graceful on an unknown action" {
  run "$CLI" describe-action zzz
  [ "$status" -eq 0 ]
  [[ "$output" == *"no description"* ]]
}

@test "describe-action renders the off action" {
  run "$CLI" describe-action off
  [ "$status" -eq 0 ]
  [[ "$output" == *"stop tinting"* ]]
  [[ "$output" == *"OSC 111"* ]]
}

# ── scripts smoke (preview + contrast) ───────────────────────────────────────
# These ship as `pt preview` / `pt contrast`; CI only shellchecked them before.

@test "preview script runs over the palette" {
  run "$REPO_ROOT/scripts/preview.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Palette:"* ]]
}

@test "contrast-check runs and prints a summary" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  run "$REPO_ROOT/scripts/contrast-check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Summary:"* ]]
}

@test "unknown subcommand exits non-zero" {
  run "$CLI" frobnicate
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown subcommand"* ]]
}

@test "no args prints help" {
  run "$CLI"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Subcommands"* ]]
}

@test "missing palette fails with an actionable message" {
  run env PWDTINTII_PALETTE="$TEST_HOME/nope.tsv" "$CLI" list
  [ "$status" -eq 1 ]
  [[ "$output" == *"palette not found"* ]]
}
