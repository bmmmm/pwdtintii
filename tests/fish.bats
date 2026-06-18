#!/usr/bin/env bats
# The fish plugin is a native third shell. It must resolve identical keys,
# families, registry hashes and emitted OSC-11 hex to bash/zsh — otherwise the
# same directory tints differently in fish, or a fish shell collides with a
# bash/zsh shell in the same dir over a shade. bash<->zsh parity is pinned in
# parity.bats; these pin fish==bash, so transitively fish==zsh==bash.

load helper

setup() { need_fish; setup_sandbox; }
teardown() { teardown_sandbox; }

@test "fish plugin parses (fish -n)" {
  run "$FISH_BIN" -n "$REPO_ROOT/pwdtintii.plugin.fish"
  [ "$status" -eq 0 ]
}

# Hash → family mapping. family_for takes the key as an argument (no $PWD), so a
# spread of absolute keys can be compared directly against bash.
@test "fish family_for matches bash across a spread of keys (hash parity)" {
  need_bash
  local k b f
  for k in /opt /srv /var/lib/foo /testhome/work /testhome / /a/b/c /usr/local/bin; do
    b="$(bash_eval / / '_pwdtintii_family_for "'"$k"'"')"
    f="$(fish_eval '_pwdtintii_family_for "'"$k"'"')"
    [ -n "$b" ]
    [ "$b" = "$f" ]
  done
}

# default_key resolves $PWD → key. fish can't fake $PWD, so use real temp dirs and
# `cd`; bash gets the same real paths (PWD=). Both branches: git-root + first
# component under HOME.
@test "fish default_key matches bash (real dirs: under-HOME + git-root)" {
  need_bash
  mkdir -p "$TEST_HOME/work/repo/deep" "$TEST_HOME/proj/.git" "$TEST_HOME/proj/sub"
  local b f
  b="$(bash_eval "$TEST_HOME" "$TEST_HOME/work/repo/deep" '_pwdtintii_default_key')"
  f="$(fish_eval 'set -g HOME "'"$TEST_HOME"'"; cd "'"$TEST_HOME"'/work/repo/deep"; _pwdtintii_default_key')"
  [ -n "$b" ]
  [ "$b" = "$f" ]
  b="$(bash_eval "$TEST_HOME" "$TEST_HOME/proj/sub" '_pwdtintii_default_key')"
  f="$(fish_eval 'set -g HOME "'"$TEST_HOME"'"; cd "'"$TEST_HOME"'/proj/sub"; _pwdtintii_default_key')"
  [ -n "$b" ]
  [ "$b" = "$f" ]
}

@test "fish registry keyhash matches bash" {
  need_bash
  local key="/testhome/projects/app"
  local hb hf
  hb="$(bash_eval / / 'printf "%s" "'"$key"'" | $_PWDTINTII_HASHCMD | cut -c1-12')"
  hf="$(fish_eval 'printf "%s" "'"$key"'" | $_PWDTINTII_HASHCMD | cut -c1-12')"
  [ -n "$hb" ]
  [ "$hb" = "$hf" ]
}

# The load-bearing index-base invariant: bash apply emits ${shades[$shade_idx]}
# (0-based), fish emits $shades[(math $shade_idx + 1)] (1-based, like zsh). For a
# given (family, shade) the OSC-11 hex MUST be byte-identical, else the same dir
# tints differently in fish.
@test "fish emitted OSC-11 hex is byte-identical to bash (apply index base)" {
  need_bash
  local b f
  b="$(bash_emit_shades /testhome /testhome/x blue)"
  f="$(fish_emit_shades blue)"
  [ -n "$b" ]
  [ "$b" = "$f" ]
  # Teeth: four distinct shades, so it can't pass vacuously on a uniform emit.
  [ "$(printf '%s\n' "$f" | sort -u | grep -c .)" -eq 4 ]
}

@test "fish emitted OSC-11 hex parity holds for a second family (charcoal)" {
  need_bash
  [ "$(bash_emit_shades /testhome /testhome/x charcoal)" = "$(fish_emit_shades charcoal)" ]
}

# list carries hand-mirrored text just like the bash/zsh pair. $PWD can't be faked
# in fish, so pin the key fn to a stub in both shells for a deterministic key.
@test "fish list output matches bash (stubbed key fn)" {
  need_bash
  local b f
  b="$(bash_eval / / 'function _pt_stub { printf "%s\n" /testhome/proj; }; PWDTINTII_DIR_KEY_FN=_pt_stub; pwdtintii_list')"
  f="$(fish_eval 'function _pt_stub; printf "%s\n" /testhome/proj; end; set -g PWDTINTII_DIR_KEY_FN _pt_stub; pwdtintii_list')"
  [ -n "$b" ]
  [ "$b" = "$f" ]
}

@test "fish help text matches bash" {
  need_bash
  [ "$(bash_eval /testhome / 'pwdtintii help')" = "$(fish_eval 'pwdtintii help')" ]
}

@test "fish dispatcher rejects an unknown command" {
  run fish_eval 'pwdtintii frobnicate 2>&1; echo "rc=$status"'
  [[ "$output" == *"unknown command"* ]]
  [[ "$output" == *"rc=1"* ]]
}

# pwdtintii_pick must reject an unknown family (rc 1 + message) and pin a valid
# one. fish has no command substitution inside double quotes, so the guard reads
# the shades into a var first — an earlier `test -z "(...)"` form took the parens
# literally and silently accepted every name. The unknown-family text also matches
# bash, so the error reads the same regardless of shell.
@test "fish pick rejects an unknown family and pins a valid one (+ error parity)" {
  need_bash
  run fish_eval 'pwdtintii_pick bogusfam 2>&1; echo "rc=$status"'
  [[ "$output" == *"unknown family: bogusfam"* ]]
  [[ "$output" == *"rc=1"* ]]
  run fish_eval 'pwdtintii_pick blue >/dev/null 2>&1; echo "forced=$_PWDTINTII_FORCED_FAMILY rc=$status"'
  [[ "$output" == *"forced=blue"* ]]
  [[ "$output" == *"rc=0"* ]]
  local b f
  b="$(bash_eval / / 'pwdtintii_pick bogusfam 2>&1 || true')"
  f="$(fish_eval 'pwdtintii_pick bogusfam 2>&1; true')"
  [ "$b" = "$f" ]
}

# The prompt hook hands $status back untouched so a prompt reading the last
# command's exit status sees it, not pwdtintii_apply's.
@test "fish precmd hook preserves \$status" {
  run fish_eval 'function _r; return 42; end; _r; _pwdtintii_precmd >/dev/null 2>&1; echo "rc=$status"'
  [[ "$output" == *"rc=42"* ]]
}

# A hand-edited palette without a trailing newline must not silently lose its last
# family — the loader reads raw (no grep/sed to re-add the \n), so the
# `|| test -n "$family"` last-line guard must hold in fish too.
@test "fish palette load keeps a newline-less last family" {
  printf 'aaa\t#001f70\t#002d8f\t#0a38a8\t#1442c0\n' >  "$TEST_HOME/nonl.tsv"
  printf 'zzz\t#701f00\t#8f2d00\t#a8380a\t#c04214'   >> "$TEST_HOME/nonl.tsv"
  local out
  out="$(PWDTINTII_PALETTE="$TEST_HOME/nonl.tsv" fish_eval 'printf "%s\n" $_pwdtintii_families')"
  [[ "$out" == *"aaa"* && "$out" == *"zzz"* ]]
}

# The picker's dark/light toggle commits through _pwdtintii_set_palette; the
# bash/zsh sides are pinned in plugin.bats/parity.bats, this guards fish.
@test "fish set_palette switches the active palette (light shades differ)" {
  run fish_eval '
    set -l dark (_pwdtintii_shades_for blue)
    _pwdtintii_set_palette "$_pwdtintii_self/palettes/light.tsv"
    set -l light (_pwdtintii_shades_for blue)
    string match -q "*/light.tsv" -- "$PWDTINTII_PALETTE"; and echo pal-ok
    test -n "$light"; and test "$dark" != "$light"; and echo shades-differ
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"pal-ok"* ]]
  [[ "$output" == *"shades-differ"* ]]
}

# `pt` self-heals a stale shell by re-sourcing before dispatching (parse-checked
# with `fish -n`); mirrors the zsh stale-reload test.
@test "fish pt auto-reloads a stale shell before dispatching" {
  run fish_eval '
    set -g _pwdtintii_families bogus
    set -g _PWDTINTII_LOADED_MTIME 1
    pwdtintii list >/dev/null 2>&1
    _pwdtintii_is_stale; and echo still-stale; or echo healed
    echo "count="(count $_pwdtintii_families)
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"healed"* ]]
  [[ "$output" == *"count=37"* ]]
}

# ── cross-shell shade registry ───────────────────────────────────────────────
@test "fish pick_shade reclaims a shade from a dead PID" {
  run fish_eval '
    mkdir -p "$PWDTINTII_SHADES_DIR"
    printf "999999\t0\t1\n" > "$PWDTINTII_SHADES_DIR/zz.tsv"
    _pwdtintii_pick_shade k "" zz'
  [ "$output" = "0" ]
}

# Live-PID coordination: a fish shell must avoid a shade another (live) shell holds
# under the SAME registry hash. Needs a real background process + kill -0, which
# the command sandbox blocks (nice/fork denied) — run on a real shell to confirm.
@test "fish pick_shade skips a shade held by a live PID" {
  mkdir -p "$PWDTINTII_SHADES_DIR"
  sleep 30 & local live=$!
  printf '%s\t0\t1\n' "$live" > "$PWDTINTII_SHADES_DIR/zz.tsv"
  run fish_eval '_pwdtintii_pick_shade k "" zz'
  kill "$live" 2>/dev/null
  [ "$output" = "1" ]
}

# ── tmux per-pane tinting ────────────────────────────────────────────────────
# Mock `tmux` on PATH logs its args; TMUX toggles the branch. Mirrors the bash
# tmux tests in plugin.bats.
@test "fish tmux: emit routes to select-pane, not OSC 11, when TMUX is set" {
  local stub="$TEST_HOME/stub_bin" log="$TEST_HOME/tmux.log"
  mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "'"$log"'"' 'exit 0' > "$stub/tmux"
  chmod +x "$stub/tmux"
  local out
  out="$(fish_eval 'set -gx PATH "'"$stub"'" $PATH; set -gx TMUX /fake/tmux,0,0; _pwdtintii_emit "#112233"')"
  [ -f "$log" ]
  grep -q 'select-pane' "$log"
  grep -q 'bg=#112233' "$log"
  local dump; dump="$(printf '%s' "$out" | od -An -tx1 | tr -d ' \n')"
  [[ "$dump" != *"1b5d3131"* ]]
}

@test "fish tmux: emit writes OSC 11 to stdout when TMUX is unset" {
  local stub="$TEST_HOME/stub_bin" log="$TEST_HOME/tmux.log"
  mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "'"$log"'"' 'exit 0' > "$stub/tmux"
  chmod +x "$stub/tmux"
  local out
  out="$(fish_eval 'set -gx PATH "'"$stub"'" $PATH; set -e TMUX; _pwdtintii_emit "#112233"')"
  local dump; dump="$(printf '%s' "$out" | od -An -tx1 | tr -d ' \n')"
  [[ "$dump" == *"1b5d3131"* ]]
  [ ! -f "$log" ]
}

@test "fish tmux: off routes to select-pane bg=default when TMUX is set" {
  local stub="$TEST_HOME/stub_bin" log="$TEST_HOME/tmux.log"
  mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "'"$log"'"' 'exit 0' > "$stub/tmux"
  chmod +x "$stub/tmux"
  fish_eval 'set -gx PATH "'"$stub"'" $PATH; set -gx TMUX /fake/tmux,0,0; pwdtintii_off'
  [ -f "$log" ]
  grep -q 'select-pane' "$log"
  grep -q 'bg=default' "$log"
}

# ── tmux per-pane tinting: the bin/pwdtintii fzf live-preview path ────────────
# bin/pwdtintii is shared across all three shells (the fish plugin shells out to
# the same binary for the picker/viewer fzf binds), so its emit subcommands must
# be tmux-aware too. Same mock as the plugin tmux tests: a `tmux` stub on PATH
# logs its args; TMUX set selects the per-pane branch. The CLI is a standalone
# bash script invoked directly, so these run it as a subprocess with TMUX set and
# the stub ahead on PATH (no fish needed for the binary itself; the setup() gate
# still skips them where fish is absent, keeping this file's invariant). Assert
# the stub saw select-pane + bg=#… and stdout carries NO OSC 11 (1b5d3131); the
# non-tmux branch writes to /dev/tty (not observable) and is pinned in cli.bats.

@test "fish tmux CLI: emit-family routes to select-pane, not OSC 11, when TMUX is set" {
  local stub="$TEST_HOME/stub_bin" log="$TEST_HOME/tmux.log"
  mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "'"$log"'"' 'exit 0' > "$stub/tmux"
  chmod +x "$stub/tmux"
  local out
  out=$(env PWDTINTII_PALETTE="$PWDTINTII_PALETTE" PATH="$stub:$PATH" TMUX=/fake/tmux,0,0 \
    "$REPO_ROOT/bin/pwdtintii" emit-family blue) 2>/dev/null
  [ -f "$log" ]
  grep -q 'select-pane' "$log"
  grep -q 'bg=#000f38' "$log"   # blue's focus tone: dimmed shade0 on the default palette
  local dump; dump=$(printf '%s' "$out" | od -An -tx1 | tr -d ' \n')
  [[ "$dump" != *"1b5d3131"* ]]
}

@test "fish tmux CLI: emit-restore routes to select-pane, not OSC 11, when TMUX is set" {
  local stub="$TEST_HOME/stub_bin" log="$TEST_HOME/tmux.log"
  mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "'"$log"'"' 'exit 0' > "$stub/tmux"
  chmod +x "$stub/tmux"
  local out
  out=$(env PWDTINTII_PALETTE="$PWDTINTII_PALETTE" PATH="$stub:$PATH" TMUX=/fake/tmux,0,0 \
    PWDTINTII_VIEW_FAMILY=blue PWDTINTII_VIEW_SHADE=2 \
    "$REPO_ROOT/bin/pwdtintii" emit-restore) 2>/dev/null
  [ -f "$log" ]
  grep -q 'select-pane' "$log"
  grep -q 'bg=#' "$log"
  local dump; dump=$(printf '%s' "$out" | od -An -tx1 | tr -d ' \n')
  [[ "$dump" != *"1b5d3131"* ]]
}

@test "fish tmux CLI: emit-backdrop routes to select-pane, not OSC 11, when TMUX is set" {
  local stub="$TEST_HOME/stub_bin" log="$TEST_HOME/tmux.log"
  mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "'"$log"'"' 'exit 0' > "$stub/tmux"
  chmod +x "$stub/tmux"
  local out
  out=$(env PWDTINTII_PALETTE="$PWDTINTII_PALETTE" PATH="$stub:$PATH" TMUX=/fake/tmux,0,0 \
    "$REPO_ROOT/bin/pwdtintii" emit-backdrop "$REPO_ROOT/palettes/default.tsv") 2>/dev/null
  [ -f "$log" ]
  grep -q 'select-pane' "$log"
  grep -q 'bg=#16191f' "$log"   # dark palette's viewer backdrop neutral
  local dump; dump=$(printf '%s' "$out" | od -An -tx1 | tr -d ' \n')
  [[ "$dump" != *"1b5d3131"* ]]
}
