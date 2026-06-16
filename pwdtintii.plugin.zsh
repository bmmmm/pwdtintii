# pwdtintii — directory-derived terminal background tinting for zsh
# Hash the current dir → pick a color family; each split/shell in the same dir
# gets a distinct shade. No daemon, no persisted state, PID-tracked, OSC 11 only.
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
: ${PWDTINTII_PALETTE:="${_pwdtintii_self}/palettes/default.tsv"}
: ${PWDTINTII_SHADES_DIR:="${HOME}/.config/pwdtintii/shades"}
: ${PWDTINTII_DIR_KEY_FN:=_pwdtintii_default_key}

# Remember the plugin file + its load-time mtime so `pt` can flag a stale shell
# (file changed on disk after sourcing — re-source or open a new shell to apply).
# `command stat` forces the external binary (zsh/stat builtin reads -f as an fd).
_pwdtintii_mtime() { command stat -f %m "$1" 2>/dev/null || command stat -c %Y "$1" 2>/dev/null; }
_PWDTINTII_PLUGIN_FILE="${_pwdtintii_self}/pwdtintii.plugin.zsh"
_PWDTINTII_LOADED_MTIME="$(_pwdtintii_mtime "$_PWDTINTII_PLUGIN_FILE")"
_pwdtintii_is_stale() {
  local now; now="$(_pwdtintii_mtime "$_PWDTINTII_PLUGIN_FILE")"
  [[ -n "$now" && -n "$_PWDTINTII_LOADED_MTIME" && "$now" != "$_PWDTINTII_LOADED_MTIME" ]]
}

# Re-source the plugin into the running shell — the "reload the session" the
# stale notice used to only tell you to do by hand. Safe to re-run: the precmd
# hook registration dedupes (add-zsh-hook), re-running recaptures the load-time
# mtime (so the shell stops reporting stale), and the per-shell state survives —
# runtime globals (pinned/forced family, shade, disabled, PWD-cache) are left
# untouched by the boot path, and config like PWDTINTII_PALETTE is kept via `:=`.
_pwdtintii_resource() {
  [[ -f "$_PWDTINTII_PLUGIN_FILE" ]] || return 1
  # Parse-check before sourcing: a reload that lands mid-edit (the file saved
  # half-written) would otherwise redefine only part of the plugin into the live
  # shell while still printing normal output, so a broken reload reads as
  # success. `zsh -n` parses without executing; on a syntax error keep the
  # already-loaded, working definitions.
  command zsh -n "$_PWDTINTII_PLUGIN_FILE" 2>/dev/null || return 1
  source "$_PWDTINTII_PLUGIN_FILE"
}

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
  local family s0 s1 s2 s3 sh ok
  while IFS=$'\t' read -r family s0 s1 s2 s3; do
    [[ -z "$family" || "$family" == "family" || "$family" == \#* ]] && continue
    ok=1
    for sh in "$s0" "$s1" "$s2" "$s3"; do
      [[ "$sh" =~ '^#?[0-9a-fA-F]{6}$' ]] || ok=0
    done
    (( ok )) || { print -u2 -- "pwdtintii: palette: skipping '$family' — needs 4 '#rrggbb' shades"; continue; }
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

# Switch the active palette for this shell (the picker's dark/light toggle
# commits through here). Reloads families + overrides; does not re-emit.
_pwdtintii_set_palette() {
  [[ "$1" == "$PWDTINTII_PALETTE" ]] && return 0
  PWDTINTII_PALETTE="$1"
  _pwdtintii_load_palette
  _pwdtintii_load_overrides
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
  [[ -n "$_PWDTINTII_DISABLED" ]] && return 0
  local key family shade_idx
  # Cache the dir-key by $PWD: resolving it forks a subshell and stat-walks for
  # the git root on every prompt. Skip both while $PWD is unchanged. Tradeoff: a
  # fresh `git init` in the current dir is picked up on the next cd, not at once.
  if [[ "$PWD" != "$_PWDTINTII_LAST_PWD" || -z "$_PWDTINTII_LAST_KEY" ]]; then
    key=$($PWDTINTII_DIR_KEY_FN)
    _PWDTINTII_LAST_PWD="$PWD"
    _PWDTINTII_LAST_KEY="$key"
  else
    key="$_PWDTINTII_LAST_KEY"
  fi

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
  unset _PWDTINTII_DISABLED
  # Accept bare `auto` too, not just `--auto`/`-`: `pt pick auto` is the natural
  # conflation of `pt auto` and `pt pick <family>`, and no family is named auto.
  if [[ "$family" == "--auto" || "$family" == "auto" || "$family" == "-" ]]; then
    unset _PWDTINTII_FORCED_FAMILY
    _pwdtintii_restore
    return 0
  fi
  if [[ -z "$family" ]]; then
    if command -v fzf >/dev/null 2>&1; then
      local picked palfile
      picked=$(_pwdtintii_pick_interactive) || { _pwdtintii_restore; return 0; }
      [[ -z "$picked" ]] && { _pwdtintii_restore; return 0; }
      palfile="${picked%%$'\t'*}"
      family="${picked#*$'\t'}"
      # Committing a pick from the other group switches this shell's palette.
      [[ -n "$palfile" && "$palfile" != "$PWDTINTII_PALETTE" ]] && _pwdtintii_set_palette "$palfile"
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

# ── Public: stop tinting + reset the terminal background ─────────────────────
# Real off — unlike `auto`, which only unpins and keeps tinting by directory.
# Blanks our state, drops this shell's registry entry, and resets the background
# to the terminal default (OSC 111). Re-enable with pt pick / pt auto / pt reload.
pwdtintii_off() {
  _PWDTINTII_DISABLED=1
  unset _PWDTINTII_FORCED_FAMILY _PWDTINTII_PINNED _PWDTINTII_FAMILY \
        _PWDTINTII_SHADE_IDX _PWDTINTII_LAST_PWD _PWDTINTII_LAST_KEY
  _pwdtintii_release
  printf '\e]111\a'
}

# fzf picker. Prints "<palette-file>\t<family>" for the committed pick, so the
# caller can switch this shell to that group's palette. ctrl-t toggles between
# the bundled dark and light groups, so both stay reachable without listing all
# of them at once. Propagates fzf's exit code on cancel; the caller restores —
# emitting from inside $() would be captured.
#
# ctrl-t keeps fzf open and reloads the list/preview/header in place (transform →
# reload+change-preview+change-header) instead of restarting fzf per toggle — the
# restart was a full-screen redraw that flickered. A state dir carries the active
# palette so the live-tint focus bind and the committed pick read the current
# group across toggles. The dark/light step itself lives in bin/ (pick-toggle).
_pwdtintii_pick_interactive() {
  local dark="${_pwdtintii_self}/palettes/default.tsv"
  local light="${_pwdtintii_self}/palettes/light.tsv"
  local self="${_pwdtintii_self}/bin/pwdtintii"
  # Offer the toggle only with both bundled palettes in play; a custom
  # PWDTINTII_PALETTE gets a plain single-group picker (no ctrl-t).
  local group=dark toggle=1
  [[ "$PWDTINTII_PALETTE" == "$light" ]] && group=light
  if [[ ! -f "$light" || ( "$PWDTINTII_PALETTE" != "$dark" && "$PWDTINTII_PALETTE" != "$light" ) ]]; then
    toggle=0
  fi

  local grouppal label hdr
  if (( toggle )); then
    local other
    if [[ "$group" == light ]]; then grouppal="$light"; other=dark; else grouppal="$dark"; other=light; fi
    label="$group"
    hdr="↑↓ · ENTER pin · ctrl-t: ${other} theme · ESC cancel"
  else
    grouppal="$PWDTINTII_PALETTE"; label=family
    hdr="↑↓ navigate · ENTER pin · ESC cancel"
  fi

  local sd; sd="$(mktemp -d "${TMPDIR:-/tmp}/pwdtintii-pick.XXXXXX")"
  printf '%s\n' "$group" > "$sd/grp"
  printf '%s\n' "$grouppal" > "$sd/pal"

  # High-contrast menu over the focused family's live tint: the list carries its
  # own color per-line (list-menu + --ansi) so ctrl-t's reload reflows it
  # dark<->light in place. The chrome --color is theme-neutral gray (a static
  # --color can't recolor at runtime, and the tint flips dark<->light on toggle);
  # only the header reflows, carrying its own ANSI color (pick-header) and swapped
  # by pick-toggle's change-header. See bin/ cmd_fzf_theme / cmd_pick_header.
  local colorspec; colorspec="$(PWDTINTII_PALETTE="$grouppal" "$self" fzf-theme)"
  local chdr; chdr="$(PWDTINTII_PALETTE="$grouppal" "$self" pick-header "$hdr")"

  # enter/esc re-emit the terminal tint BEFORE fzf tears down, so no default-bg
  # flash shows between the picker closing and the prompt re-tinting (the picker
  # repaints the bg per focus): esc → emit-restore (the shell's pre-picker dir
  # tint, from the PWDTINTII_VIEW_* + palette handed to fzf below) then abort;
  # enter → re-emit the focused family's tint then accept (the commit path then
  # sets the real shade). ctrl-t passes the focused family ({}) to pick-toggle so
  # it flips the live tint to the new palette at once — see bin/ cmd_pick_toggle.
  local -a fzfargs=(
    --ansi
    --prompt="pick ${label} > "
    # 99%, not 100%: at 100% fzf takes over the alternate screen, whose
    # enter/leave repaints the whole frame and flashes the terminal's default
    # background on exit (the ESC flicker). Sub-100% keeps fzf inline — no
    # \e[?1049h/l, so closing it never repaints the frame.
    --height=99%
    --reverse
    --preview="PWDTINTII_PALETTE=${grouppal} ${self} preview-family {}"
    --preview-window=right:50%:nowrap
    --bind="change:first"
    --bind="focus:execute-silent(PWDTINTII_PALETTE=\"\$(cat ${sd}/pal)\" ${self} emit-family {})"
    --bind="enter:execute-silent(PWDTINTII_PALETTE=\"\$(cat ${sd}/pal)\" ${self} emit-family {})+accept"
    --bind="esc:execute-silent(${self} emit-restore)+abort"
    --color="$colorspec"
    --header="$chdr"
  )
  (( toggle )) && fzfargs+=( --bind="ctrl-t:transform(${self} pick-toggle ${sd} {})" )

  # PWDTINTII_VIEW_* + the pre-picker palette go to fzf (not exported) so the esc
  # emit-restore bind can restore the shell's tint; the focus/preview/ctrl-t binds
  # set their own PWDTINTII_PALETTE per call, so this only feeds emit-restore.
  local sel rc
  sel=$(PWDTINTII_PALETTE="$grouppal" "$self" list-menu \
    | PWDTINTII_PALETTE="$PWDTINTII_PALETTE" \
      PWDTINTII_VIEW_FAMILY="${_PWDTINTII_FAMILY:-}" \
      PWDTINTII_VIEW_SHADE="${_PWDTINTII_SHADE_IDX:-}" \
      fzf "${fzfargs[@]}")
  rc=$?
  # ctrl-t may have switched the group; the committed palette is whatever the
  # state dir now holds. Read it before removing the dir.
  grouppal="$(cat "$sd/pal" 2>/dev/null)"
  rm -rf "$sd"
  (( rc != 0 )) && return 1
  [[ -z "$sel" || -z "$grouppal" ]] && return 1
  print -r -- "${grouppal}"$'\t'"${sel}"
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
  unset _PWDTINTII_DISABLED
  _pwdtintii_load_palette
  _pwdtintii_load_overrides
  _PWDTINTII_FORCE_REAPPLY=1
  pwdtintii_apply
  print "pwdtintii: reloaded (${#_pwdtintii_families} families)"
}

# ── Public: diagnose the setup ───────────────────────────────────────────────
# The tool's main silent-failure mode is a terminal that ignores OSC 11. Surface
# the moving parts, then probe OSC 11 support live when attached to a terminal.
pwdtintii_doctor() {
  print "pwdtintii doctor"
  print "  hash command: $_PWDTINTII_HASHCMD"
  if command -v fzf >/dev/null 2>&1; then
    print "  fzf:          found (menus + live picker enabled)"
  else
    print "  fzf:          missing (menus fall back to a printed list)"
  fi
  if command -v python3 >/dev/null 2>&1; then
    print "  python3:      found (pt contrast enabled)"
  else
    print "  python3:      missing (pt contrast unavailable)"
  fi
  print "  palette:      $PWDTINTII_PALETTE (${#_pwdtintii_families} families)"
  print "  state:        family=${_PWDTINTII_FAMILY:-auto} shade=${_PWDTINTII_SHADE_IDX:-?} disabled=${_PWDTINTII_DISABLED:-0}"
  print "  terminal:     TERM=${TERM:-?} COLORTERM=${COLORTERM:-?} TERM_PROGRAM=${TERM_PROGRAM:-?}"
  if [[ ! -t 1 ]]; then
    print "  osc 11:       skipped (output is not a terminal)"
    return 0
  fi
  # Query the current background (OSC 11 with '?'); a compliant terminal answers
  # with an ESC-prefixed 'rgb:' sequence. Bounded read so we never hang; drain
  # the rest of the reply so it does not leak onto the next prompt.
  local reply=""
  printf '\e]11;?\a' > /dev/tty
  read -k1 -s -t 0.3 reply < /dev/tty 2>/dev/null
  if [[ -n "$reply" ]]; then
    while read -k1 -s -t 0.05 _ < /dev/tty 2>/dev/null; do : ; done
    print "  osc 11:       terminal responded — supported"
  else
    print "  osc 11:       no response — terminal may not support OSC 11 (tinting will be a no-op)"
  fi
}

# ── Public: the `pt` entry point ─────────────────────────────────────────────
# Bare `pwdtintii` opens the fzf action hub (printed cheat-sheet without fzf);
# `pwdtintii <cmd>` dispatches. The hub re-runs the chosen action through this
# same dispatcher, so the action catalog (bin/pwdtintii actions) and the case
# arms below stay in lockstep.
pwdtintii() {
  # Self-heal a stale shell: if the plugin file changed on disk since this shell
  # sourced it, re-source it before dispatching so `pt` always runs current code.
  # (This running pwdtintii keeps its already-parsed body for this one call, but
  # the actions it dispatches resolve to the freshly defined functions.)
  if _pwdtintii_is_stale; then
    if _pwdtintii_resource; then
      print -u2 -- "pwdtintii: plugin changed on disk — reloaded this shell"
    else
      print -u2 -- "pwdtintii: plugin changed on disk but the new version won't parse — keeping the running one"
    fi
  fi
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
    auto|unpin)      pwdtintii_pick --auto ;;
    off)             pwdtintii_off ;;
    doctor|diag)     pwdtintii_doctor ;;
    reload)          pwdtintii_reload ;;
    view)            PWDTINTII_PALETTE="$PWDTINTII_PALETTE" PWDTINTII_VIEW_FAMILY="${_PWDTINTII_FAMILY:-}" PWDTINTII_VIEW_SHADE="${_PWDTINTII_SHADE_IDX:-}" "${_pwdtintii_self}/bin/pwdtintii" view
                     pwdtintii_apply ;;   # safety net: the viewer restores the tint itself on enter/esc (before fzf clears, so no flash); this also re-emits after ctrl-c
    preview)         pwdtintii view ;;    # back-compat: the old static dump is now view
    contrast)        "${_pwdtintii_self}/scripts/contrast-check.sh" ;;
    help|-h|--help)  _pwdtintii_help ;;
    *)
      print -u2 -- "pwdtintii: unknown command: $sub"
      print -u2 -- "try: pwdtintii help"
      return 1 ;;
  esac
}

# fzf hub: list every action, preview its description, echo the chosen machine
# name (field 1). Cancel/empty → no output, the caller returns to the prompt.
# --height stays under 100% so fzf renders inline: at exactly 100% it takes the
# alternate screen, and that buffer switch repaints the frame and flashes the
# terminal's default background on exit (the ESC flicker).
_pwdtintii_menu_pick() {
  local hdr="now: ${_PWDTINTII_FAMILY:-auto} ${_PWDTINTII_SHADE_IDX:-?} · ENTER run · ESC quit"
  _pwdtintii_is_stale && hdr="plugin changed — re-source · ${hdr}"
  "${_pwdtintii_self}/bin/pwdtintii" actions \
    | fzf \
        --prompt='pwdtintii > ' \
        --height=99% \
        --reverse \
        --delimiter='\t' \
        --with-nth=2 \
        --preview="${_pwdtintii_self}/bin/pwdtintii describe-action {1}" \
        --preview-window=right:55%:wrap \
        --header="$hdr" \
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
      list|contrast) _pwdtintii_pause || break ;;
    esac
  done
}

# Hold a display action's output on screen until a keypress: q (or Q) quits the
# hub (rc 1), any other key returns to the menu. `read -k` reads the controlling
# terminal directly (it ignores fd redirects), so no `< /dev/tty` is needed.
# Arrow keys etc. arrive as an ESC-prefixed sequence — drain the tail so it is
# not fed to the next fzf as a search query.
_pwdtintii_pause() {
  print -n -- $'\n  \e[2m— any key: back to menu · q: quit —\e[0m ' > /dev/tty
  local k
  read -k1 -s k
  print -- "" > /dev/tty
  [[ "$k" == [qQ] ]] && return 1
  [[ "$k" == $'\e' ]] && while read -k1 -s -t 0.05 k; do : ; done
  return 0
}

# Printed cheat-sheet: the no-fzf fallback for `pt`, and `pt help`.
_pwdtintii_help() {
  print -r -- "pwdtintii — directory-derived terminal tinting"
  print -r -- "  now: ${_PWDTINTII_FAMILY:-?} · shade ${_PWDTINTII_SHADE_IDX:-?}"
  _pwdtintii_is_stale && print -r -- "  (plugin changed on disk — re-source or open a new shell)"
  print
  print -r -- "  pt                 open the action menu (this list without fzf)"
  print -r -- "  pt pick [family]   pin a color family (picker; ctrl-t: dark/light)"
  print -r -- "  pt view            browse the palette (colored; ctrl-t cycles)"
  print -r -- "  pt list            families + current mapping"
  print -r -- "  pt auto            back to directory-derived auto (unpin)"
  print -r -- "  pt off             stop tinting + reset the terminal background"
  print -r -- "  pt reload          re-read the palette TSV"
  print -r -- "  pt contrast        WCAG + APCA contrast of all shades"
  print -r -- "  pt doctor          diagnose terminal OSC 11 / fzf / palette"
  print -r -- "  pt help            this overview"
  print
  print -r -- "  aliases: ptpick · ptlist · ptreload · ptview · ptcontrast"
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
