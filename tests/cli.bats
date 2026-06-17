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

@test "palette-for emits a normalized path (no bin/.. for string-equality)" {
  # The plugin compares this output by STRING against its own canonical palettes/
  # dir (the picker's dark/light group check). A bin/../palettes/… form would
  # differ and silently drop the ctrl-t toggle after a commit, so guard it here.
  run "$CLI" palette-for light
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO_ROOT/palettes/light.tsv" ]
  [[ "$output" != *"/../"* ]]
  run "$CLI" palette-for dark
  [ "$output" = "$REPO_ROOT/palettes/default.tsv" ]
}

@test "preview-family renders a known family" {
  run "$CLI" preview-family blue
  [ "$status" -eq 0 ]
  # Banner is "<mode> · <theme> · <family>" — mode + family must show.
  [[ "$output" == *"swatch"* ]]
  [[ "$output" == *"blue"* ]]
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

@test "live-preview lift tone is lighter than shade3" {
  # Mirror of the dim test for light palettes: shade3 #e5eaf6 at 50% toward white.
  source <(sed -n '/^_pt_lift_hex()/,/^}/p' "$CLI")
  run _pt_lift_hex "#e5eaf6" 50
  [ "$status" -eq 0 ]
  [ "$output" = "#f2f4fa" ]
}

@test "is-light-hex classifies light vs dark colors" {
  source <(sed -n '/^_pt_lum()/,/^}/p;/^_pt_is_light_hex()/,/^}/p' "$CLI")
  run _pt_is_light_hex "#a8b8e2"   # pale light-palette shade0
  [ "$status" -eq 0 ]
  run _pt_is_light_hex "#001f70"   # dark default shade0
  [ "$status" -eq 1 ]
}

@test "focus tone dims on the dark palette, lifts on the light one" {
  # The hover background must not darken a light terminal theme under the user's
  # dark text: on the light palette it lifts the lightest shade toward white, on
  # the dark default it keeps dimming the darkest toward black (no regression).
  source <(sed -n '/^_pt_lum()/,/^}/p;/^_pt_valid_hex()/,/^}/p;/^shades_for()/,/^}/p;/^_pt_dim_hex()/,/^}/p;/^_pt_lift_hex()/,/^}/p;/^_pt_is_light_hex()/,/^}/p;/^_pt_focus_tone()/,/^}/p' "$CLI")
  PALETTE="$PWDTINTII_PALETTE"
  run _pt_focus_tone blue
  [ "$status" -eq 0 ]
  [ "$output" = "#000f38" ]
  PALETTE="$REPO_ROOT/palettes/light.tsv"
  run _pt_focus_tone blue
  [ "$status" -eq 0 ]
  [ "$output" = "#f2f4fa" ]
}

@test "focus tone is order-independent (lifts the lightest even if shades run light→dark)" {
  # A palette whose four shades run light→dark must still lift its *lightest*
  # shade (chosen by luminance, not position) so the hover tone sits above all
  # four. The old position-based code keyed on shade0 and lifted shade3 — here
  # the darkest — producing a tone below shade0.
  source <(sed -n '/^_pt_lum()/,/^}/p;/^_pt_valid_hex()/,/^}/p;/^shades_for()/,/^}/p;/^_pt_dim_hex()/,/^}/p;/^_pt_lift_hex()/,/^}/p;/^_pt_is_light_hex()/,/^}/p;/^_pt_focus_tone()/,/^}/p' "$CLI")
  printf 'reversed\t#e5eaf6\t#d5ddf1\t#c0cbea\t#a8b8e2\n' > "$TEST_HOME/rev.tsv"
  PALETTE="$TEST_HOME/rev.tsv"
  run _pt_focus_tone reversed
  [ "$status" -eq 0 ]
  [ "$output" = "#f2f4fa" ]   # lift of the lightest (#e5eaf6), not of shade3
}

@test "preview text tone flips to dark on a light band, light on a dark band" {
  # The picker preview must read on the light palette too: a pale band gets a
  # dim-dark ghost + near-black label, a dark band keeps the light tones (so the
  # default palette is byte-identical — no regression). _pt_text_fg returns via
  # the _PT_FG global (fork-free on the focus hot path), so assert that directly.
  source <(sed -n '/^_pt_lum()/,/^}/p;/^_pt_text_fg()/,/^}/p' "$CLI")
  _pt_text_fg 229 234 246   # a pale light-palette shade (lum ~233)
  [ "$_PT_FG" = "72 72 72 16 16 16" ]
  _pt_text_fg 0 31 112      # blue shade0 from the dark default (lum ~26)
  [ "$_PT_FG" = "220 220 220 235 235 235" ]
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

@test "preview-family rejects a malformed shade instead of crashing" {
  # A custom palette reaches the CLI unvalidated (only the plugin loader checks),
  # so a malformed cell must fail loudly — not crash hex_to_rgb's 16#/printf
  # under set -euo pipefail.
  printf 'rust\t#aa3300\tNOTHEX\t#cc5522\t#dd6633\n' > "$TEST_HOME/bad.tsv"
  run env PWDTINTII_PALETTE="$TEST_HOME/bad.tsv" "$CLI" preview-family rust
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed shade"* ]]
}

@test "emit-family is a no-op on a malformed shade (no set -e crash)" {
  printf 'rust\t#aa3300\tNOTHEX\t#cc5522\t#dd6633\n' > "$TEST_HOME/bad.tsv"
  run env PWDTINTII_PALETTE="$TEST_HOME/bad.tsv" "$CLI" emit-family rust
  [ "$status" -eq 0 ]   # the bad cell short-circuits _pt_focus_tone, no abort
}

@test "actions lists the seven hub actions, machine name in field 1" {
  run "$CLI" actions
  [ "$status" -eq 0 ]
  local rows; rows=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
  [ "$rows" -eq 7 ]
  # Field 1 (tab-delimited) is the machine name the shell dispatcher re-runs;
  # pin the catalog so any add/remove forces a deliberate test update.
  local names; names=$(printf '%s\n' "$output" | cut -f1 | tr '\n' ' ')
  [ "$names" = "pick view list auto off reload contrast " ]
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

@test "describe-action renders the view action" {
  run "$CLI" describe-action view
  [ "$status" -eq 0 ]
  [[ "$output" == *"browse the palette"* ]]
  [[ "$output" == *"ptview"* ]]
}

# ── menu chrome: list-menu (--ansi list) + fzf-theme (--color) + pick-header ──
# The fzf menus sit on the OSC-11 tint. list-menu colors each row per-line so a
# ctrl-t reload reflows it dark<->light (flips by the palette's mean luminance).
# The picker's --color chrome (fzf-theme) is theme-NEUTRAL: --color is static per
# fzf session but the picker toggles the tint dark<->light within one session, so
# a mid-gray that reads on either tint is the only thing that survives the toggle.
# Only the header reflows — it carries its own ANSI color (pick-header).

@test "list-menu colors every family with near-white text on the dark palette" {
  run "$CLI" list-menu
  [ "$status" -eq 0 ]
  [[ "$output" == *"blue"* ]]
  [[ "$output" == *"charcoal"* ]]
  [[ "$output" == *"38;2;233;236;240"* ]]   # near-white SGR wraps each row
}

@test "list-menu flips to near-black text on the light palette" {
  run env PWDTINTII_PALETTE="$REPO_ROOT/palettes/light.tsv" "$CLI" list-menu
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;2;22;26;31"* ]]
  [[ "$output" != *"38;2;233;236;240"* ]]
}

@test "fzf-theme is theme-neutral: identical gray chrome for both palettes" {
  run "$CLI" fzf-theme
  [ "$status" -eq 0 ]
  local dark_spec="$output"
  [[ "$dark_spec" == *"bg+:#777d86"* ]]     # focused-row block is mid-gray, reads on either tint
  [[ "$dark_spec" == *"prompt:#777d86"* ]]
  [[ "$dark_spec" == *"separator:#777d86"* ]]   # pinned so the terminal default fg can't leak
  run env PWDTINTII_PALETTE="$REPO_ROOT/palettes/light.tsv" "$CLI" fzf-theme
  [ "$status" -eq 0 ]
  [ "$output" = "$dark_spec" ]              # static --color can't reflow → must not depend on the palette
}

@test "pick-header colors the header near-white on the dark palette" {
  run "$CLI" pick-header "ENTER pin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;2;233;236;240"* ]]   # near-white HI, embedded so the header reflows on ctrl-t
  [[ "$output" == *"ENTER pin"* ]]
}

@test "pick-header flips to near-black on the light palette" {
  run env PWDTINTII_PALETTE="$REPO_ROOT/palettes/light.tsv" "$CLI" pick-header "ENTER pin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"38;2;22;26;31"* ]]      # near-black HI
  [[ "$output" != *"38;2;233;236;240"* ]]
}

@test "pick-toggle flips the group and reflows the picker frame in place" {
  # ctrl-t swaps the picker's dark<->light group without restarting fzf: it flips
  # the group in the state dir and emits reload + change-preview/header/prompt +
  # refresh-preview for the new palette. It no longer emits the OSC tint itself —
  # the ctrl-t bind chains a coordinated execute-silent(emit-family) after this
  # transform (a raw write here raced fzf's renderer and was dropped), so all we
  # assert is the well-formed action chain and the flipped group + recorded palette.
  local sd="$TEST_HOME/pstate"; mkdir -p "$sd"
  printf 'dark\n' > "$sd/grp"
  printf '%s\n' "$REPO_ROOT/palettes/default.tsv" > "$sd/pal"
  run "$CLI" pick-toggle "$sd"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reload("* ]]
  [[ "$output" == *"list-menu"* ]]
  [[ "$output" == *"change-preview("* ]]
  [[ "$output" == *"change-header("* ]]
  [[ "$output" == *"change-prompt("* ]]
  [[ "$output" == *"+refresh-preview"* ]]
  [[ "$output" == *"light.tsv"* ]]          # toggled dark -> light
  [ "$(cat "$sd/grp")" = "light" ]          # group flipped in the state dir
  [ "$(cat "$sd/pal")" = "$REPO_ROOT/palettes/light.tsv" ]   # new palette recorded for the execute-silent emit
}

@test "view exits cleanly and removes its tempdir (fzf stubbed)" {
  # Regression: cmd_view cleaned its tempdir via an EXIT trap over a `local sd`,
  # which fires after the function returns — under set -u that aborted with
  # 'sd: unbound variable' on exit and leaked the dir. With fzf stubbed to exit 0
  # the full mktemp+pipeline path runs, then the script exits: assert no
  # unbound-var error and no net new pwdtintii-view.* dir.
  local stub="$TEST_HOME/bin"; mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'cat >/dev/null 2>&1; exit 0' > "$stub/fzf"; chmod +x "$stub/fzf"
  local before after
  before=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'pwdtintii-view.*' 2>/dev/null | wc -l | tr -d ' ')
  run env PATH="$stub:$PATH" PWDTINTII_VIEW_FAMILY=blue PWDTINTII_VIEW_SHADE=0 "$CLI" view
  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
  after=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'pwdtintii-view.*' 2>/dev/null | wc -l | tr -d ' ')
  [ "$after" -le "$before" ]
}

@test "view-advance reflows the whole frame: reload, header, preview, refresh" {
  # ctrl-t advances the cycle and repaints everything for the new state's theme:
  # reload (the --ansi list colors reflow dark<->light), change-header (the
  # header's own ANSI color), change-preview + refresh-preview (swap the pane and
  # run it now — not after the next arrow key). State 1 here is the light palette.
  # The backdrop flip is no longer written here: it records the new palette in
  # $sd/pal and the ctrl-t bind chains a coordinated execute-silent(emit-backdrop
  # $sd/pal) after this transform (a raw OSC write here raced fzf's renderer). Also
  # advances + wraps the index.
  local sd="$TEST_HOME/vstate"; mkdir -p "$sd"
  printf '0\n' > "$sd/idx"
  printf '%s\tpreview-family\n%s\tpreview-contrast\n' \
    "$REPO_ROOT/palettes/default.tsv" "$REPO_ROOT/palettes/light.tsv" > "$sd/states"
  run "$CLI" view-advance "$sd"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reload("* ]]
  [[ "$output" == *"list-menu"* ]]
  [[ "$output" == *"change-preview("* ]]
  [[ "$output" == *"change-header("* ]]
  [[ "$output" == *"+refresh-preview"* ]]
  [[ "$output" == *"light.tsv"* ]]
  [ "$(cat "$sd/idx")" -eq 1 ]
  [ "$(cat "$sd/pal")" = "$REPO_ROOT/palettes/light.tsv" ]   # new palette recorded for the execute-silent backdrop emit
}

@test "view backdrop is a dark neutral for the dark palette, light for the light one" {
  # The viewer tints the terminal to a deliberate dark default and flips it to a
  # light neutral on ctrl-t, so the global background tracks the dark/light cycle
  # instead of a light preview floating in a dark frame.
  source <(sed -n '/^_pt_palette_is_light()/,/^}/p;/^_pt_view_backdrop()/,/^}/p' "$CLI")
  PALETTE="$PWDTINTII_PALETTE"
  run _pt_view_backdrop "$REPO_ROOT/palettes/default.tsv"
  [ "$status" -eq 0 ]
  [ "$output" = "#16191f" ]
  run _pt_view_backdrop "$REPO_ROOT/palettes/light.tsv"
  [ "$status" -eq 0 ]
  [ "$output" = "#e8eaee" ]
}

@test "emit-restore is a no-op without a view family" {
  run "$CLI" emit-restore
  [ "$status" -eq 0 ]
}

@test "emit-restore exits cleanly with a view family set" {
  # It emits the shell's tint to /dev/tty (suppressed when there's no tty), so we
  # can only assert it doesn't crash under set -euo pipefail — the structural twin
  # of emit-family's no-op test.
  run env PWDTINTII_VIEW_FAMILY=blue PWDTINTII_VIEW_SHADE=2 "$CLI" emit-restore
  [ "$status" -eq 0 ]
}

@test "emit-backdrop is a no-op without a palette arg" {
  # The viewer's ctrl-t chains execute-silent(emit-backdrop "$(cat $sd/pal)"); an
  # empty $sd/pal must short-circuit cleanly rather than emit a malformed OSC.
  run "$CLI" emit-backdrop
  [ "$status" -eq 0 ]
}

@test "emit-backdrop exits cleanly for a bundled palette" {
  # Emits the palette's viewer backdrop to /dev/tty (suppressed off-tty), so like
  # emit-restore we can only assert it survives set -euo pipefail.
  run "$CLI" emit-backdrop "$REPO_ROOT/palettes/light.tsv"
  [ "$status" -eq 0 ]
}

# ── scripts smoke (contrast) ─────────────────────────────────────────────────
# Ships as `pt contrast`; CI only shellchecked it before.

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
