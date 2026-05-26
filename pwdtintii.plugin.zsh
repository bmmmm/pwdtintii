# pwdtintii — directory-derived terminal background tinting for zsh
# Hash the current dir → pick a color family; each split/shell in the same dir
# gets a distinct shade. No daemon, PID-tracked, OSC 11 only.
#
# Public functions:
#   pwdtintii_apply          — re-apply background color to current shell
#   pwdtintii_pick [family]  — pin a family for this shell (fzf picker if no arg)
#   pwdtintii_list           — list families with their current dir mapping
#   pwdtintii_reload         — re-load the palette TSV
#
# Config (set BEFORE sourcing):
#   PWDTINTII_PALETTE         — path to palette TSV (default: $plugin_dir/palettes/default.tsv)
#   PWDTINTII_OVERRIDES_FILE  — optional TSV of named overrides: project_basename<TAB>family
#   PWDTINTII_SHADES_DIR      — runtime PID-registry dir (default: ~/.config/pwdtintii/shades)
#   PWDTINTII_DIR_KEY_FN      — optional shell function name to resolve $PWD → key (default: _pwdtintii_default_key)

# ── Resolve own location so we can find the default palette ──────────────────
_pwdtintii_self="${${(%):-%x}:A:h}"
: ${PWDTINTII_PALETTE:="${_pwdtintii_self}/palettes/default.tsv"}
: ${PWDTINTII_SHADES_DIR:="${HOME}/.config/pwdtintii/shades"}
: ${PWDTINTII_DIR_KEY_FN:=_pwdtintii_default_key}

typeset -gA _pwdtintii_shades
typeset -ga _pwdtintii_families
typeset -gA _pwdtintii_overrides

# ── Palette loader ───────────────────────────────────────────────────────────
_pwdtintii_load_palette() {
  _pwdtintii_shades=()
  _pwdtintii_families=()
  local family s0 s1 s2 s3 line
  while IFS=$'\t' read -r family s0 s1 s2 s3; do
    [[ -z "$family" || "$family" == "family" || "$family" == \#* ]] && continue
    _pwdtintii_shades[$family]="$s0 $s1 $s2 $s3"
    _pwdtintii_families+=($family)
  done < "$PWDTINTII_PALETTE"
}

_pwdtintii_load_overrides() {
  _pwdtintii_overrides=()
  [[ -z "$PWDTINTII_OVERRIDES_FILE" || ! -f "$PWDTINTII_OVERRIDES_FILE" ]] && return
  local proj family
  while IFS=$'\t' read -r proj family; do
    [[ -z "$proj" || "$proj" == \#* ]] && continue
    _pwdtintii_overrides[$proj]=$family
  done < "$PWDTINTII_OVERRIDES_FILE"
}

# ── Dir-key strategy: git-root or first path component under $HOME ───────────
_pwdtintii_default_key() {
  local dir="$PWD"
  while [[ "$dir" != "/" && "$dir" != "$HOME" ]]; do
    [[ -d "$dir/.git" ]] && { print -r -- "$dir"; return; }
    dir="${dir:h}"
  done
  if [[ "$PWD" == "$HOME" ]]; then
    print -r -- "$HOME"
  elif [[ "$PWD" == "$HOME"/* ]]; then
    local rel="${PWD#${HOME}/}"
    print -r -- "${HOME}/${rel%%/*}"
  else
    print -r -- "/${${PWD#/}%%/*}"
  fi
}

# ── Family resolver: override > hash → family ────────────────────────────────
_pwdtintii_family_for() {
  local key="$1"
  local proj="${key##*/}"
  if [[ -n "${_pwdtintii_overrides[$proj]}" ]]; then
    print -r -- "${_pwdtintii_overrides[$proj]}"
    return
  fi
  local h
  h=$(print -rn -- "$key" | shasum | cut -c1-8)
  print -r -- "$_pwdtintii_families[$(( 0x$h % ${#_pwdtintii_families} + 1 ))]"
}

# ── Shade picker: per-key registry, PID-GC ───────────────────────────────────
_pwdtintii_pick_shade() {
  local key="$1" forced="${2:-}" my_pid=$$
  mkdir -p "$PWDTINTII_SHADES_DIR"
  local reg="${PWDTINTII_SHADES_DIR}/$(print -r -- "$key" | shasum | cut -c1-12).tsv"
  : > "${reg}.new"
  local -A in_use
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
    for pick in 0 1 2 3; do [[ -z "${in_use[$pick]}" ]] && break; done
  fi
  printf '%s\t%s\t%s\n' "$my_pid" "$pick" "$(date +%s)" >> "${reg}.new"
  mv "${reg}.new" "$reg"
  print -r -- "$pick"
}

_pwdtintii_release() {
  [[ -n "$_PWDTINTII_REG" && -f "$_PWDTINTII_REG" ]] && {
    grep -v "^$$	" "$_PWDTINTII_REG" > "${_PWDTINTII_REG}.t" 2>/dev/null \
      && mv "${_PWDTINTII_REG}.t" "$_PWDTINTII_REG"
  }
}

# ── OSC 11 emission ──────────────────────────────────────────────────────────
_pwdtintii_emit() {
  local hex="$1"
  printf '\e]11;%s\a' "$hex"
}

# ── Public: apply current dir's color ────────────────────────────────────────
pwdtintii_apply() {
  local key family shade_idx
  key=$($PWDTINTII_DIR_KEY_FN)

  if [[ -n "$_PWDTINTII_FORCED_FAMILY" ]]; then
    family="$_PWDTINTII_FORCED_FAMILY"
  fi

  if [[ "$_PWDTINTII_PINNED" != "$key" || -n "$_PWDTINTII_FORCE_REAPPLY" ]]; then
    _pwdtintii_release
    shade_idx=$(_pwdtintii_pick_shade "$key")
    _PWDTINTII_PINNED="$key"
    _PWDTINTII_SHADE_IDX="$shade_idx"
    [[ -z "$family" ]] && family=$(_pwdtintii_family_for "$key")
    _PWDTINTII_FAMILY="$family"
    _PWDTINTII_REG="${PWDTINTII_SHADES_DIR}/$(print -r -- "$key" | shasum | cut -c1-12).tsv"
    unset _PWDTINTII_FORCE_REAPPLY
  else
    shade_idx="$_PWDTINTII_SHADE_IDX"
    [[ -z "$family" ]] && family="$_PWDTINTII_FAMILY"
    _pwdtintii_pick_shade "$key" "$shade_idx" > /dev/null
  fi

  local shades=(${=_pwdtintii_shades[$family]})
  _pwdtintii_emit "${shades[$(( shade_idx + 1 ))]}"
}

# ── Public: pin a family for this shell ──────────────────────────────────────
pwdtintii_pick() {
  local family="$1"
  if [[ -z "$family" ]]; then
    if command -v fzf >/dev/null 2>&1; then
      family=$(_pwdtintii_pick_interactive)
      [[ -z "$family" ]] && return 0
    else
      _pwdtintii_pick_menu
      return $?
    fi
  fi
  if [[ -z "${_pwdtintii_shades[$family]}" ]]; then
    print -u2 -- "pwdtintii: unknown family: $family"
    print -u2 -- "available: $_pwdtintii_families"
    return 1
  fi
  _PWDTINTII_FORCED_FAMILY="$family"
  _PWDTINTII_FORCE_REAPPLY=1
  pwdtintii_apply
}

# fzf-based picker with live OSC 11 preview as the cursor moves
_pwdtintii_pick_interactive() {
  local current_bg="${_PWDTINTII_FAMILY:-}"
  printf '%s\n' "${_pwdtintii_families[@]}" | \
    fzf \
      --prompt='pick family > ' \
      --height=40% \
      --reverse \
      --preview="$_pwdtintii_self/bin/pwdtintii preview-family {}" \
      --preview-window=right:50%:wrap \
      --bind="change:first" \
      --bind="focus:execute-silent($_pwdtintii_self/bin/pwdtintii emit-family {})" \
      --header="↑↓ navigate · ENTER pin · ESC cancel"
  local rc=$?
  # Restore previous bg if user cancelled
  if (( rc != 0 )); then
    _PWDTINTII_FORCE_REAPPLY=1
    pwdtintii_apply
  fi
  return $rc
}

# Numbered-menu fallback when fzf isn't available
_pwdtintii_pick_menu() {
  local i=1 fam
  print "available families:"
  for fam in $_pwdtintii_families; do
    printf '  %2d) %s\n' "$i" "$fam"
    (( i++ ))
  done
  printf 'pick number (or family name): '
  local choice
  read -r choice
  [[ -z "$choice" ]] && return 0
  if [[ "$choice" == <-> ]]; then
    fam="$_pwdtintii_families[$choice]"
  else
    fam="$choice"
  fi
  [[ -z "$fam" ]] && { print -u2 "pwdtintii: invalid choice"; return 1 }
  pwdtintii_pick "$fam"
}

# ── Public: list families + current key/family of this shell ─────────────────
pwdtintii_list() {
  local key=$($PWDTINTII_DIR_KEY_FN)
  local resolved=$(_pwdtintii_family_for "$key")
  print "current key:    $key"
  print "current family: ${_PWDTINTII_FAMILY:-$resolved}${_PWDTINTII_FORCED_FAMILY:+ (forced)}"
  print "current shade:  $_PWDTINTII_SHADE_IDX"
  print
  print "families (${#_pwdtintii_families}):"
  local fam
  for fam in $_pwdtintii_families; do
    printf '  %-15s %s\n' "$fam" "${_pwdtintii_shades[$fam]}"
  done
}

# ── Public: reload palette ───────────────────────────────────────────────────
pwdtintii_reload() {
  _pwdtintii_load_palette
  _pwdtintii_load_overrides
  _PWDTINTII_FORCE_REAPPLY=1
  pwdtintii_apply
  print "pwdtintii: reloaded (${#_pwdtintii_families} families)"
}

# ── Hooks ────────────────────────────────────────────────────────────────────
_pwdtintii_precmd() { pwdtintii_apply }

# ── Boot ─────────────────────────────────────────────────────────────────────
_pwdtintii_load_palette
_pwdtintii_load_overrides

autoload -Uz add-zsh-hook
add-zsh-hook precmd _pwdtintii_precmd
add-zsh-hook zshexit _pwdtintii_release
