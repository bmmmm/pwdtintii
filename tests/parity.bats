#!/usr/bin/env bats
# bash and zsh must resolve identical keys, families, and registry hashes —
# otherwise the same directory tints differently depending on the shell.

load helper

setup() { need_both; setup_sandbox; }
teardown() { teardown_sandbox; }

@test "key+family parity: non-HOME nested path (/opt/projektX/sub)" {
  [ "$(bash_key_family /testhome /opt/projektX/sub)" = "$(zsh_key_family /testhome /opt/projektX/sub)" ]
}

@test "key+family parity: shallow absolute path (/srv)" {
  [ "$(bash_key_family /testhome /srv)" = "$(zsh_key_family /testhome /srv)" ]
}

@test "key+family parity: deep system path (/var/lib/foo/bar)" {
  [ "$(bash_key_family /testhome /var/lib/foo/bar)" = "$(zsh_key_family /testhome /var/lib/foo/bar)" ]
}

@test "key+family parity: first component under HOME" {
  [ "$(bash_key_family /testhome /testhome/work/repo/deep)" = "$(zsh_key_family /testhome /testhome/work/repo/deep)" ]
}

@test "key+family parity: HOME itself" {
  [ "$(bash_key_family /testhome /testhome)" = "$(zsh_key_family /testhome /testhome)" ]
}

@test "key+family parity: filesystem root" {
  [ "$(bash_key_family /testhome /)" = "$(zsh_key_family /testhome /)" ]
}

@test "non-HOME path collapses to first component (not whole path)" {
  run bash_key_family /testhome /opt/projektX/sub
  [[ "$output" == /opt\|* ]]
  run zsh_key_family /testhome /opt/projektX/sub
  [[ "$output" == /opt\|* ]]
}

@test "registry keyhash parity (bash printf vs zsh print -rn)" {
  key="/testhome/projects/app"
  hb="$(bash_eval /testhome / 'printf "%s" "'"$key"'" | $_PWDTINTII_HASHCMD | cut -c1-12')"
  hz="$(zsh_eval  /testhome / 'print -rn -- "'"$key"'" | $_PWDTINTII_HASHCMD | cut -c1-12')"
  [ -n "$hb" ]
  [ "$hb" = "$hz" ]
}

@test "family is deterministic across repeated calls" {
  a="$(bash_key_family /testhome /opt/a/b/c)"
  b="$(bash_key_family /testhome /opt/a/b/c)"
  [ "$a" = "$b" ]
}

# A hand-edited palette without a trailing newline must not silently lose its
# last family. The loader reads the file raw (no grep/sed upstream to re-add the
# newline), so both shells need the `|| [[ -n "$family" ]]` last-line guard — and
# must agree, since the last family vanishing in only one shell would also break
# the cross-shell hash mapping.
@test "palette load keeps a newline-less last family (bash and zsh)" {
  printf 'aaa\t#001f70\t#002d8f\t#0a38a8\t#1442c0\n' >  "$TEST_HOME/nonl.tsv"
  printf 'zzz\t#701f00\t#8f2d00\t#a8380a\t#c04214'   >> "$TEST_HOME/nonl.tsv"   # no trailing newline
  local b z
  b="$(PWDTINTII_PALETTE="$TEST_HOME/nonl.tsv" bash_eval / / 'printf "%s\n" "${_pwdtintii_families[*]}"')"
  z="$(PWDTINTII_PALETTE="$TEST_HOME/nonl.tsv" zsh_eval  / / 'printf "%s\n" "${_pwdtintii_families[*]}"')"
  [[ "$b" == *"aaa"* && "$b" == *"zzz"* ]]
  [[ "$z" == *"aaa"* && "$z" == *"zzz"* ]]
}

# The load-bearing index-base invariant: bash apply emits ${shades[$shade_idx]}
# (0-based) and zsh emits ${shades[$((shade_idx+1))]} (1-based). For a given
# (family, shade) the resulting OSC-11 hex MUST be byte-identical — otherwise the
# same directory tints differently per shell, and nothing else in the suite would
# catch a copy-paste slip between the two subscript forms.
@test "emitted OSC-11 hex is byte-identical in bash and zsh (apply index base)" {
  local b z
  b="$(bash_emit_shades /testhome /testhome/x blue)"
  z="$(zsh_emit_shades  /testhome /testhome/x blue)"
  [ -n "$b" ]
  [ "$b" = "$z" ]
  # Teeth: the four shades must be distinct, so the test can't pass vacuously on
  # an apply that emits the same shade (or nothing) for every index.
  [ "$(printf '%s\n' "$b" | sort -u | grep -c .)" -eq 4 ]
}

@test "emitted OSC-11 hex parity holds for a second family (charcoal)" {
  [ "$(bash_emit_shades /testhome /testhome/x charcoal)" = "$(zsh_emit_shades /testhome /testhome/x charcoal)" ]
}

# Regression guard: apply at the filesystem root (empty project basename) must
# not leak an internal error (e.g. "bad array subscript") to the prompt. This
# deliberately does NOT swallow stderr, unlike the *_eval helpers.
@test "no stderr noise when applying at filesystem root (bash)" {
  err="$(PT_REPO="$REPO_ROOT" PT_PAL="$PWDTINTII_PALETTE" PT_SH="$PWDTINTII_SHADES_DIR" "$BASH4" -c '
    export PWDTINTII_PALETTE="$PT_PAL" PWDTINTII_SHADES_DIR="$PT_SH"
    source "$PT_REPO/pwdtintii.plugin.bash"
    HOME=/testhome; PWD=/; pwdtintii_apply' 2>&1 >/dev/null)"
  [ -z "$err" ]
}

@test "no stderr noise when applying at filesystem root (zsh)" {
  err="$(PT_REPO="$REPO_ROOT" PT_PAL="$PWDTINTII_PALETTE" PT_SH="$PWDTINTII_SHADES_DIR" "$ZSH_BIN" -c '
    export PWDTINTII_PALETTE="$PT_PAL" PWDTINTII_SHADES_DIR="$PT_SH"
    source "$PT_REPO/pwdtintii.plugin.zsh"
    HOME=/testhome; PWD=/; pwdtintii_apply' 2>&1 >/dev/null)"
  [ -z "$err" ]
}

# The `pt` dispatcher lives in both plugins — keep its help text and error
# behaviour identical so `pt` works the same regardless of shell.
@test "dispatcher help text is identical in bash and zsh" {
  [ "$(bash_eval /testhome / 'pwdtintii help')" = "$(zsh_eval /testhome / 'pwdtintii help')" ]
}

# help was the ONLY display text pinned; doctor, list, and the no-fzf menu carry
# just as much hand-mirrored text across the two files and were unguarded. Off a
# tty all three are deterministic (doctor takes its "skipped" branch), so pin
# them byte-for-byte: this makes maintaining two native files provably safe and
# is the baseline the echo->printf collapse must preserve.
@test "doctor output is identical in bash and zsh (off-tty)" {
  [ "$(bash_eval /testhome /testhome/proj 'pwdtintii doctor')" = "$(zsh_eval /testhome /testhome/proj 'pwdtintii doctor')" ]
}

@test "list output is identical in bash and zsh" {
  [ "$(bash_eval /testhome /testhome/proj 'pwdtintii list')" = "$(zsh_eval /testhome /testhome/proj 'pwdtintii list')" ]
}

@test "no-fzf pick menu output is identical in bash and zsh" {
  local b z
  b="$(bash_eval /testhome /testhome/proj 'printf "\n" | _pwdtintii_pick_menu 2>&1')"
  z="$(zsh_eval  /testhome /testhome/proj 'printf "\n" | _pwdtintii_pick_menu 2>&1')"
  [ -n "$b" ]
  [ "$b" = "$z" ]
}

@test "dispatcher rejects an unknown command in zsh" {
  run zsh_eval / / 'pwdtintii frobnicate 2>&1; echo "rc=$?"'
  [[ "$output" == *"unknown command"* ]]
  [[ "$output" == *"rc=1"* ]]
}

# The `pt` dispatcher self-heals a stale shell by re-sourcing in both plugins;
# plugin.bats exercises the bash side, this guards the zsh side.
@test "zsh pt auto-reloads a stale shell before dispatching" {
  run zsh_eval /testhome /testhome '
    _pwdtintii_families=(bogus)
    _PWDTINTII_LOADED_MTIME=1
    pwdtintii list >/dev/null 2>&1
    _pwdtintii_is_stale && print still-stale || print healed
    print "count=${#_pwdtintii_families}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"healed"* ]]
  [[ "$output" == *"count=37"* ]]
}

# bash guards the prompt-hook against a self-reload double-append with a one-shot
# flag; zsh gets it from add-zsh-hook's exact-membership dedupe. Same observable
# behaviour: a re-source leaves exactly one _pwdtintii_precmd hook registered.
@test "zsh self-reload keeps a single precmd hook (no double OSC 11)" {
  run zsh_eval /testhome /testhome '
    _PWDTINTII_LOADED_MTIME=1            # force staleness
    pwdtintii list >/dev/null 2>&1       # dispatch → self-reload re-sources
    local -a hooks=( "${(@M)precmd_functions:#_pwdtintii_precmd}" )
    print "n=${#hooks}"                  # element count, not string length
  '
  [ "$status" -eq 0 ]
  [ "$output" = "n=1" ]
}

# The precmd hook runs between the user's command and the prompt; it must hand
# $? back untouched so %? (and any prompt reading $?) shows the real status, not
# pwdtintii_apply's 0. bash guards this in plugin.bats; this is the zsh side.
@test "zsh precmd hook preserves \$? (the prompt %? shows the real status)" {
  run zsh_eval /testhome /testhome '
    ( exit 42 )                        # a recognizable non-zero status
    _pwdtintii_precmd >/dev/null 2>&1
    print "rc=$?"
  '
  [[ "$output" == *"rc=42"* ]]
}

# The plugin advertises `setopt nounset` support (see the _pwdtintii_release
# comment). bash guards every state read with `${VAR:-}`; the zsh side must too,
# including the two associative-array subscript reads that abort under nounset:
# the apply emit (`${shades[i]}` when a forced/pinned family vanished from the
# palette) and the pick unknown-family check. Source under nounset (the real
# user path — it's set in their .zshrc before the plugin loads) and drive both.
@test "zsh survives setopt nounset on the absent-family paths (apply + pick)" {
  run env PT_REPO="$REPO_ROOT" PT_PAL="$PWDTINTII_PALETTE" PT_SH="$PWDTINTII_SHADES_DIR" \
    "$ZSH_BIN" -c '
      setopt nounset
      export PWDTINTII_PALETTE="$PT_PAL" PWDTINTII_SHADES_DIR="$PT_SH"
      source "$PT_REPO/pwdtintii.plugin.zsh"
      HOME=/testhome; PWD=/testhome/proj
      _PWDTINTII_FORCED_FAMILY=zzz_absent_family   # forced family with no shades entry
      pwdtintii_apply;                  print "apply-done"
      pwdtintii_pick zzz_absent_family 2>/dev/null; print "pick-rc=$?"
    '
  # A nounset abort exits the whole zsh -c before its markers print, so the proof
  # of "no abort" is status 0 AND both markers reaching the output. (apply itself
  # returns the emit's rc — non-zero is the correct no-op on an empty shade, and
  # the precmd wrapper masks it anyway — so we don't pin apply's rc here.)
  [ "$status" -eq 0 ]
  [[ "$output" == *"apply-done"* ]]    # apply ran to the end, no parameter-not-set abort
  [[ "$output" == *"pick-rc=1"* ]]     # clean "unknown family", not a nounset abort
}

# The `pt` self-reload parse-checks before sourcing in both plugins; plugin.bats
# exercises the bash side, this guards the zsh side.
@test "zsh self-reload refuses a syntactically broken plugin (keeps the running one)" {
  run zsh_eval /testhome /testhome '
    broken="$PWDTINTII_SHADES_DIR/broken.zsh"
    mkdir -p "$PWDTINTII_SHADES_DIR"
    printf "pwdtintii_apply() {\n" > "$broken"   # truncated: unterminated function
    _PWDTINTII_PLUGIN_FILE="$broken"
    _PWDTINTII_LOADED_MTIME=1                     # force staleness
    msg=$(pwdtintii list 2>&1 >/dev/null) || true
    print "$msg"
    (( $+functions[pwdtintii_apply] )) && print apply-intact || print apply-gone
  '
  [[ "$output" == *"won't parse"* ]]
  [[ "$output" == *"apply-intact"* ]]
}

# The picker's dark/light toggle commits through _pwdtintii_set_palette in both
# shells; plugin.bats exercises the bash side, this guards the zsh side.
@test "zsh set_palette switches the active palette (light shades differ)" {
  run zsh_eval /testhome /testhome '
    dark="${_pwdtintii_shades[blue]}"
    _pwdtintii_set_palette "$_pwdtintii_self/palettes/light.tsv"
    light="${_pwdtintii_shades[blue]}"
    [[ "$PWDTINTII_PALETTE" == *"/light.tsv" ]] && print pal-ok
    [[ -n "$light" && "$dark" != "$light" ]] && print shades-differ
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"pal-ok"* ]]
  [[ "$output" == *"shades-differ"* ]]
}

# ── cross-shell shade-registry coordination ──────────────────────────────────
# The core promise: a zsh shell and a bash shell in the same dir get *distinct*
# shades. The hash-parity test above proves both compute the same registry file
# name; this proves the bash picker honours an entry written under a hash that
# zsh computed — i.e. the two shells really share one registry end to end.
@test "cross-shell: bash avoids a shade held under a zsh-computed registry hash" {
  key="/testhome/projects/shared"
  h="$(zsh_eval /testhome / 'print -rn -- "'"$key"'" | $_PWDTINTII_HASHCMD | cut -c1-12')"
  [ -n "$h" ]
  mkdir -p "$PWDTINTII_SHADES_DIR"
  sleep 30 & live=$!
  printf '%s\t0\t1\n' "$live" > "$PWDTINTII_SHADES_DIR/$h.tsv"
  run bash_eval /testhome / '_pwdtintii_pick_shade "'"$key"'" "" "'"$h"'"'
  kill "$live" 2>/dev/null
  [ "$output" = "1" ]
}

# zsh's shade registry is logic-mirrored from bash; plugin.bats exercises the
# bash side, these guard the zsh side directly (skip live PIDs, reclaim dead).
@test "zsh pick_shade skips a shade held by a live PID" {
  run zsh_eval / / '
    mkdir -p "$PWDTINTII_SHADES_DIR"
    sleep 30 & live=$!
    printf "%s\t0\t1\n" "$live" > "$PWDTINTII_SHADES_DIR/zz.tsv"
    _pwdtintii_pick_shade "k" "" "zz"
    kill "$live" 2>/dev/null
  '
  [ "$output" = "1" ]
}

@test "zsh pick_shade reclaims a shade from a dead PID" {
  run zsh_eval / / '
    mkdir -p "$PWDTINTII_SHADES_DIR"
    printf "999999\t0\t1\n" > "$PWDTINTII_SHADES_DIR/zz.tsv"
    _pwdtintii_pick_shade "k" "" "zz"
  '
  [ "$output" = "0" ]
}

# ── tmux per-pane tinting (zsh) ──────────────────────────────────────────────
# bash gets these in plugin.bats and fish in fish.bats; the zsh emit/off tmux
# branch is byte-identical, so pin it here too. Mock `tmux` logs its args.
@test "zsh tmux: emit routes to select-pane, not OSC 11, when TMUX is set" {
  local stub="$TEST_HOME/stub_bin" log="$TEST_HOME/tmux.log"
  mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "'"$log"'"' 'exit 0' > "$stub/tmux"
  chmod +x "$stub/tmux"
  local out
  out=$(PT_REPO="$REPO_ROOT" PT_PAL="$PWDTINTII_PALETTE" PT_SH="$PWDTINTII_SHADES_DIR" PT_STUB="$stub" \
    "$ZSH_BIN" -c '
      export PWDTINTII_PALETTE="$PT_PAL" PWDTINTII_SHADES_DIR="$PT_SH" PATH="$PT_STUB:$PATH"
      source "$PT_REPO/pwdtintii.plugin.zsh" 2>/dev/null
      export TMUX=/fake/tmux,0,0
      _pwdtintii_emit "#112233"
    ') 2>/dev/null
  [[ -f "$log" ]] || { echo "tmux log missing"; return 1; }
  grep -q 'select-pane' "$log"
  grep -q 'bg=#112233' "$log"
  local dump; dump=$(printf '%s' "$out" | od -An -tx1 | tr -d ' \n')
  [[ "$dump" != *"1b5d3131"* ]] || { echo "unexpected OSC 11: $dump"; return 1; }
}

@test "zsh tmux: emit writes OSC 11 to stdout when TMUX is unset" {
  local stub="$TEST_HOME/stub_bin" log="$TEST_HOME/tmux.log"
  mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "'"$log"'"' 'exit 0' > "$stub/tmux"
  chmod +x "$stub/tmux"
  local out
  out=$(PT_REPO="$REPO_ROOT" PT_PAL="$PWDTINTII_PALETTE" PT_SH="$PWDTINTII_SHADES_DIR" PT_STUB="$stub" \
    "$ZSH_BIN" -c '
      export PWDTINTII_PALETTE="$PT_PAL" PWDTINTII_SHADES_DIR="$PT_SH" PATH="$PT_STUB:$PATH"
      source "$PT_REPO/pwdtintii.plugin.zsh" 2>/dev/null
      unset TMUX
      _pwdtintii_emit "#112233"
    ') 2>/dev/null
  local dump; dump=$(printf '%s' "$out" | od -An -tx1 | tr -d ' \n')
  [[ "$dump" == *"1b5d3131"* ]] || { echo "OSC 11 not in stdout: $dump"; return 1; }
  [[ ! -f "$log" ]] || { echo "tmux called unexpectedly: $(cat "$log")"; return 1; }
}

@test "zsh tmux: off routes to select-pane bg=default when TMUX is set" {
  local stub="$TEST_HOME/stub_bin" log="$TEST_HOME/tmux.log"
  mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "'"$log"'"' 'exit 0' > "$stub/tmux"
  chmod +x "$stub/tmux"
  PT_REPO="$REPO_ROOT" PT_PAL="$PWDTINTII_PALETTE" PT_SH="$PWDTINTII_SHADES_DIR" PT_STUB="$stub" \
    "$ZSH_BIN" -c '
      export PWDTINTII_PALETTE="$PT_PAL" PWDTINTII_SHADES_DIR="$PT_SH" PATH="$PT_STUB:$PATH"
      source "$PT_REPO/pwdtintii.plugin.zsh" 2>/dev/null
      export TMUX=/fake/tmux,0,0
      pwdtintii_off
    ' 2>/dev/null
  [[ -f "$log" ]] || { echo "tmux log missing"; return 1; }
  grep -q 'select-pane' "$log"
  grep -q 'bg=default' "$log"
}
