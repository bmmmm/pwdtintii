# pwdtintii — directory-derived terminal background tinting for bash 4+
# Hash the current dir → pick a color family; each split/shell in the same dir
# gets a distinct shade. No daemon, PID-tracked, OSC 11 only.
#
# Requires bash 4+ (associative arrays). On macOS install via `brew install bash`.
#
# Public functions:
#   pwdtintii_apply          — re-apply background color to current shell
#   pwdtintii_pick [family]  — pin a family for this shell (fzf picker if no arg)
#   pwdtintii_list           — list families with current dir mapping
#   pwdtintii_reload         — re-load the palette TSV
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

# ── Resolve own location ─────────────────────────────────────────────────────
_pwdtintii_self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${PWDTINTII_PALETTE:=${_pwdtintii_self}/palettes/default.tsv}"
: "${PWDTINTII_SHADES_DIR:=${HOME}/.config/pwdtintii/shades}"
: "${PWDTINTII_DIR_KEY_FN:=_pwdtintii_default_key}"

declare -gA _pwdtintii_shades
declare -ga _pwdtintii_families
declare -gA _pwdtintii_overrides

# Hash command: shasum (macOS) or sha1sum (Linux)
if command -v shasum >/dev/null 2>&1; then
  _PWDTINTII_HASHCMD=shasum
else
  _PWDTINTII_HASHCMD=sha1sum
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

# ── Dir-key strategy ─────────────────────────────────────────────────────────
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
    local rel="${PWD#${HOME}/}"
    printf '%s\n' "${HOME}/${rel%%/*}"
  else
    printf '%s\n' "/${PWD#/}"
  fi
}

# ── Family resolver: override > hash → family ────────────────────────────────
_pwdtintii_family_for() {
  local key="$1"
  local proj="${key##*/}"
  if [[ -n "${_pwdtintii_overrides[$proj]:-}" ]]; then
    printf '%s\n' "${_pwdtintii_overrides[$proj]}"
    return
  fi
  local h
  h=$(printf '%s' "$key" | "$_PWDTINTII_HASHCMD" | cut -c1-8)
  local idx=$(( 0x$h % ${#_pwdtintii_families[@]} ))
  printf '%s\n' "${_pwdtintii_families[$idx]}"
}

# ── Shade picker ─────────────────────────────────────────────────────────────
_pwdtintii_pick_shade() {
  local key="$1" forced="${2:-}" my_pid=$$
  mkdir -p "$PWDTINTII_SHADES_DIR"
  local keyhash
  keyhash=$(printf '%s' "$key" | "$_PWDTINTII_HASHCMD" | cut -c1-12)
  local reg="${PWDTINTII_SHADES_DIR}/${keyhash}.tsv"
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
  printf '%s\n' "$pick"
}

_pwdtintii_release() {
  [[ -n "${_PWDTINTII_REG:-}" && -f "$_PWDTINTII_REG" ]] && {
    grep -v "^$$"$'\t' "$_PWDTINTII_REG" > "${_PWDTINTII_REG}.t" 2>/dev/null \
      && mv "${_PWDTINTII_REG}.t" "$_PWDTINTII_REG"
  }
}

_pwdtintii_emit() {
  printf '\e]11;%s\a' "$1"
}

# ── Public: apply ────────────────────────────────────────────────────────────
pwdtintii_apply() {
  local key family shade_idx
  key=$("$PWDTINTII_DIR_KEY_FN")

  if [[ -n "${_PWDTINTII_FORCED_FAMILY:-}" ]]; then
    family="$_PWDTINTII_FORCED_FAMILY"
  fi

  if [[ "${_PWDTINTII_PINNED:-}" != "$key" || -n "${_PWDTINTII_FORCE_REAPPLY:-}" ]]; then
    _pwdtintii_release
    shade_idx=$(_pwdtintii_pick_shade "$key")
    _PWDTINTII_PINNED="$key"
    _PWDTINTII_SHADE_IDX="$shade_idx"
    [[ -z "${family:-}" ]] && family=$(_pwdtintii_family_for "$key")
    _PWDTINTII_FAMILY="$family"
    local keyhash
    keyhash=$(printf '%s' "$key" | "$_PWDTINTII_HASHCMD" | cut -c1-12)
    _PWDTINTII_REG="${PWDTINTII_SHADES_DIR}/${keyhash}.tsv"
    unset _PWDTINTII_FORCE_REAPPLY
  else
    shade_idx="$_PWDTINTII_SHADE_IDX"
    [[ -z "${family:-}" ]] && family="$_PWDTINTII_FAMILY"
    _pwdtintii_pick_shade "$key" "$shade_idx" > /dev/null
  fi

  local shades
  read -r -a shades <<< "${_pwdtintii_shades[$family]}"
  _pwdtintii_emit "${shades[$shade_idx]}"
}

# ── Public: pick ─────────────────────────────────────────────────────────────
pwdtintii_pick() {
  local family="${1:-}"
  if [[ -z "$family" ]]; then
    if command -v fzf >/dev/null 2>&1; then
      family=$(_pwdtintii_pick_interactive)
      [[ -z "$family" ]] && return 0
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

_pwdtintii_pick_interactive() {
  printf '%s\n' "${_pwdtintii_families[@]}" | \
    fzf \
      --prompt='pick family > ' \
      --height=40% \
      --reverse \
      --preview="$_pwdtintii_self/bin/pwdtintii preview-family {}" \
      --preview-window=right:50%:wrap \
      --bind="focus:execute-silent($_pwdtintii_self/bin/pwdtintii emit-family {})" \
      --header="↑↓ navigate · ENTER pin · ESC cancel"
  local rc=$?
  if (( rc != 0 )); then
    _PWDTINTII_FORCE_REAPPLY=1
    pwdtintii_apply
  fi
  return $rc
}

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
    fam="${_pwdtintii_families[$((choice - 1))]}"
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

# ── Hooks ────────────────────────────────────────────────────────────────────
# PROMPT_COMMAND idiom: append, don't replace
_pwdtintii_load_palette
_pwdtintii_load_overrides

if [[ ";${PROMPT_COMMAND:-};" != *";pwdtintii_apply;"* ]]; then
  PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND%;};}pwdtintii_apply"
fi
trap _pwdtintii_release EXIT
