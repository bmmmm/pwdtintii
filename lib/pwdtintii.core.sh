# pwdtintii — shared core for the zsh and bash plugins.
#
# This file is NOT sourced directly. Each entry point (pwdtintii.plugin.zsh /
# pwdtintii.plugin.bash) resolves its own location, sets a few shell-specific
# shims, then sources this core and registers the prompt hook its own way. The
# two plugins were ~80% byte-identical; that shared body lives here once, written
# in the constructs both shells agree on, with the genuine divergences behind a
# tiny shim the entry point provides:
#
#   _pwdtintii_self    absolute plugin dir (entry point resolves it per shell)
#   _PWDTINTII_PLUGIN_FILE  the entry point's own path (for the stale check)
#   _PT_AOFF           indexed-array base: 1 (zsh) or 0 (bash)
#   _PT_SPLIT          scratch array filled by _pt_split (declared below)
#   _pt_split <str>    word-split a "s0 s1 s2 s3" string into _PT_SPLIT
#   _pt_readkey <var> [timeout]   read one silent key into <var> (optional -t)
#   _PT_SHELLCHECK     argv array running this shell's `-n` parse check
#
# Everything else here is portable between zsh and bash: printf over print,
# "${arr[@]}" / ${#arr[@]} over bare-array forms, typeset -g (a declare synonym
# in bash), command -v over (( $+commands )), and ERE matches via a pattern
# variable (`re='…'; [[ x =~ $re ]]`) so neither shell's quoting rule bites.

# This core is a fragment: the entry-point adapter assigns _pwdtintii_self,
# _PWDTINTII_PLUGIN_FILE, the _PT_* shims and the PWDTINTII_* config before
# sourcing it, so suppress the "referenced but not assigned" check file-wide.
# shellcheck disable=SC2154

typeset -gA _pwdtintii_shades
typeset -ga _pwdtintii_families
typeset -gA _pwdtintii_overrides
typeset -ga _PT_SPLIT

# Hash command: shasum (macOS) or sha1sum (Linux). Set at boot; fail loudly if
# neither is on PATH (the family hash can't be computed without one).
_pt_detect_hashcmd() {
  if command -v shasum >/dev/null 2>&1; then
    _PWDTINTII_HASHCMD=shasum
  elif command -v sha1sum >/dev/null 2>&1; then
    _PWDTINTII_HASHCMD=sha1sum
  else
    printf '%s\n' "pwdtintii: needs 'shasum' or 'sha1sum' on PATH" >&2
    return 1
  fi
}

# Remember the plugin file + its load-time mtime so `pt` can flag a stale shell
# (file changed on disk after sourcing — re-source or open a new shell to apply).
# `command stat` forces the external binary. BSD stat uses `-f %m` (macOS);
# GNU stat treats `-f` as --file-system (filesystem mode) and would output
# changing filesystem stats instead of the mtime — capture first and only
# print on exit 0, else fall back to GNU `-c %Y`.
_pwdtintii_mtime() {
  local t; t=$(command stat -f %m "$1" 2>/dev/null) && printf '%s\n' "$t" \
    || command stat -c %Y "$1" 2>/dev/null
}
_pwdtintii_is_stale() {
  local now; now="$(_pwdtintii_mtime "$_PWDTINTII_PLUGIN_FILE")"
  [[ -n "$now" && -n "$_PWDTINTII_LOADED_MTIME" && "$now" != "$_PWDTINTII_LOADED_MTIME" ]]
}

# Re-source the plugin into the running shell — the "reload the session" the
# stale notice used to only tell you to do by hand. Safe to re-run: the entry
# point's hook registration dedupes (zsh add-zsh-hook membership / bash one-shot
# flag), re-sourcing recaptures the load-time mtime (so the shell stops reporting
# stale), and the per-shell state survives — runtime globals (pinned/forced
# family, shade, disabled, PWD-cache) are left untouched by the boot path, and
# config like PWDTINTII_PALETTE is kept via the entry point's defaults guard.
_pwdtintii_resource() {
  [[ -f "$_PWDTINTII_PLUGIN_FILE" ]] || return 1
  # Parse-check before sourcing: a reload that lands mid-edit (the file saved
  # half-written) would otherwise redefine only part of the plugin into the live
  # shell while still printing normal output, so a broken reload reads as
  # success. `<shell> -n` parses without executing; on a syntax error keep the
  # already-loaded, working definitions.
  "${_PT_SHELLCHECK[@]}" -n "$_PWDTINTII_PLUGIN_FILE" 2>/dev/null || return 1
  # shellcheck source=/dev/null  # dynamic self-path; resolved at runtime
  source "$_PWDTINTII_PLUGIN_FILE"
}

# ── Palette loader ───────────────────────────────────────────────────────────
_pwdtintii_load_palette() {
  _pwdtintii_shades=()
  _pwdtintii_families=()
  local family s0 s1 s2 s3 sh ok
  local hexre='^#?[0-9a-fA-F]{6}$'
  # keep a newline-less last row (file read raw, no grep/sed to re-add the \n)
  while IFS=$'\t' read -r family s0 s1 s2 s3 || [[ -n "$family" ]]; do
    [[ -z "$family" || "$family" == "family" || "$family" == \#* ]] && continue
    ok=1
    for sh in "$s0" "$s1" "$s2" "$s3"; do
      [[ "$sh" =~ $hexre ]] || ok=0
    done
    (( ok )) || { printf '%s\n' "pwdtintii: palette: skipping '$family' — needs 4 '#rrggbb' shades" >&2; continue; }
    _pwdtintii_shades[$family]="$s0 $s1 $s2 $s3"
    _pwdtintii_families+=("$family")
  done < "$PWDTINTII_PALETTE"
}

_pwdtintii_load_overrides() {
  _pwdtintii_overrides=()
  [[ -z "${PWDTINTII_OVERRIDES_FILE:-}" || ! -f "$PWDTINTII_OVERRIDES_FILE" ]] && return
  local proj family
  # keep a newline-less last row (file read raw, no grep/sed to re-add the \n)
  while IFS=$'\t' read -r proj family || [[ -n "$proj" ]]; do
    [[ -z "$proj" || "$proj" == \#* ]] && continue
    _pwdtintii_overrides[$proj]=$family
  done < "$PWDTINTII_OVERRIDES_FILE"
}

# Switch the active palette for this shell (the picker's dark/light toggle
# commits through here). Reloads families + overrides; does not re-emit.
_pwdtintii_set_palette() {
  [[ "$1" -ef "$PWDTINTII_PALETTE" ]] && return 0
  PWDTINTII_PALETTE="$1"
  _pwdtintii_load_palette
  _pwdtintii_load_overrides
}

# ── Dir-key strategy: git-root or first path component under $HOME ────────────
_pwdtintii_default_key() {
  local dir="$PWD"
  while [[ "$dir" != "/" && "$dir" != "$HOME" ]]; do
    # -e, not -d: in a worktree or submodule .git is a *file* (a gitdir pointer),
    # and -d would skip it — the worktree then keys on ~/<top> and loses its color.
    [[ -e "$dir/.git" ]] && { printf '%s\n' "$dir"; return; }
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
  printf '%s\n' "${_pwdtintii_families[$(( _PT_AOFF + 0x$h % ${#_pwdtintii_families[@]} ))]}"
}

# ── Shade picker: per-key registry, PID-GC, mkdir-locked read-modify-write ───
# Takes the precomputed keyhash (the prompt hot-path caches it); the key itself
# is not needed — the registry file is named by the hash alone.
_pwdtintii_pick_shade() {
  local keyhash="$1" my_pid=$$
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
  local pick=0
  for pick in 0 1 2 3; do [[ -z "${in_use[$pick]:-}" ]] && break; done
  printf '%s\t%s\t%s\n' "$my_pid" "$pick" "$(date +%s)" >> "${reg}.new"
  mv "${reg}.new" "$reg"
  [[ -n "$locked" ]] && { rm -f "$lock/pid" 2>/dev/null; rmdir "$lock" 2>/dev/null; }
  printf '%s\n' "$pick"
}

# Drop this shell's entry from its registry; remove the file if it was the last.
# Lock-free by design: the exit hook must stay fast and never hang.
_pwdtintii_release() {
  # `:-` on every state-var read so the plugin survives a user's `setopt nounset`.
  [[ -n "${_PWDTINTII_REG:-}" && -f "${_PWDTINTII_REG:-}" ]] || return 0
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
# Inside tmux, OSC 11 tints the *global* terminal background shared by all panes.
# Sibling panes in the same terminal would race and overwrite each other's colour.
# Use tmux select-pane -P instead to set a per-pane background that stays isolated.
_pwdtintii_emit() {
  local hex="$1"
  local hexre='^#[0-9a-fA-F]{6}$'
  [[ "$hex" == \#* ]] || hex="#$hex"
  [[ "$hex" =~ $hexre ]] || return 1
  if [[ -n "${TMUX:-}" ]]; then
    tmux select-pane -P "bg=$hex" 2>/dev/null || true
  else
    printf '\e]11;%s\a' "$hex"
  fi
}

# ── Public: apply current dir's color ────────────────────────────────────────
pwdtintii_apply() {
  (( ${#_pwdtintii_families[@]} == 0 )) && return 0
  [[ -n "${_PWDTINTII_DISABLED:-}" ]] && return 0
  local key family shade_idx
  # Cache the dir-key by $PWD: resolving it forks a subshell and stat-walks for
  # the git root on every prompt. Skip both while $PWD is unchanged. Tradeoff: a
  # fresh `git init` in the current dir is picked up on the next cd, not at once.
  if [[ "$PWD" != "${_PWDTINTII_LAST_PWD:-}" || -z "${_PWDTINTII_LAST_KEY:-}" ]]; then
    key=$("$PWDTINTII_DIR_KEY_FN")
    _PWDTINTII_LAST_PWD="$PWD"
    _PWDTINTII_LAST_KEY="$key"
  else
    key="$_PWDTINTII_LAST_KEY"
  fi

  if [[ -n "${_PWDTINTII_FORCED_FAMILY:-}" ]]; then
    family="$_PWDTINTII_FORCED_FAMILY"
  fi

  if [[ "${_PWDTINTII_PINNED:-}" != "$key" || -n "${_PWDTINTII_FORCE_REAPPLY:-}" ]]; then
    _pwdtintii_release
    local keyhash
    keyhash=$(printf '%s' "$key" | "$_PWDTINTII_HASHCMD" | cut -c1-12)
    shade_idx=$(_pwdtintii_pick_shade "$keyhash")
    _PWDTINTII_PINNED="$key"
    _PWDTINTII_SHADE_IDX="$shade_idx"
    [[ -z "${family:-}" ]] && family=$(_pwdtintii_family_for "$key")
    _PWDTINTII_FAMILY="$family"
    _PWDTINTII_REG="${PWDTINTII_SHADES_DIR}/${keyhash}.tsv"
    unset _PWDTINTII_FORCE_REAPPLY
  else
    # Same key as last prompt: nothing changed → just re-emit, no forks.
    shade_idx="$_PWDTINTII_SHADE_IDX"
    [[ -z "${family:-}" ]] && family="$_PWDTINTII_FAMILY"
  fi

  # `:-` here too: empty shades (family gone from the palette) is an out-of-range
  # read, fatal under nounset. _pt_split + _PT_AOFF bridge the index base (zsh
  # 1-based, bash 0-based) so both shells select the same physical shade.
  _pt_split "${_pwdtintii_shades[$family]:-}"
  _pwdtintii_emit "${_PT_SPLIT[$(( _PT_AOFF + shade_idx ))]:-}"
}

# ── Public: pin a family for this shell ──────────────────────────────────────
pwdtintii_pick() {
  local family="${1:-}"
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
      [[ -n "$palfile" && ! "$palfile" -ef "$PWDTINTII_PALETTE" ]] && _pwdtintii_set_palette "$palfile"
    else
      _pwdtintii_pick_menu
      return $?
    fi
  fi
  if [[ -z "${_pwdtintii_shades[$family]:-}" ]]; then
    printf '%s\n' "pwdtintii: unknown family: $family" >&2
    printf '%s\n' "available: ${_pwdtintii_families[*]}" >&2
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
  # Keep _PWDTINTII_REG set: if release left our entry pending on a transient
  # read error, the exit-time release reuses the path to retry; apply re-sets it.
  if [[ -n "${TMUX:-}" ]]; then
    tmux select-pane -P 'bg=default' 2>/dev/null || true
  else
    printf '\e]111\a'
  fi
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
  # Compare by inode (-ef) not string: a committed PWDTINTII_PALETTE can carry a
  # bin/.. or symlinked form that string-mismatches the bundled paths. CLI does too.
  [[ "$PWDTINTII_PALETTE" -ef "$light" ]] && group=light
  if [[ ! -f "$light" || ( ! "$PWDTINTII_PALETTE" -ef "$dark" && ! "$PWDTINTII_PALETTE" -ef "$light" ) ]]; then
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
  # sets the real shade). ctrl-t chains transform(pick-toggle) — which flips the
  # group + records the new palette in $sd/pal — with execute-silent(emit-family
  # {}) under that new palette, the same coordinated path as focus: emitting the
  # tint as a raw side effect *inside* the transform races fzf's renderer and gets
  # dropped, so the bg used to lag a toggle behind. See bin/ cmd_pick_toggle.
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
  (( toggle )) && fzfargs+=( --bind="ctrl-t:transform(${self} pick-toggle ${sd})+execute-silent(PWDTINTII_PALETTE=\"\$(cat ${sd}/pal)\" ${self} emit-family {})" )

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
  printf '%s\t%s\n' "$grouppal" "$sel"
}

# Numbered-menu fallback when fzf isn't available
_pwdtintii_pick_menu() {
  local i=1 fam
  printf '%s\n' "available families:"
  for fam in "${_pwdtintii_families[@]}"; do
    printf '  %2d) %s\n' "$i" "$fam"
    (( i++ ))
  done
  printf 'pick number (or family name): '
  local choice
  read -r choice
  [[ -z "$choice" ]] && return 0
  local numre='^[0-9]+$'
  if [[ "$choice" =~ $numre ]]; then
    # 10# forces base-10 so a leading zero (08, 09) isn't read as octal.
    if (( 10#$choice < 1 || 10#$choice > ${#_pwdtintii_families[@]} )); then
      printf '%s\n' "pwdtintii: out of range: $choice" >&2
      return 1
    fi
    fam="${_pwdtintii_families[$(( _PT_AOFF + 10#$choice - 1 ))]}"
  else
    fam="$choice"
  fi
  [[ -z "$fam" ]] && { printf '%s\n' "pwdtintii: invalid choice" >&2; return 1; }
  pwdtintii_pick "$fam"
}

# ── Public: list families + current key/family of this shell ─────────────────
pwdtintii_list() {
  local key; key=$("$PWDTINTII_DIR_KEY_FN")
  local resolved; resolved=$(_pwdtintii_family_for "$key")
  printf '%s\n' "current key:    $key"
  printf '%s\n' "current family: ${_PWDTINTII_FAMILY:-$resolved}${_PWDTINTII_FORCED_FAMILY:+ (forced)}"
  printf '%s\n' "current shade:  ${_PWDTINTII_SHADE_IDX:-?}"
  printf '\n'
  printf '%s\n' "families (${#_pwdtintii_families[@]}):"
  local fam
  for fam in "${_pwdtintii_families[@]}"; do
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
  printf '%s\n' "pwdtintii: reloaded (${#_pwdtintii_families[@]} families)"
}

# ── Public: diagnose the setup ───────────────────────────────────────────────
# The tool's main silent-failure mode is a terminal that ignores OSC 11. Surface
# the moving parts, then probe OSC 11 support live when attached to a terminal.
pwdtintii_doctor() {
  printf '%s\n' "pwdtintii doctor"
  printf '%s\n' "  hash command: $_PWDTINTII_HASHCMD"
  if command -v fzf >/dev/null 2>&1; then
    printf '%s\n' "  fzf:          found (menus + live picker enabled)"
  else
    printf '%s\n' "  fzf:          missing (menus fall back to a printed list)"
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "  python3:      found (pt contrast enabled)"
  else
    printf '%s\n' "  python3:      missing (pt contrast unavailable)"
  fi
  printf '%s\n' "  palette:      $PWDTINTII_PALETTE (${#_pwdtintii_families[@]} families)"
  printf '%s\n' "  state:        family=${_PWDTINTII_FAMILY:-auto} shade=${_PWDTINTII_SHADE_IDX:-?} disabled=${_PWDTINTII_DISABLED:-0}"
  printf '%s\n' "  terminal:     TERM=${TERM:-?} COLORTERM=${COLORTERM:-?} TERM_PROGRAM=${TERM_PROGRAM:-?}"
  if [[ ! -t 1 ]]; then
    printf '%s\n' "  osc 11:       skipped (output is not a terminal)"
    return 0
  fi
  # Query the current background (OSC 11 with '?'); a compliant terminal answers
  # with an ESC-prefixed 'rgb:' sequence. Bounded read so we never hang; drain
  # the rest of the reply so it does not leak onto the next prompt.
  local reply=""
  printf '\e]11;?\a' > /dev/tty
  _pt_readkey reply 0.3 < /dev/tty 2>/dev/null || true
  if [[ -n "$reply" ]]; then
    while _pt_readkey _ 0.05 < /dev/tty 2>/dev/null; do : ; done
    printf '%s\n' "  osc 11:       terminal responded — supported"
  else
    printf '%s\n' "  osc 11:       no response — terminal may not support OSC 11 (tinting will be a no-op)"
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
      printf '%s\n' "pwdtintii: plugin changed on disk — reloaded this shell" >&2
    else
      printf '%s\n' "pwdtintii: plugin changed on disk but the new version won't parse — keeping the running one" >&2
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
    version)
      local _v
      if [[ -r "${_pwdtintii_self}/VERSION" ]]; then
        _v="$(< "${_pwdtintii_self}/VERSION")"
        _v="${_v%%[[:space:]]*}"
      else
        _v="(version unknown)"
      fi
      printf '%s\n' "pwdtintii ${_v}" ;;
    help|-h|--help)  _pwdtintii_help ;;
    *)
      printf '%s\n' "pwdtintii: unknown command: $sub" >&2
      printf '%s\n' "try: pwdtintii help" >&2
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
  # Size the split to the content, not a fixed ratio: give the list pane just
  # enough columns for its widest "name + gloss" row (and the header) so fzf
  # stops ellipsizing the gloss — the menu's whole point — and hand the rest to
  # the preview, which reflows to whatever width it gets (describe-action reads
  # FZF_PREVIEW_COLUMNS). Too narrow to fit both side by side: stack the preview
  # below so the list keeps the full width.
  local actions; actions=$("${_pwdtintii_self}/bin/pwdtintii" actions)
  local cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
  # + 6 ≈ fzf's pointer/marker gutter plus a column of slack, so the row never
  # quite touches the pane edge (which would bring the ellipsis back).
  local list_w; list_w=$(printf '%s\n' "$actions" \
    | awk -F'\t' '{ if (length($2) > m) m = length($2) } END { print m + 6 }')
  if (( ${#hdr} + 6 > list_w )); then list_w=$(( ${#hdr} + 6 )); fi
  local pvw
  if (( cols - list_w >= 30 )); then
    pvw="right:$(( cols - list_w )):wrap"
  else
    pvw='down:55%:wrap'
  fi
  printf '%s\n' "$actions" \
    | fzf \
        --prompt='pwdtintii > ' \
        --height=99% \
        --reverse \
        --delimiter='\t' \
        --with-nth=2 \
        --preview="${_pwdtintii_self}/bin/pwdtintii describe-action {1}" \
        --preview-window="$pvw" \
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
      list|contrast|doctor) _pwdtintii_pause || break ;;
    esac
  done
}

# Hold a display action's output on screen until a keypress: q (or Q) quits the
# hub (rc 1), any other key returns to the menu. Reads one silent key from the
# controlling terminal (via _pt_readkey). Arrow keys etc. arrive as an
# ESC-prefixed sequence — drain the tail so it is not fed to the next fzf.
_pwdtintii_pause() {
  printf '\n  \e[2m— any key: back to menu · q: quit —\e[0m ' > /dev/tty
  local k
  _pt_readkey k < /dev/tty
  printf '\n' > /dev/tty
  [[ "$k" == [qQ] ]] && return 1
  [[ "$k" == $'\e' ]] && while _pt_readkey k 0.05 < /dev/tty; do : ; done
  return 0
}

# Printed cheat-sheet: the no-fzf fallback for `pt`, and `pt help`.
_pwdtintii_help() {
  printf '%s\n' "pwdtintii — directory-derived terminal tinting"
  printf '%s\n' "  now: ${_PWDTINTII_FAMILY:-?} · shade ${_PWDTINTII_SHADE_IDX:-?}"
  _pwdtintii_is_stale && printf '%s\n' "  (plugin changed on disk — re-source or open a new shell)"
  printf '\n'
  printf '%s\n' "  pt                 open the action menu (this list without fzf)"
  printf '%s\n' "  pt pick [family]   pin a color family (picker; ctrl-t: dark/light)"
  printf '%s\n' "  pt view            browse the palette (colored; ctrl-t cycles)"
  printf '%s\n' "  pt list            families + current mapping"
  printf '%s\n' "  pt auto            back to directory-derived auto (unpin)"
  printf '%s\n' "  pt off             stop tinting + reset the terminal background"
  printf '%s\n' "  pt reload          re-read the palette TSV"
  printf '%s\n' "  pt contrast        WCAG + APCA contrast of all shades"
  printf '%s\n' "  pt doctor          diagnose terminal OSC 11 / fzf / palette"
  printf '%s\n' "  pt help            this overview"
  printf '%s\n' "  pt version         print the installed version"
  printf '\n'
  printf '%s\n' "  aliases: ptpick · ptlist · ptreload · ptview · ptcontrast"
}

# ── Hooks ────────────────────────────────────────────────────────────────────
# Preserve $? around the tint emit so the status the prompt shows — a bash PROMPT
# that reads a captured $? (and zsh's %?) — is the user's last command, not
# pwdtintii_apply's (which would always read 0). The entry point registers this
# the shell's own way (zsh add-zsh-hook precmd / bash PROMPT_COMMAND).
_pwdtintii_precmd() { local __pt_rc=$?; pwdtintii_apply; return "$__pt_rc"; }

# ── Boot ─────────────────────────────────────────────────────────────────────
# Detect the hash command, load the palette + overrides, warn on an empty
# palette. Returns non-zero only when no hash command exists (the entry point
# then skips hook registration — tinting can't work without it). An empty
# palette is survivable: warn, return 0, let apply no-op.
_pt_boot() {
  # Capture the entry point's load-time mtime so a later `pt` can spot a
  # changed-on-disk plugin; a self-reload re-runs boot and recaptures it, which
  # is how the stale flag clears without a manual re-source.
  _PWDTINTII_LOADED_MTIME="$(_pwdtintii_mtime "$_PWDTINTII_PLUGIN_FILE")"
  _pt_detect_hashcmd || return 1
  _pwdtintii_load_palette
  _pwdtintii_load_overrides
  if (( ${#_pwdtintii_families[@]} == 0 )); then
    printf '%s\n' "pwdtintii: palette '$PWDTINTII_PALETTE' has no families — tinting disabled" >&2
  fi
  return 0
}
