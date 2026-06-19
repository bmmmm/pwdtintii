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

# fish 3.4+ (path resolve, --on-event fish_exit). Honour PWDTINTII_TEST_FISH like
# the bash override, then the usual brew / PATH locations.
_pwdtintii_find_fish() {
  local c
  for c in "${PWDTINTII_TEST_FISH:-}" /opt/homebrew/bin/fish /usr/local/bin/fish fish; do
    [[ -n "$c" ]] || continue
    command -v "$c" >/dev/null 2>&1 && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}
FISH_BIN="$(_pwdtintii_find_fish || true)"

setup_sandbox() {
  TEST_HOME="$(mktemp -d)"
  export PWDTINTII_PALETTE="$REPO_ROOT/palettes/default.tsv"
  export PWDTINTII_SHADES_DIR="$TEST_HOME/shades"
  unset PWDTINTII_OVERRIDES_FILE
}
teardown_sandbox() { [[ -n "${TEST_HOME:-}" ]] && rm -rf "$TEST_HOME"; }

need_bash() { [[ -n "$BASH4" ]] || skip "no bash >= 4 available"; }
need_zsh()  { [[ -n "$ZSH_BIN" ]] || skip "no zsh available"; }
need_fish() { [[ -n "$FISH_BIN" ]] || skip "no fish available"; }
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
  PT_REPO="$REPO_ROOT" PT_HOME="$1" PT_PWD="$2" PT_SNIP="$3" PT_PAL="$PWDTINTII_PALETTE" PT_SH="$PWDTINTII_SHADES_DIR" PT_PATH="$PATH" \
    "$ZSH_BIN" -c '
      # zsh nices background jobs by default (BG_NICE). The nice() syscall is
      # blocked in a command sandbox, and zsh prints "nice(N) failed" to stderr,
      # which bats `run` merges into $output — turning a correct "1" into a false
      # mismatch in the live-PID coordination test. Off here, harness-wide, since
      # job priority is irrelevant to anything these snippets assert.
      unsetopt bgnice 2>/dev/null
      # /etc/zshenv (macOS path_helper, Linux /etc/zsh/zshenv) can reset PATH
      # before our snippet runs, causing tool detection (fzf, python3, shasum) to
      # diverge from bash_eval which inherits the caller'"'"'s PATH unchanged.
      export PATH="$PT_PATH"
      # zsh builds its $commands hash at startup from the initial PATH; restoring
      # PATH via export does not update the hash.  rehash rebuilds it so that
      # (( $+commands[shasum] )) in the plugin sees the correct PATH.
      rehash 2>/dev/null || true
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

# fish differs from bash_eval/zsh_eval: $PWD is read-only in fish (bound to the
# real cwd, not fakeable), and fish needs a writable HOME/XDG, so fish_eval takes
# only a snippet (fish syntax) and points HOME/XDG at the per-test sandbox. A
# snippet that needs a specific $PWD either `cd`s into a real dir or stubs
# PWDTINTII_DIR_KEY_FN; one that needs the hash mapping calls _pwdtintii_family_for
# with the key as an argument (which never reads $PWD).
fish_eval() { # $1=snippet (fish)
  mkdir -p "$TEST_HOME/.local/share/fish" "$TEST_HOME/.config/fish" 2>/dev/null
  PT_REPO="$REPO_ROOT" PT_SNIP="$1" PT_PAL="$PWDTINTII_PALETTE" PT_SH="$PWDTINTII_SHADES_DIR" \
    HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_CONFIG_HOME="$TEST_HOME/.config" \
    "$FISH_BIN" -c '
      set -gx PWDTINTII_PALETTE "$PT_PAL"
      set -gx PWDTINTII_SHADES_DIR "$PT_SH"
      source "$PT_REPO/pwdtintii.plugin.fish" 2>/dev/null
      eval "$PT_SNIP"'
}

# fish side of _pt_emit_snip: drive the 1-based ${shades[idx+1]} apply subscript
# across shade 0..3 so it must agree byte-for-byte with bash's 0-based form.
_pt_fish_emit_snip='
  set -g _PWDTINTII_LAST_PWD foo; set -g _PWDTINTII_LAST_KEY k; set -g _PWDTINTII_PINNED k
  set -g _PWDTINTII_FORCED_FAMILY __FAM__; set -g _PWDTINTII_FAMILY __FAM__
  set -e _PWDTINTII_FORCE_REAPPLY
  for i in 0 1 2 3; set -g _PWDTINTII_SHADE_IDX $i; pwdtintii_apply | od -An -tx1 | tr -d " \n"; printf "\n"; end'
fish_emit_shades() { fish_eval "${_pt_fish_emit_snip//__FAM__/$1}"; }
