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
