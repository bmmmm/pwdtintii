# pwdtintii — directory-derived terminal background tinting for zsh
# Hash the current dir → pick a color family; each split/shell in the same dir
# gets a distinct shade. No daemon, no persisted state, PID-tracked, OSC 11 only.
#
# Public functions:
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
: ${PWDTINTII_PALETTE:="${_pwdtintii_self}/palettes/default.tsv"}
: ${PWDTINTII_SHADES_DIR:="${HOME}/.config/pwdtintii/shades"}
: ${PWDTINTII_DIR_KEY_FN:=_pwdtintii_default_key}

typeset -gA _pwdtintii_shades
typeset -ga _pwdtintii_families
typeset -gA _pwdtintii_overrides

# Hash command: shasum (macOS) or sha1sum (Linux). Fail loudly if neither.
if (( $+commands[shasum] )); then
  _PWDTINTII_HASHCMD=shasum
elif (( $+commands[sha1sum] )); then
  _PWDTINTII_HASHCMD=sha1sum
else
  print -u2 "pwdtintii: needs 'shasum' or 'sha1sum' on PATH"
  return 1
fi

# ── Palette loader ───────────────────────────────────────────────────────────
_pwdtintii_load_palette() {
  _pwdtintii_shades=()
  _pwdtintii_families=()
  local family s0 s1 s2 s3
  while IFS=$'\t' read -r family s0 s1 s2 s3; do
    [[ -z "$family" || "$family" == "family" || "$family" == \#* ]] && continue
    _pwdtintii_shades[$family]="$s0 $s1 $s2 $s3"
    _pwdtintii_families+=($family)
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
    local rel="${PWD#"${HOME}"/}"
    print -r -- "${HOME}/${rel%%/*}"
  else
    print -r -- "/${${PWD#/}%%/*}"
  fi
}

# ── Family resolver: override > hash → family ────────────────────────────────
_pwdtintii_family_for() {
  local key="$1"
  (( ${#_pwdtintii_families} == 0 )) && return 1
  local proj="${key##*/}"
  if [[ -n "$proj" && -n "${_pwdtintii_overrides[$proj]}" ]]; then
    print -r -- "${_pwdtintii_overrides[$proj]}"
    return
  fi
  local h
  h=$(print -rn -- "$key" | $_PWDTINTII_HASHCMD | cut -c1-8)
  print -r -- "$_pwdtintii_families[$(( 0x$h % ${#_pwdtintii_families} + 1 ))]"
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
  [[ -n "$locked" ]] && print -r -- "$my_pid" > "$lock/pid"

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
  [[ -n "$locked" ]] && { rm -f "$lock/pid" 2>/dev/null; rmdir "$lock" 2>/dev/null; }
  print -r -- "$pick"
}

# Drop this shell's entry from its registry; remove the file if it was the last.
# Lock-free by design: the exit hook must stay fast and never hang.
_pwdtintii_release() {
  [[ -n "$_PWDTINTII_REG" && -f "$_PWDTINTII_REG" ]] || return 0
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
  [[ "$hex" =~ '^#[0-9a-fA-F]{6}$' ]] || return 1
  printf '\e]11;%s\a' "$hex"
}

# ── Public: apply current dir's color ────────────────────────────────────────
pwdtintii_apply() {
  (( ${#_pwdtintii_families} == 0 )) && return 0
  local key family shade_idx
  key=$($PWDTINTII_DIR_KEY_FN)

  if [[ -n "$_PWDTINTII_FORCED_FAMILY" ]]; then
    family="$_PWDTINTII_FORCED_FAMILY"
  fi

  if [[ "$_PWDTINTII_PINNED" != "$key" || -n "$_PWDTINTII_FORCE_REAPPLY" ]]; then
    _pwdtintii_release
    local keyhash
    keyhash=$(print -rn -- "$key" | $_PWDTINTII_HASHCMD | cut -c1-12)
    shade_idx=$(_pwdtintii_pick_shade "$key" "" "$keyhash")
    _PWDTINTII_PINNED="$key"
    _PWDTINTII_SHADE_IDX="$shade_idx"
    _PWDTINTII_KEYHASH="$keyhash"
    [[ -z "$family" ]] && family=$(_pwdtintii_family_for "$key")
    _PWDTINTII_FAMILY="$family"
    _PWDTINTII_REG="${PWDTINTII_SHADES_DIR}/${keyhash}.tsv"
    unset _PWDTINTII_FORCE_REAPPLY
  else
    # Same key as last prompt: nothing changed → just re-emit, no forks.
    shade_idx="$_PWDTINTII_SHADE_IDX"
    [[ -z "$family" ]] && family="$_PWDTINTII_FAMILY"
  fi

  local shades=(${=_pwdtintii_shades[$family]})
  _pwdtintii_emit "${shades[$(( shade_idx + 1 ))]}"
}

# ── Public: pin a family for this shell ──────────────────────────────────────
pwdtintii_pick() {
  local family="$1"
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
  if [[ -z "${_pwdtintii_shades[$family]}" ]]; then
    print -u2 -- "pwdtintii: unknown family: $family"
    print -u2 -- "available: $_pwdtintii_families"
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
      --height=40% \
      --reverse \
      --preview="$_pwdtintii_self/bin/pwdtintii preview-family {}" \
      --preview-window=right:50%:wrap \
      --bind="change:first" \
      --bind="focus:execute-silent($_pwdtintii_self/bin/pwdtintii emit-family {})" \
      --header="↑↓ navigate · ENTER pin · ESC cancel"
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
    if (( choice < 1 || choice > ${#_pwdtintii_families} )); then
      print -u2 "pwdtintii: out of range: $choice"
      return 1
    fi
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
  print "current shade:  ${_PWDTINTII_SHADE_IDX:-?}"
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
if (( ${#_pwdtintii_families} == 0 )); then
  print -u2 "pwdtintii: palette '$PWDTINTII_PALETTE' has no families — tinting disabled"
fi

autoload -Uz add-zsh-hook
add-zsh-hook precmd _pwdtintii_precmd
add-zsh-hook zshexit _pwdtintii_release
