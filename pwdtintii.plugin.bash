# pwdtintii — directory-derived terminal background tinting for bash 4+
# Hash the current dir → pick a color family; each split/shell in the same dir
# gets a distinct shade. No daemon, PID-tracked, OSC 11 only.
#
# Requires bash 4+ (associative arrays). On macOS install via `brew install bash`.
#
# Public functions:
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
  echo "pwdtintii: requires bash 4+ (you have ${BASH_VERSION:-unknown})" >&2
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

: "${PWDTINTII_PALETTE:=${_pwdtintii_self}/palettes/default.tsv}"
: "${PWDTINTII_SHADES_DIR:=${HOME}/.config/pwdtintii/shades}"
: "${PWDTINTII_DIR_KEY_FN:=_pwdtintii_default_key}"

declare -gA _pwdtintii_shades
declare -ga _pwdtintii_families
declare -gA _pwdtintii_overrides

# Hash command: shasum (macOS) or sha1sum (Linux). Fail loudly if neither.
if command -v shasum >/dev/null 2>&1; then
  _PWDTINTII_HASHCMD=shasum
elif command -v sha1sum >/dev/null 2>&1; then
  _PWDTINTII_HASHCMD=sha1sum
else
  echo "pwdtintii: needs 'shasum' or 'sha1sum' on PATH" >&2
  return 1 2>/dev/null || exit 1
fi

# ── Palette loader ───────────────────────────────────────────────────────────
_pwdtintii_load_palette() {
  _pwdtintii_shades=()
  _pwdtintii_families=()
  local family s0 s1 s2 s3
  while IFS=$'\t' read -r family s0 s1 s2 s3; do
    [[ -z "$family" || "$family" == "family" || "$family" == \#* ]] && continue
    _pwdtintii_shades[$family]="$s0 $s1 $s2 $s3"
    _pwdtintii_families+=("$family")
  done < "$PWDTINTII_PALETTE"
}

_pwdtintii_load_overrides() {
  _pwdtintii_overrides=()
  [[ -z "${PWDTINTII_OVERRIDES_FILE:-}" || ! -f "$PWDTINTII_OVERRIDES_FILE" ]] && return
  local proj family
  while IFS=$'\t' read -r proj family; do
    [[ -z "$proj" || "$proj" == \#* ]] && continue
    _pwdtintii_overrides[$proj]=$family
  done < "$PWDTINTII_OVERRIDES_FILE"
}

# ── Dir-key strategy: git-root or first path component under $HOME ────────────
_pwdtintii_default_key() {
  local dir="$PWD"
  while [[ "$dir" != "/" && "$dir" != "$HOME" ]]; do
    [[ -d "$dir/.git" ]] && { printf '%s\n' "$dir"; return; }
    dir="${dir%/*}"
    [[ -z "$dir" ]] && dir="/"
  done
  if [[ "$PWD" == "$HOME" ]]; then
    printf '%s\n' "$HOME"
  elif [[ "$PWD" == "$HOME"/* ]]; then
    local rel="${PWD#"${HOME}"/}"
    printf '%s\n' "${HOME}/${rel%%/*}"
  else
    local rel="${PWD#/}"
    printf '%s\n' "/${rel%%/*}"
  fi
}

# ── Family resolver: override > hash → family ────────────────────────────────
_pwdtintii_family_for() {
  local key="$1"
  (( ${#_pwdtintii_families[@]} == 0 )) && return 1
  local proj="${key##*/}"
  if [[ -n "$proj" && -n "${_pwdtintii_overrides[$proj]:-}" ]]; then
    printf '%s\n' "${_pwdtintii_overrides[$proj]}"
    return
  fi
  local h
  h=$(printf '%s' "$key" | "$_PWDTINTII_HASHCMD" | cut -c1-8)
  printf '%s\n' "${_pwdtintii_families[$(( 0x$h % ${#_pwdtintii_families[@]} ))]}"
}

# ── Shade picker: per-key registry, PID-GC, mkdir-locked read-modify-write ───
# Takes the precomputed keyhash as $3 so the prompt hot-path can cache it.
_pwdtintii_pick_shade() {
  local key="$1" forced="${2:-}" keyhash="$3" my_pid=$$
  local reg="${PWDTINTII_SHADES_DIR}/${keyhash}.tsv"
  local lock="${reg}.lock"
  mkdir -p "$PWDTINTII_SHADES_DIR"

  # Acquire a lock around the read-modify-write so concurrently starting shells
  # don't clobber each other's entry. Bounded + fail-open: a prompt never hangs.
  local locked="" i lpid pidless=0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if mkdir "$lock" 2>/dev/null; then locked=1; break; fi
    lpid=""
    [[ -f "$lock/pid" ]] && read -r lpid < "$lock/pid" 2>/dev/null
    if [[ -n "$lpid" ]]; then
      pidless=0
      if ! kill -0 "$lpid" 2>/dev/null; then          # holder is dead → steal
        rm -f "$lock/pid" 2>/dev/null; rmdir "$lock" 2>/dev/null; continue
      fi
    else
      # Lock with no pid yet: give the holder a moment to write it, but if it
      # stays pid-less across a few polls it's an orphan (holder died between
      # mkdir and the pid write). rmdir fails safe if the pid landed meanwhile.
      pidless=$((pidless + 1))
      if (( pidless >= 3 )); then
        rmdir "$lock" 2>/dev/null; pidless=0; continue
      fi
    fi
    sleep 0.05
  done
  [[ -n "$locked" ]] && printf '%s\n' "$my_pid" > "$lock/pid"

  : > "${reg}.new"
  declare -A in_use
  if [[ -f "$reg" ]]; then
    local pid sh ts
    while IFS=$'\t' read -r pid sh ts; do
      [[ "$pid" == "$my_pid" ]] && continue
      kill -0 "$pid" 2>/dev/null || continue
      in_use[$sh]=1
      printf '%s\t%s\t%s\n' "$pid" "$sh" "$ts" >> "${reg}.new"
    done < "$reg"
  fi
  local pick
  if [[ -n "$forced" ]]; then
    pick="$forced"
  else
    pick=0
    for pick in 0 1 2 3; do [[ -z "${in_use[$pick]:-}" ]] && break; done
  fi
  printf '%s\t%s\t%s\n' "$my_pid" "$pick" "$(date +%s)" >> "${reg}.new"
  mv "${reg}.new" "$reg"
  [[ -n "$locked" ]] && { rm -f "$lock/pid" 2>/dev/null; rmdir "$lock" 2>/dev/null; }
  printf '%s\n' "$pick"
}

# Drop this shell's entry from its registry; remove the file if it was the last.
# Lock-free by design: the EXIT trap must stay fast and never hang.
_pwdtintii_release() {
  [[ -n "${_PWDTINTII_REG:-}" && -f "$_PWDTINTII_REG" ]] || return 0
  local tmp="${_PWDTINTII_REG}.t" rc
  grep -v "^$$"$'\t' "$_PWDTINTII_REG" > "$tmp" 2>/dev/null; rc=$?
  if (( rc == 0 )); then
    mv "$tmp" "$_PWDTINTII_REG"
  elif (( rc == 1 )); then
    rm -f "$tmp" "$_PWDTINTII_REG" 2>/dev/null   # we were the only entry
  else
    rm -f "$tmp" 2>/dev/null                      # read error: leave registry as-is
  fi
}

# ── OSC 11 emission (validate hex; refuse to emit anything else) ─────────────
_pwdtintii_emit() {
  local hex="$1"
  [[ "$hex" == \#* ]] || hex="#$hex"
  [[ "$hex" =~ ^#[0-9a-fA-F]{6}$ ]] || return 1
  printf '\e]11;%s\a' "$hex"
}

# ── Public: apply ────────────────────────────────────────────────────────────
pwdtintii_apply() {
  (( ${#_pwdtintii_families[@]} == 0 )) && return 0
  local key family shade_idx
  key=$("$PWDTINTII_DIR_KEY_FN")

  if [[ -n "${_PWDTINTII_FORCED_FAMILY:-}" ]]; then
    family="$_PWDTINTII_FORCED_FAMILY"
  fi

  if [[ "${_PWDTINTII_PINNED:-}" != "$key" || -n "${_PWDTINTII_FORCE_REAPPLY:-}" ]]; then
    _pwdtintii_release
    local keyhash
    keyhash=$(printf '%s' "$key" | "$_PWDTINTII_HASHCMD" | cut -c1-12)
    shade_idx=$(_pwdtintii_pick_shade "$key" "" "$keyhash")
    _PWDTINTII_PINNED="$key"
    _PWDTINTII_SHADE_IDX="$shade_idx"
    _PWDTINTII_KEYHASH="$keyhash"
    [[ -z "${family:-}" ]] && family=$(_pwdtintii_family_for "$key")
    _PWDTINTII_FAMILY="$family"
    _PWDTINTII_REG="${PWDTINTII_SHADES_DIR}/${keyhash}.tsv"
    unset _PWDTINTII_FORCE_REAPPLY
  else
    # Same key as last prompt: nothing changed → just re-emit, no forks.
    shade_idx="$_PWDTINTII_SHADE_IDX"
    [[ -z "${family:-}" ]] && family="$_PWDTINTII_FAMILY"
  fi

  local shades
  read -r -a shades <<< "${_pwdtintii_shades[$family]}"
  _pwdtintii_emit "${shades[$shade_idx]}"
}

# ── Public: pick ─────────────────────────────────────────────────────────────
pwdtintii_pick() {
  local family="${1:-}"
  if [[ "$family" == "--auto" || "$family" == "-" ]]; then
    unset _PWDTINTII_FORCED_FAMILY
    _pwdtintii_restore
    return 0
  fi
  if [[ -z "$family" ]]; then
    if command -v fzf >/dev/null 2>&1; then
      family=$(_pwdtintii_pick_interactive) || { _pwdtintii_restore; return 0; }
      [[ -z "$family" ]] && { _pwdtintii_restore; return 0; }
    else
      _pwdtintii_pick_menu
      return $?
    fi
  fi
  if [[ -z "${_pwdtintii_shades[$family]:-}" ]]; then
    echo "pwdtintii: unknown family: $family" >&2
    echo "available: ${_pwdtintii_families[*]}" >&2
    return 1
  fi
  _PWDTINTII_FORCED_FAMILY="$family"
  _PWDTINTII_FORCE_REAPPLY=1
  pwdtintii_apply
}

# Reapply outside any command-substitution so the OSC reaches the terminal.
_pwdtintii_restore() {
  _PWDTINTII_FORCE_REAPPLY=1
  pwdtintii_apply
}

# fzf picker: prints the chosen family on stdout, propagates fzf's exit code.
# The caller handles cancel-restore — emitting from inside $() would be captured.
_pwdtintii_pick_interactive() {
  printf '%s\n' "${_pwdtintii_families[@]}" | \
    fzf \
      --prompt='pick family > ' \
      --height=100% \
      --reverse \
      --preview="$_pwdtintii_self/bin/pwdtintii preview-family {}" \
      --preview-window=right:50%:nowrap \
      --bind="change:first" \
      --bind="focus:execute-silent($_pwdtintii_self/bin/pwdtintii emit-family {})" \
      --header="↑↓ navigate · ENTER pin · ESC cancel"
}

# Numbered-menu fallback when fzf isn't available
_pwdtintii_pick_menu() {
  local i=1 fam
  echo "available families:"
  for fam in "${_pwdtintii_families[@]}"; do
    printf '  %2d) %s\n' "$i" "$fam"
    ((i++))
  done
  printf 'pick number (or family name): '
  local choice
  read -r choice
  [[ -z "$choice" ]] && return 0
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    # 10# forces base-10 so a leading zero (08, 09) isn't read as octal.
    if (( 10#$choice < 1 || 10#$choice > ${#_pwdtintii_families[@]} )); then
      echo "pwdtintii: out of range: $choice" >&2
      return 1
    fi
    fam="${_pwdtintii_families[$((10#$choice - 1))]}"
  else
    fam="$choice"
  fi
  [[ -z "$fam" ]] && { echo "pwdtintii: invalid choice" >&2; return 1; }
  pwdtintii_pick "$fam"
}

# ── Public: list ─────────────────────────────────────────────────────────────
pwdtintii_list() {
  local key; key=$("$PWDTINTII_DIR_KEY_FN")
  local resolved; resolved=$(_pwdtintii_family_for "$key")
  echo "current key:    $key"
  echo "current family: ${_PWDTINTII_FAMILY:-$resolved}${_PWDTINTII_FORCED_FAMILY:+ (forced)}"
  echo "current shade:  ${_PWDTINTII_SHADE_IDX:-?}"
  echo
  echo "families (${#_pwdtintii_families[@]}):"
  local fam
  for fam in "${_pwdtintii_families[@]}"; do
    printf '  %-15s %s\n' "$fam" "${_pwdtintii_shades[$fam]}"
  done
}

pwdtintii_reload() {
  _pwdtintii_load_palette
  _pwdtintii_load_overrides
  _PWDTINTII_FORCE_REAPPLY=1
  pwdtintii_apply
  echo "pwdtintii: reloaded (${#_pwdtintii_families[@]} families)"
}

# ── Public: the `pt` entry point ─────────────────────────────────────────────
# Bare `pwdtintii` opens the fzf action hub (printed cheat-sheet without fzf);
# `pwdtintii <cmd>` dispatches. The hub re-runs the chosen action through this
# same dispatcher, so the action catalog (bin/pwdtintii actions) and the case
# arms below stay in lockstep.
pwdtintii() {
  local sub="${1:-}"
  case "$sub" in
    "")
      if command -v fzf >/dev/null 2>&1; then
        _pwdtintii_hub
      else
        _pwdtintii_help
      fi
      ;;
    pick)            shift; pwdtintii_pick "$@" ;;
    list|ls)         pwdtintii_list ;;
    apply)           pwdtintii_apply ;;
    auto|off|unpin)  pwdtintii_pick --auto ;;
    reload)          pwdtintii_reload ;;
    preview)         "${_pwdtintii_self}/scripts/preview.sh" ;;
    contrast)        "${_pwdtintii_self}/scripts/contrast-check.sh" ;;
    help|-h|--help)  _pwdtintii_help ;;
    *)
      echo "pwdtintii: unknown command: $sub" >&2
      echo "try: pwdtintii help" >&2
      return 1 ;;
  esac
}

# fzf hub: list every action, preview its description, echo the chosen machine
# name (field 1). Cancel/empty → no output, the caller returns to the prompt.
_pwdtintii_menu_pick() {
  "${_pwdtintii_self}/bin/pwdtintii" actions \
    | fzf \
        --prompt='pwdtintii > ' \
        --height=100% \
        --reverse \
        --delimiter='\t' \
        --with-nth=2 \
        --preview="${_pwdtintii_self}/bin/pwdtintii describe-action {1}" \
        --preview-window=right:55%:wrap \
        --header="now: ${_PWDTINTII_FAMILY:-auto} ${_PWDTINTII_SHADE_IDX:-?} · ENTER run · ESC quit" \
    | cut -f1
}

# The hub loop: open the action menu, run the choice, come back to the menu.
# Display-only actions pause first so their output stays readable before the
# menu redraws over it. ESC at the menu (empty pick) — or q at a pause — exits.
_pwdtintii_hub() {
  local action
  while action=$(_pwdtintii_menu_pick); [[ -n "$action" ]]; do
    pwdtintii "$action"
    case "$action" in
      list|preview|contrast) _pwdtintii_pause || break ;;
    esac
  done
}

# Hold a display action's output on screen until a keypress: any key returns to
# the hub, q or ESC quits it (rc 1). Reads from /dev/tty so a redirected stdin
# can't swallow the keypress.
_pwdtintii_pause() {
  printf '\n  \e[2m— any key: back to menu · q: quit —\e[0m ' > /dev/tty
  local k
  read -rsn1 k < /dev/tty
  printf '\n' > /dev/tty
  [[ "$k" == q || "$k" == $'\e' ]] && return 1
  return 0
}

# Printed cheat-sheet: the no-fzf fallback for `pt`, and `pt help`.
_pwdtintii_help() {
  echo "pwdtintii — directory-derived terminal tinting"
  echo "  now: ${_PWDTINTII_FAMILY:-?} · shade ${_PWDTINTII_SHADE_IDX:-?}"
  echo
  echo "  pt                 open the action menu (this list without fzf)"
  echo "  pt pick [family]   pin a color family (live picker)"
  echo "  pt list            families + current mapping"
  echo "  pt auto            back to directory-derived auto (unpin)"
  echo "  pt reload          re-read the palette TSV"
  echo "  pt preview         visual dump of the whole palette"
  echo "  pt contrast        WCAG contrast check of all shades"
  echo "  pt help            this overview"
  echo
  echo "  aliases: ptpick · ptlist · ptreload · ptpreview · ptcontrast"
}

# ── Hooks ────────────────────────────────────────────────────────────────────
# PROMPT_COMMAND idiom: append, don't replace
_pwdtintii_load_palette
_pwdtintii_load_overrides
if (( ${#_pwdtintii_families[@]} == 0 )); then
  echo "pwdtintii: palette '$PWDTINTII_PALETTE' has no families — tinting disabled" >&2
fi

if [[ ";${PROMPT_COMMAND:-};" != *";pwdtintii_apply;"* ]]; then
  PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND%;};}pwdtintii_apply"
fi
trap _pwdtintii_release EXIT
