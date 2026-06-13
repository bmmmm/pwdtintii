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
