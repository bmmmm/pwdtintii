# pwdtintii — directory-derived terminal background tinting for zsh
# Hash the current dir → pick a color family; each split/shell in the same dir
# gets a distinct shade. No daemon, no persisted state, PID-tracked, OSC 11 only.
#
# This is the thin zsh adapter: it resolves its own location, sets the few
# shell-specific shims the shared core needs, sources lib/pwdtintii.core.sh
# (which holds the ~80% of logic identical to the bash plugin), then registers
# the zsh precmd/exit hooks. The bash plugin is the mirror adapter.
#
# Public functions:
#   pwdtintii [cmd]           — entry point / fzf action hub (alias: pt)
#   pwdtintii_apply           — re-apply background color to current shell
#   pwdtintii_pick [family]   — pin a family for this shell (fzf picker if no arg)
#   pwdtintii_pick --auto     — clear the pin, back to dir-derived auto mode
#   pwdtintii_list            — list families with their current dir mapping
#   pwdtintii_reload          — re-load the palette TSV
#
# Config (set BEFORE sourcing):
#   PWDTINTII_PALETTE         — path to palette TSV (default: $plugin_dir/palettes/default.tsv)
#   PWDTINTII_OVERRIDES_FILE  — optional TSV of named overrides: project_basename<TAB>family
#   PWDTINTII_SHADES_DIR      — runtime PID-registry dir (default: ~/.config/pwdtintii/shades)
#   PWDTINTII_DIR_KEY_FN      — optional shell function name to resolve $PWD → key (default: _pwdtintii_default_key)

# ── Resolve own location (%x is this file; :A resolves symlinks) ─────────────
_pwdtintii_self="${${(%):-%x}:A:h}"
_PWDTINTII_PLUGIN_FILE="${_pwdtintii_self}/pwdtintii.plugin.zsh"
: ${PWDTINTII_PALETTE:="${_pwdtintii_self}/palettes/default.tsv"}
: ${PWDTINTII_SHADES_DIR:="${HOME}/.config/pwdtintii/shades"}
: ${PWDTINTII_DIR_KEY_FN:=_pwdtintii_default_key}

# ── Shell shims the core builds on (see lib/pwdtintii.core.sh header) ─────────
_PT_AOFF=1                       # zsh indexed arrays are 1-based
_PT_SHELLCHECK=(command zsh)     # the `-n` parse check before a self-reload
# Word-split a "s0 s1 s2 s3" row into _PT_SPLIT (zsh keeps unquoted expansions
# intact, so force splitting with ${=...}).
_pt_split() { _PT_SPLIT=( ${=1} ); }
# Read one silent key into the var named $1, optionally with a -t $2 timeout.
# `read -k` reads the controlling terminal directly (ignores fd redirects).
_pt_readkey() {
  if [[ -n "${2:-}" ]]; then read -k1 -s -t "$2" "$1"; else read -k1 -s "$1"; fi
}

# shellcheck source=lib/pwdtintii.core.sh  # dynamic self-path; resolved at runtime
source "${_pwdtintii_self}/lib/pwdtintii.core.sh"

_pt_boot || return

# ── Hooks ────────────────────────────────────────────────────────────────────
# add-zsh-hook dedupes by exact membership, so a self-reload re-running this
# leaves exactly one precmd hook (no double OSC 11 per prompt).
autoload -Uz add-zsh-hook
add-zsh-hook precmd _pwdtintii_precmd
add-zsh-hook zshexit _pwdtintii_release
