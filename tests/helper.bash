# Shared helpers for the pwdtintii bats suite.
#
# Plugins are exercised by running snippets in a real bash 4+ / zsh interpreter
# with an isolated HOME, palette, and shade registry — never by sourcing into
# the bats shell itself (which may be bash 3.2 on macOS).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Locate a bash >= 4 (plugins need associative arrays).
_pwdtintii_find_bash4() {
  local c v
  for c in "${PWDTINTII_TEST_BASH:-}" /opt/homebrew/bin/bash /usr/local/bin/bash bash; do
    [[ -n "$c" ]] || continue
    command -v "$c" >/dev/null 2>&1 || continue
    v="$("$c" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null)"
    [[ -n "$v" && "$v" -ge 4 ]] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}
BASH4="$(_pwdtintii_find_bash4 || true)"
ZSH_BIN="$(command -v zsh 2>/dev/null || true)"

setup_sandbox() {
  TEST_HOME="$(mktemp -d)"
  export PWDTINTII_PALETTE="$REPO_ROOT/palettes/default.tsv"
  export PWDTINTII_SHADES_DIR="$TEST_HOME/shades"
  unset PWDTINTII_OVERRIDES_FILE
}
teardown_sandbox() { [[ -n "${TEST_HOME:-}" ]] && rm -rf "$TEST_HOME"; }

need_bash() { [[ -n "$BASH4" ]] || skip "no bash >= 4 available"; }
need_zsh()  { [[ -n "$ZSH_BIN" ]] || skip "no zsh available"; }
need_both() { need_bash; need_zsh; }

# Run a snippet with the bash plugin sourced. Snippet references $HOME/$PWD and
# plugin functions; passed verbatim (single-quote it at the call site).
bash_eval() { # $1=home $2=pwd $3=snippet
  PT_REPO="$REPO_ROOT" PT_HOME="$1" PT_PWD="$2" PT_SNIP="$3" PT_PAL="$PWDTINTII_PALETTE" PT_SH="$PWDTINTII_SHADES_DIR" \
    "$BASH4" -c '
      export PWDTINTII_PALETTE="$PT_PAL" PWDTINTII_SHADES_DIR="$PT_SH"
      source "$PT_REPO/pwdtintii.plugin.bash" 2>/dev/null
      HOME="$PT_HOME"; PWD="$PT_PWD"
      eval "$PT_SNIP"
    '
}
zsh_eval() {
  PT_REPO="$REPO_ROOT" PT_HOME="$1" PT_PWD="$2" PT_SNIP="$3" PT_PAL="$PWDTINTII_PALETTE" PT_SH="$PWDTINTII_SHADES_DIR" \
    "$ZSH_BIN" -c '
      export PWDTINTII_PALETTE="$PT_PAL" PWDTINTII_SHADES_DIR="$PT_SH"
      source "$PT_REPO/pwdtintii.plugin.zsh" 2>/dev/null
      HOME="$PT_HOME"; PWD="$PT_PWD"
      eval "$PT_SNIP"
    '
}

# key|family for a given (home, pwd), per shell.
bash_key_family() { bash_eval "$1" "$2" 'k=$(_pwdtintii_default_key); printf "%s|%s\n" "$k" "$(_pwdtintii_family_for "$k")"'; }
zsh_key_family()  { zsh_eval  "$1" "$2" 'k=$(_pwdtintii_default_key); printf "%s|%s\n" "$k" "$(_pwdtintii_family_for "$k")"'; }

# Hex-dump (one line per shade) of the OSC 11 pwdtintii_apply emits for family $3
# across shade index 0..3. Drives the REAL apply array-subscript path — bash
# 0-based ${shades[$shade_idx]}, zsh 1-based ${shades[$((shade_idx+1))]} — by
# forcing the family + shade and steering apply down its cached (reuse) branch,
# so the two shells must agree byte-for-byte on which physical hex each shade
# index selects. od makes the ESC/BEL bytes compare cleanly.
_pt_emit_snip='
  _PWDTINTII_LAST_PWD="$PWD"; _PWDTINTII_LAST_KEY=k; _PWDTINTII_PINNED=k
  _PWDTINTII_FORCED_FAMILY=__FAM__; _PWDTINTII_FAMILY=__FAM__
  unset _PWDTINTII_FORCE_REAPPLY
  for i in 0 1 2 3; do _PWDTINTII_SHADE_IDX=$i; pwdtintii_apply | od -An -tx1 | tr -d " \n"; printf "\n"; done'
bash_emit_shades() { bash_eval "$1" "$2" "${_pt_emit_snip//__FAM__/$3}"; }
zsh_emit_shades()  { zsh_eval  "$1" "$2" "${_pt_emit_snip//__FAM__/$3}"; }
