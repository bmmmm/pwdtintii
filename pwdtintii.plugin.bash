# pwdtintii — directory-derived terminal background tinting for bash 4+
# Hash the current dir → pick a color family; each split/shell in the same dir
# gets a distinct shade. No daemon, PID-tracked, OSC 11 only.
#
# Requires bash 4+ (associative arrays). On macOS install via `brew install bash`.
#
# This is the thin bash adapter: it resolves its own location, sets the few
# shell-specific shims the shared core needs, sources lib/pwdtintii.core.sh
# (which holds the ~80% of logic identical to the zsh plugin), then installs the
# PROMPT_COMMAND hook + EXIT trap. The zsh plugin is the mirror adapter.
#
# Public functions:
#   pwdtintii [cmd]           — entry point / fzf action hub (alias: pt)
#   pwdtintii_apply           — re-apply background color to current shell
#   pwdtintii_pick [family]   — pin a family for this shell (fzf picker if no arg)
#   pwdtintii_pick --auto     — clear the pin, back to dir-derived auto mode
#   pwdtintii_list            — list families with current dir mapping
#   pwdtintii_reload          — re-load the palette TSV
#
# Config (set BEFORE sourcing):
#   PWDTINTII_PALETTE         — path to palette TSV (default: $plugin_dir/palettes/default.tsv)
#   PWDTINTII_OVERRIDES_FILE  — optional TSV: project_basename<TAB>family
#   PWDTINTII_SHADES_DIR      — PID-registry dir (default: ~/.config/pwdtintii/shades)
#   PWDTINTII_DIR_KEY_FN      — optional function name resolving $PWD → key

if [[ -z "${BASH_VERSINFO[0]:-}" ]] || (( BASH_VERSINFO[0] < 4 )); then
  printf '%s\n' "pwdtintii: requires bash 4+ (you have ${BASH_VERSION:-unknown})" >&2
  return 1 2>/dev/null || exit 1
fi

# ── Resolve own location (follow symlinks; BSD+GNU portable, no readlink -f) ──
_pwdtintii_self="${BASH_SOURCE[0]}"
while [[ -h "$_pwdtintii_self" ]]; do
  _pwdtintii_dir="$(cd -P "$(dirname "$_pwdtintii_self")" && pwd)"
  _pwdtintii_self="$(readlink "$_pwdtintii_self")"
  [[ "$_pwdtintii_self" != /* ]] && _pwdtintii_self="${_pwdtintii_dir}/${_pwdtintii_self}"
done
_pwdtintii_self="$(cd -P "$(dirname "$_pwdtintii_self")" && pwd)"
unset _pwdtintii_dir
_PWDTINTII_PLUGIN_FILE="${_pwdtintii_self}/pwdtintii.plugin.bash"

: "${PWDTINTII_PALETTE:=${_pwdtintii_self}/palettes/default.tsv}"
: "${PWDTINTII_SHADES_DIR:=${HOME}/.config/pwdtintii/shades}"
: "${PWDTINTII_DIR_KEY_FN:=_pwdtintii_default_key}"

# ── Shell shims the core builds on (see lib/pwdtintii.core.sh header) ─────────
_PT_AOFF=0                          # bash indexed arrays are 0-based
_PT_SHELLCHECK=("${BASH:-bash}")    # the `-n` parse check before a self-reload
# Word-split a "s0 s1 s2 s3" row into _PT_SPLIT (bash word-splits an unquoted $1).
# shellcheck disable=SC2206  # the unquoted split into four shades is the point
_pt_split() { _PT_SPLIT=( $1 ); }
# Read one silent key into the var named $1, optionally with a -t $2 timeout.
# Reads from /dev/tty so a redirected stdin can't swallow the keypress.
_pt_readkey() {
  if [[ -n "${2:-}" ]]; then read -rsn1 -t "$2" "$1" < /dev/tty; else read -rsn1 "$1" < /dev/tty; fi
}

# shellcheck source=lib/pwdtintii.core.sh  # dynamic self-path; resolved at runtime
source "${_pwdtintii_self}/lib/pwdtintii.core.sh"

_pt_boot || return

# ── Hooks ────────────────────────────────────────────────────────────────────
# Register the prompt hook exactly once per shell. A self-reload re-sources this
# file, so a one-shot flag keeps the re-source from appending again. PROMPT_COMMAND
# can be a string or — since bash 5.1 — an array, so scan EVERY element for our
# hook: a reformatted ";" separator (string) or a hook in a non-[0] element (array)
# used to slip past a [0]-only substring check and double-register, emitting OSC 11
# twice per prompt. zsh gets this from add-zsh-hook's exact-membership dedupe.
_pwdtintii_install_hook() {
  local hook=_pwdtintii_precmd e
  if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
    for e in "${PROMPT_COMMAND[@]}"; do [[ "$e" == *"$hook"* ]] && return 0; done
    PROMPT_COMMAND+=( "$hook" )
  else
    [[ ";${PROMPT_COMMAND:-};" == *";${hook};"* ]] && return 0
    # shellcheck disable=SC2178  # this branch deliberately assigns the string form (bash <5.1)
    PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND%;};}${hook}"
  fi
}
if [[ -z "${_PWDTINTII_HOOK_INSTALLED:-}" ]]; then
  _pwdtintii_install_hook
  _PWDTINTII_HOOK_INSTALLED=1
fi
trap _pwdtintii_release EXIT
