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

@test "actions lists the six hub actions, machine name in field 1" {
  run "$CLI" actions
  [ "$status" -eq 0 ]
  local rows; rows=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
  [ "$rows" -eq 6 ]
  # Field 1 (tab-delimited) is the machine name the shell dispatcher re-runs;
  # pin the catalog so any add/remove forces a deliberate test update.
  local names; names=$(printf '%s\n' "$output" | cut -f1 | tr '\n' ' ')
  [ "$names" = "pick list auto reload preview contrast " ]
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
