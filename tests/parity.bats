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

@test "dispatcher rejects an unknown command in zsh" {
  run zsh_eval / / 'pwdtintii frobnicate 2>&1; echo "rc=$?"'
  [[ "$output" == *"unknown command"* ]]
  [[ "$output" == *"rc=1"* ]]
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
