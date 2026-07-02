# pwdtintii — directory-derived terminal background tinting for fish 3.5+
# (needs the `path` builtin, fish 3.5; --on-event fish_exit, fish 3.2)
# Hash the current dir → pick a color family; each split/shell in the same dir
# gets a distinct shade. No daemon, no persisted state, PID-tracked, OSC 11 (or,
# inside tmux, a per-pane background). A native port of the zsh/bash plugins; the
# parity bats suite pins key/family/registry/emit byte-for-byte across all three.
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
#   PWDTINTII_DIR_KEY_FN      — optional function name resolving $PWD → key (default: _pwdtintii_default_key)

# ── Resolve own location (path resolve follows symlinks + makes absolute) ─────
set -g _pwdtintii_self (path dirname (path resolve (status -f)))
set -q PWDTINTII_PALETTE; or set -g PWDTINTII_PALETTE "$_pwdtintii_self/palettes/default.tsv"
set -q PWDTINTII_SHADES_DIR; or set -g PWDTINTII_SHADES_DIR "$HOME/.config/pwdtintii/shades"
set -q PWDTINTII_DIR_KEY_FN; or set -g PWDTINTII_DIR_KEY_FN _pwdtintii_default_key

# Remember the plugin file + its load-time mtime so `pt` can flag a stale shell
# (file changed on disk after sourcing — re-source or open a new shell to apply).
set -g _PWDTINTII_PLUGIN_FILE "$_pwdtintii_self/pwdtintii.plugin.fish"
function _pwdtintii_mtime
    # BSD stat (-f %m, macOS) exits 0 and prints the mtime; GNU stat (-f means
    # --file-system) exits non-zero and leaks filesystem stats into the output —
    # capture first, only print on exit 0, else fall back to GNU -c %Y.
    set -l t (command stat -f %m "$argv[1]" 2>/dev/null)
    and printf '%s\n' $t
    or command stat -c %Y "$argv[1]" 2>/dev/null
end
set -g _PWDTINTII_LOADED_MTIME (_pwdtintii_mtime "$_PWDTINTII_PLUGIN_FILE")
function _pwdtintii_is_stale
    set -l now (_pwdtintii_mtime "$_PWDTINTII_PLUGIN_FILE")
    test -n "$now"; and test -n "$_PWDTINTII_LOADED_MTIME"; and test "$now" != "$_PWDTINTII_LOADED_MTIME"
end

# Re-source the plugin into the running shell — the "reload the session" the
# stale notice tells you to do. Parse-check first (`fish -n`): a reload that lands
# mid-edit (file saved half-written) would otherwise redefine only part of the
# plugin while still printing normal output, so a broken reload reads as success.
# Per-shell runtime state survives (globals + config kept via `set -q`).
function _pwdtintii_resource
    test -f "$_PWDTINTII_PLUGIN_FILE"; or return 1
    fish -n "$_PWDTINTII_PLUGIN_FILE" 2>/dev/null; or return 1
    source "$_PWDTINTII_PLUGIN_FILE"
end

# Hash command: shasum (macOS) or sha1sum (Linux). Fail loudly if neither.
if command -q shasum
    set -g _PWDTINTII_HASHCMD shasum
else if command -q sha1sum
    set -g _PWDTINTII_HASHCMD sha1sum
else
    printf '%s\n' "pwdtintii: needs 'shasum' or 'sha1sum' on PATH" >&2
end

# ── Palette loader ────────────────────────────────────────────────────────────
# No associative arrays in fish: keep families + shades as parallel lists, the
# shade row stored as one "s0 s1 s2 s3" element. `_pwdtintii_shades_for` looks up
# by name via `contains -i`. The `|| test -n "$family"` guard keeps a newline-less
# last row (file read raw, no grep/sed upstream to re-add the \n), matching bash/zsh.
function _pwdtintii_load_palette
    set -g _pwdtintii_families
    set -g _pwdtintii_shades
    while read -d \t -l family s0 s1 s2 s3 || test -n "$family"
        if test -z "$family"; or test "$family" = "family"; or string match -q '#*' -- $family
            continue
        end
        set -l ok 1
        for sh in $s0 $s1 $s2 $s3
            string match -qr '^#?[0-9a-fA-F]{6}$' -- $sh; or set ok 0
        end
        if test $ok -eq 0
            printf '%s\n' "pwdtintii: palette: skipping '$family' — needs 4 '#rrggbb' shades" >&2
            continue
        end
        set -a _pwdtintii_families $family
        set -a _pwdtintii_shades "$s0 $s1 $s2 $s3"
    end <"$PWDTINTII_PALETTE"
end

function _pwdtintii_load_overrides
    set -g _pwdtintii_override_keys
    set -g _pwdtintii_override_fams
    test -n "$PWDTINTII_OVERRIDES_FILE"; and test -f "$PWDTINTII_OVERRIDES_FILE"; or return
    while read -d \t -l proj family || test -n "$proj"
        if test -z "$proj"; or string match -q '#*' -- $proj
            continue
        end
        set -a _pwdtintii_override_keys $proj
        set -a _pwdtintii_override_fams $family
    end <"$PWDTINTII_OVERRIDES_FILE"
end

# Shades row ("s0 s1 s2 s3") for a family, or nothing. Parallel-list lookup.
function _pwdtintii_shades_for
    set -l i (contains -i -- $argv[1] $_pwdtintii_families)
    test -n "$i"; and printf '%s\n' $_pwdtintii_shades[$i]
end

# Switch the active palette for this shell (the picker's dark/light toggle commits
# through here). Reloads families + overrides; does not re-emit.
function _pwdtintii_set_palette
    test "$argv[1]" -ef "$PWDTINTII_PALETTE"; and return 0
    set -g PWDTINTII_PALETTE "$argv[1]"
    _pwdtintii_load_palette
    _pwdtintii_load_overrides
end

# ── Dir-key strategy: git-root or first path component under $HOME ────────────
function _pwdtintii_default_key
    set -l dir $PWD
    while test "$dir" != "/"; and test "$dir" != "$HOME"
        # -e, not -d: in a worktree or submodule .git is a *file* (a gitdir
        # pointer), and -d would skip it — the worktree loses its repo color.
        if test -e "$dir/.git"
            printf '%s\n' $dir
            return
        end
        set dir (path dirname $dir)
    end
    if test "$PWD" = "$HOME"
        printf '%s\n' $HOME
    else if string match -q -- "$HOME/*" "$PWD"
        set -l rel (string replace -- "$HOME/" "" "$PWD")
        printf '%s\n' "$HOME/"(string replace -r -- '/.*' '' $rel)
    else
        set -l rel (string replace -r -- '^/' '' "$PWD")
        printf '%s\n' "/"(string replace -r -- '/.*' '' $rel)
    end
end

# ── Family resolver: override > hash → family ────────────────────────────────
function _pwdtintii_family_for
    set -l key $argv[1]
    test (count $_pwdtintii_families) -gt 0; or return 1
    set -l proj (string replace -r -- '.*/' '' $key)
    if test -n "$proj"
        set -l oi (contains -i -- $proj $_pwdtintii_override_keys)
        if test -n "$oi"
            printf '%s\n' $_pwdtintii_override_fams[$oi]
            return
        end
    end
    set -l h (printf '%s' $key | $_PWDTINTII_HASHCMD | cut -c1-8)
    # fish arrays are 1-based, so + 1 (bash uses 0-based, zsh also + 1).
    set -l idx (math "0x$h % "(count $_pwdtintii_families)" + 1")
    printf '%s\n' $_pwdtintii_families[$idx]
end

# ── Shade picker: per-key registry, PID-GC, mkdir-locked read-modify-write ───
# Bit-compatible with the bash/zsh registry format (pid<TAB>shade<TAB>ts) so a
# fish shell and a zsh/bash shell in the same dir share one registry and get
# distinct shades. Takes the precomputed keyhash as $3 so the prompt hot-path can
# cache it.
function _pwdtintii_pick_shade
    set -l key $argv[1]
    set -l forced $argv[2]
    set -l keyhash $argv[3]
    set -l my_pid $fish_pid
    set -l reg "$PWDTINTII_SHADES_DIR/$keyhash.tsv"
    set -l lock "$reg.lock"
    mkdir -p "$PWDTINTII_SHADES_DIR"

    # Bounded, fail-open lock around the read-modify-write so concurrently starting
    # shells don't clobber each other's entry. A prompt never hangs.
    set -l locked ""
    set -l pidless 0
    for i in 1 2 3 4 5 6 7 8 9 10
        if mkdir "$lock" 2>/dev/null
            set locked 1
            break
        end
        set -l lpid ""
        test -f "$lock/pid"; and read -l lpid <"$lock/pid" 2>/dev/null
        if test -n "$lpid"
            set pidless 0
            if not kill -0 $lpid 2>/dev/null # holder is dead → steal
                rm -f "$lock/pid" 2>/dev/null
                rmdir "$lock" 2>/dev/null
                continue
            end
        else
            # Lock with no pid yet: give the holder a moment, but if it stays
            # pid-less across a few polls it's an orphan (holder died between mkdir
            # and the pid write). rmdir fails safe if the pid landed meanwhile.
            set pidless (math $pidless + 1)
            if test $pidless -ge 3
                rmdir "$lock" 2>/dev/null
                set pidless 0
                continue
            end
        end
        sleep 0.05
    end
    test -n "$locked"; and printf '%s\n' $my_pid >"$lock/pid"

    printf '' >"$reg.new"
    set -l in_use
    if test -f "$reg"
        while read -d \t -l pid sh ts
            test "$pid" = "$my_pid"; and continue
            kill -0 $pid 2>/dev/null; or continue
            set -a in_use $sh
            printf '%s\t%s\t%s\n' $pid $sh $ts >>"$reg.new"
        end <"$reg"
    end
    set -l pick
    if test -n "$forced"
        set pick $forced
    else
        set pick 0
        for p in 0 1 2 3
            if not contains -- $p $in_use
                set pick $p
                break
            end
        end
    end
    printf '%s\t%s\t%s\n' $my_pid $pick (date +%s) >>"$reg.new"
    mv "$reg.new" "$reg"
    if test -n "$locked"
        rm -f "$lock/pid" 2>/dev/null
        rmdir "$lock" 2>/dev/null
    end
    printf '%s\n' $pick
end

# Drop this shell's entry from its registry; remove the file if it was the last.
# Lock-free by design: the exit handler must stay fast and never hang.
function _pwdtintii_release
    test -n "$_PWDTINTII_REG"; and test -f "$_PWDTINTII_REG"; or return 0
    set -l tmp "$_PWDTINTII_REG.t"
    grep -v "^$fish_pid"\t "$_PWDTINTII_REG" >"$tmp" 2>/dev/null
    set -l rc $status
    if test $rc -eq 0
        mv "$tmp" "$_PWDTINTII_REG"
    else if test $rc -eq 1
        rm -f "$tmp" "$_PWDTINTII_REG" 2>/dev/null # we were the only entry
    else
        rm -f "$tmp" 2>/dev/null # read error: leave registry as-is
    end
end

# ── OSC 11 emission (validate hex; refuse to emit anything else) ─────────────
# Inside tmux, OSC 11 tints the *global* terminal background shared by all panes.
# Sibling panes in the same terminal would race and overwrite each other's colour.
# Use tmux select-pane -P instead to set a per-pane background that stays isolated.
function _pwdtintii_emit
    set -l hex $argv[1]
    string match -q '#*' -- $hex; or set hex "#$hex"
    string match -qr '^#[0-9a-fA-F]{6}$' -- $hex; or return 1
    if test -n "$TMUX"
        tmux select-pane -P "bg=$hex" 2>/dev/null; or true
    else
        printf '\e]11;%s\a' $hex
    end
end

# ── Public: apply current dir's color ────────────────────────────────────────
function pwdtintii_apply
    test (count $_pwdtintii_families) -gt 0; or return 0
    test -n "$_PWDTINTII_DISABLED"; and return 0
    set -l key
    set -l family
    set -l shade_idx
    # Cache the dir-key by $PWD: resolving it forks + stat-walks for the git root
    # every prompt. Skip both while $PWD is unchanged.
    if test "$PWD" != "$_PWDTINTII_LAST_PWD"; or test -z "$_PWDTINTII_LAST_KEY"
        set key ($PWDTINTII_DIR_KEY_FN)
        set -g _PWDTINTII_LAST_PWD $PWD
        set -g _PWDTINTII_LAST_KEY $key
    else
        set key $_PWDTINTII_LAST_KEY
    end

    if test -n "$_PWDTINTII_FORCED_FAMILY"
        set family $_PWDTINTII_FORCED_FAMILY
    end

    if test "$_PWDTINTII_PINNED" != "$key"; or test -n "$_PWDTINTII_FORCE_REAPPLY"
        _pwdtintii_release
        set -l keyhash (printf '%s' $key | $_PWDTINTII_HASHCMD | cut -c1-12)
        set shade_idx (_pwdtintii_pick_shade $key "" $keyhash)
        set -g _PWDTINTII_PINNED $key
        set -g _PWDTINTII_SHADE_IDX $shade_idx
        test -z "$family"; and set family (_pwdtintii_family_for $key)
        set -g _PWDTINTII_FAMILY $family
        set -g _PWDTINTII_REG "$PWDTINTII_SHADES_DIR/$keyhash.tsv"
        set -e _PWDTINTII_FORCE_REAPPLY
    else
        # Same key as last prompt: nothing changed → just re-emit, no forks.
        set shade_idx $_PWDTINTII_SHADE_IDX
        test -z "$family"; and set family $_PWDTINTII_FAMILY
    end

    set -l shades (string split ' ' -- (_pwdtintii_shades_for $family))
    # Empty shades (family gone from the palette) → no-op, like the other shells.
    test (count $shades) -ge 1; or return 0
    _pwdtintii_emit $shades[(math $shade_idx + 1)]
end

# ── Public: pin a family for this shell ──────────────────────────────────────
function pwdtintii_pick
    set -l family $argv[1]
    set -e _PWDTINTII_DISABLED
    # Accept bare `auto` too, not just `--auto`/`-`.
    if test "$family" = "--auto"; or test "$family" = "auto"; or test "$family" = "-"
        set -e _PWDTINTII_FORCED_FAMILY
        _pwdtintii_restore
        return 0
    end
    if test -z "$family"
        if command -q fzf
            set -l picked (_pwdtintii_pick_interactive)
            or begin
                _pwdtintii_restore
                return 0
            end
            test -n "$picked"; or begin
                _pwdtintii_restore
                return 0
            end
            set -l palfile (string split -m1 \t -- $picked)[1]
            set family (string split -m1 \t -- $picked)[2]
            # Committing a pick from the other group switches this shell's palette.
            if test -n "$palfile"; and not test "$palfile" -ef "$PWDTINTII_PALETTE"
                _pwdtintii_set_palette "$palfile"
            end
        else
            _pwdtintii_pick_menu
            return $status
        end
    end
    set -l fam_shades (_pwdtintii_shades_for $family)
    if test -z "$fam_shades"
        printf '%s\n' "pwdtintii: unknown family: $family" >&2
        printf '%s\n' "available: $_pwdtintii_families" >&2
        return 1
    end
    set -g _PWDTINTII_FORCED_FAMILY $family
    set -g _PWDTINTII_FORCE_REAPPLY 1
    pwdtintii_apply
end

# Reapply outside any command-substitution so the OSC reaches the terminal.
function _pwdtintii_restore
    set -g _PWDTINTII_FORCE_REAPPLY 1
    pwdtintii_apply
end

# ── Public: stop tinting + reset the terminal background ─────────────────────
# Real off — unlike `auto`, which only unpins and keeps tinting by directory.
function pwdtintii_off
    set -g _PWDTINTII_DISABLED 1
    set -e _PWDTINTII_FORCED_FAMILY
    set -e _PWDTINTII_PINNED
    set -e _PWDTINTII_FAMILY
    set -e _PWDTINTII_SHADE_IDX
    set -e _PWDTINTII_LAST_PWD
    set -e _PWDTINTII_LAST_KEY
    _pwdtintii_release
    # Keep _PWDTINTII_REG set: if release left our entry pending on a transient
    # read error, the exit-time release reuses the path to retry; apply re-sets it.
    if test -n "$TMUX"
        tmux select-pane -P 'bg=default' 2>/dev/null; or true
    else
        printf '\e]111\a'
    end
end

# fzf picker. Prints "<palette-file>\t<family>" for the committed pick. ctrl-t
# toggles dark/light. The fzf binds call bin/pwdtintii with POSIX `VAR=val cmd`
# syntax, so force SHELL=/bin/sh: fzf runs execute/preview/transform under $SHELL,
# and fish can't parse that syntax. The dark/light + live-tint logic lives in bin/.
function _pwdtintii_pick_interactive
    set -l dark "$_pwdtintii_self/palettes/default.tsv"
    set -l light "$_pwdtintii_self/palettes/light.tsv"
    set -l self "$_pwdtintii_self/bin/pwdtintii"
    set -l group dark
    set -l toggle 1
    test "$PWDTINTII_PALETTE" -ef "$light"; and set group light
    if not test -f "$light"; or begin
            not test "$PWDTINTII_PALETTE" -ef "$dark"; and not test "$PWDTINTII_PALETTE" -ef "$light"
        end
        set toggle 0
    end

    set -l grouppal
    set -l label
    set -l hdr
    if test $toggle -eq 1
        set -l other
        if test "$group" = light
            set grouppal "$light"
            set other dark
        else
            set grouppal "$dark"
            set other light
        end
        set label "$group"
        set hdr "↑↓ · ENTER pin · ctrl-t: $other theme · ESC cancel"
    else
        set grouppal "$PWDTINTII_PALETTE"
        set label family
        set hdr "↑↓ navigate · ENTER pin · ESC cancel"
    end

    set -l sd (mktemp -d "$TMPDIR"/pwdtintii-pick.XXXXXX 2>/dev/null; or mktemp -d /tmp/pwdtintii-pick.XXXXXX)
    printf '%s\n' "$group" >"$sd/grp"
    printf '%s\n' "$grouppal" >"$sd/pal"

    set -l colorspec (env PWDTINTII_PALETTE="$grouppal" "$self" fzf-theme)
    set -l chdr (env PWDTINTII_PALETTE="$grouppal" "$self" pick-header "$hdr")

    set -l fzfargs --ansi "--prompt=pick $label > " --height=99% --reverse \
        "--preview=PWDTINTII_PALETTE=$grouppal $self preview-family {}" \
        --preview-window=right:50%:nowrap \
        --bind=change:first \
        "--bind=focus:execute-silent(PWDTINTII_PALETTE=\"\$(cat $sd/pal)\" $self emit-family {})" \
        "--bind=enter:execute-silent(PWDTINTII_PALETTE=\"\$(cat $sd/pal)\" $self emit-family {})+accept" \
        "--bind=esc:execute-silent($self emit-restore)+abort" \
        "--color=$colorspec" \
        "--header=$chdr"
    if test $toggle -eq 1
        set -a fzfargs "--bind=ctrl-t:transform($self pick-toggle $sd)+execute-silent(PWDTINTII_PALETTE=\"\$(cat $sd/pal)\" $self emit-family {})"
    end

    set -l sel (env PWDTINTII_PALETTE="$grouppal" "$self" list-menu \
        | env SHELL=/bin/sh PWDTINTII_PALETTE="$PWDTINTII_PALETTE" \
            PWDTINTII_VIEW_FAMILY="$_PWDTINTII_FAMILY" \
            PWDTINTII_VIEW_SHADE="$_PWDTINTII_SHADE_IDX" \
            fzf $fzfargs)
    set -l rc $status
    set grouppal (cat "$sd/pal" 2>/dev/null)
    rm -rf "$sd"
    test $rc -ne 0; and return 1
    test -z "$sel"; or test -z "$grouppal"; and return 1
    printf '%s\t%s\n' "$grouppal" "$sel"
end

# Numbered-menu fallback when fzf isn't available
function _pwdtintii_pick_menu
    set -l i 1
    printf '%s\n' "available families:"
    for fam in $_pwdtintii_families
        printf '  %2d) %s\n' $i $fam
        set i (math $i + 1)
    end
    printf 'pick number (or family name): '
    read -l choice
    test -z "$choice"; and return 0
    set -l fam
    if string match -qr '^[0-9]+$' -- $choice
        if test $choice -lt 1; or test $choice -gt (count $_pwdtintii_families)
            printf '%s\n' "pwdtintii: out of range: $choice" >&2
            return 1
        end
        set fam $_pwdtintii_families[$choice]
    else
        set fam $choice
    end
    test -z "$fam"; and begin
        printf '%s\n' "pwdtintii: invalid choice" >&2
        return 1
    end
    pwdtintii_pick $fam
end

# ── Public: list families + current key/family of this shell ─────────────────
function pwdtintii_list
    set -l key ($PWDTINTII_DIR_KEY_FN)
    set -l resolved (_pwdtintii_family_for $key)
    set -l curfam $_PWDTINTII_FAMILY
    test -n "$curfam"; or set curfam $resolved
    test -n "$_PWDTINTII_FORCED_FAMILY"; and set curfam "$curfam (forced)"
    set -l curshade $_PWDTINTII_SHADE_IDX
    test -n "$curshade"; or set curshade '?'
    printf '%s\n' "current key:    $key"
    printf '%s\n' "current family: $curfam"
    printf '%s\n' "current shade:  $curshade"
    printf '\n'
    printf '%s\n' "families ("(count $_pwdtintii_families)"):"
    set -l n (count $_pwdtintii_families)
    for i in (seq 1 $n)
        printf '  %-15s %s\n' $_pwdtintii_families[$i] $_pwdtintii_shades[$i]
    end
end

# ── Public: reload palette ───────────────────────────────────────────────────
function pwdtintii_reload
    set -e _PWDTINTII_DISABLED
    _pwdtintii_load_palette
    _pwdtintii_load_overrides
    set -g _PWDTINTII_FORCE_REAPPLY 1
    pwdtintii_apply
    printf '%s\n' "pwdtintii: reloaded ("(count $_pwdtintii_families)" families)"
end

# ── Public: diagnose the setup ───────────────────────────────────────────────
function pwdtintii_doctor
    printf '%s\n' "pwdtintii doctor"
    printf '%s\n' "  hash command: $_PWDTINTII_HASHCMD"
    if command -q fzf
        printf '%s\n' "  fzf:          found (menus + live picker enabled)"
    else
        printf '%s\n' "  fzf:          missing (menus fall back to a printed list)"
    end
    if command -q python3
        printf '%s\n' "  python3:      found (pt contrast enabled)"
    else
        printf '%s\n' "  python3:      missing (pt contrast unavailable)"
    end
    set -l tprog $TERM_PROGRAM
    test -n "$tprog"; or set tprog '?'
    set -l tterm $TERM
    test -n "$tterm"; or set tterm '?'
    set -l tcolor $COLORTERM
    test -n "$tcolor"; or set tcolor '?'
    set -l dis $_PWDTINTII_DISABLED
    test -n "$dis"; or set dis 0
    set -l fam $_PWDTINTII_FAMILY
    test -n "$fam"; or set fam auto
    set -l shd $_PWDTINTII_SHADE_IDX
    test -n "$shd"; or set shd '?'
    printf '%s\n' "  palette:      $PWDTINTII_PALETTE ("(count $_pwdtintii_families)" families)"
    printf '%s\n' "  state:        family=$fam shade=$shd disabled=$dis"
    printf '%s\n' "  terminal:     TERM=$tterm COLORTERM=$tcolor TERM_PROGRAM=$tprog"
    if not test -t 1
        printf '%s\n' "  osc 11:       skipped (output is not a terminal)"
        return 0
    end
    # Query the current background (OSC 11 with '?'); a compliant terminal answers
    # with an ESC-prefixed 'rgb:' reply. fish's read has no timeout, so the bounded
    # probe is delegated to bash's `read -n1 -t` — NOT sh: on Linux /bin/sh is dash,
    # whose read rejects -n/-t and would silently misreport "no response". Skip
    # honestly when bash is absent rather than emit a false negative.
    if not command -q bash
        printf '%s\n' "  osc 11:       skipped (probe needs bash for a timed read)"
        return 0
    end
    printf '\e]11;?\a' >/dev/tty
    set -l reply (bash -c 'IFS= read -r -n1 -t 1 r </dev/tty 2>/dev/null; printf %s "$r"' 2>/dev/null)
    if test -n "$reply"
        bash -c 'while IFS= read -r -n1 -t 0.05 _ </dev/tty 2>/dev/null; do :; done' 2>/dev/null
        printf '%s\n' "  osc 11:       terminal responded — supported"
    else
        printf '%s\n' "  osc 11:       no response — terminal may not support OSC 11 (tinting will be a no-op)"
    end
end

# ── Public: the `pt` entry point ─────────────────────────────────────────────
function pwdtintii
    # Self-heal a stale shell: re-source if the plugin file changed on disk.
    if _pwdtintii_is_stale
        if _pwdtintii_resource
            printf '%s\n' "pwdtintii: plugin changed on disk — reloaded this shell" >&2
        else
            printf '%s\n' "pwdtintii: plugin changed on disk but the new version won't parse — keeping the running one" >&2
        end
    end
    set -l sub $argv[1]
    switch "$sub"
        case ''
            if command -q fzf
                _pwdtintii_hub
            else
                _pwdtintii_help
            end
        case pick
            pwdtintii_pick $argv[2..-1]
        case list ls
            pwdtintii_list
        case apply
            pwdtintii_apply
        case auto unpin
            pwdtintii_pick --auto
        case off
            pwdtintii_off
        case doctor diag
            pwdtintii_doctor
        case reload
            pwdtintii_reload
        case view
            env SHELL=/bin/sh PWDTINTII_PALETTE="$PWDTINTII_PALETTE" \
                PWDTINTII_VIEW_FAMILY="$_PWDTINTII_FAMILY" \
                PWDTINTII_VIEW_SHADE="$_PWDTINTII_SHADE_IDX" \
                "$_pwdtintii_self/bin/pwdtintii" view
            pwdtintii_apply
        case preview
            pwdtintii view
        case contrast
            "$_pwdtintii_self/scripts/contrast-check.sh"
        case version
            set -l _v "(version unknown)"
            if test -r "$_pwdtintii_self/VERSION"
                # First whitespace-delimited token of the file, matching the
                # bash/zsh `${_v%%[[:space:]]*}` so all three shells agree even
                # on a malformed multi-line VERSION.
                set _v (string match -r '\S+' < "$_pwdtintii_self/VERSION" | head -n1)
            end
            printf '%s\n' "pwdtintii $_v"
        case help -h --help
            _pwdtintii_help
        case '*'
            printf '%s\n' "pwdtintii: unknown command: $sub" >&2
            printf '%s\n' "try: pwdtintii help" >&2
            return 1
    end
end

# fzf hub: list every action, preview its description, echo the chosen machine
# name (field 1). Sized to content like the zsh/bash hub. SHELL=/bin/sh so fzf's
# preview command runs under a POSIX shell.
function _pwdtintii_menu_pick
    set -l hdr "now: "(test -n "$_PWDTINTII_FAMILY"; and echo $_PWDTINTII_FAMILY; or echo auto)" "(test -n "$_PWDTINTII_SHADE_IDX"; and echo $_PWDTINTII_SHADE_IDX; or echo '?')" · ENTER run · ESC quit"
    _pwdtintii_is_stale; and set hdr "plugin changed — re-source · $hdr"
    set -l actions ("$_pwdtintii_self/bin/pwdtintii" actions)
    set -l cols $COLUMNS
    test -n "$cols"; or set cols (tput cols 2>/dev/null; or echo 80)
    set -l list_w (printf '%s\n' $actions | awk -F\t '{ if (length($2) > m) m = length($2) } END { print m + 6 }')
    if test (math (string length -- "$hdr")" + 6") -gt $list_w
        set list_w (math (string length -- "$hdr")" + 6")
    end
    set -l pvw
    if test (math "$cols - $list_w") -ge 30
        set pvw "right:"(math "$cols - $list_w")":wrap"
    else
        set pvw 'down:55%:wrap'
    end
    printf '%s\n' $actions \
        | env SHELL=/bin/sh fzf \
        --prompt='pwdtintii > ' \
        --height=99% \
        --reverse \
        --delimiter=\t \
        --with-nth=2 \
        "--preview=$_pwdtintii_self/bin/pwdtintii describe-action {1}" \
        "--preview-window=$pvw" \
        "--header=$hdr" \
        | cut -f1
end

# The hub loop: open the action menu, run the choice, come back to the menu.
function _pwdtintii_hub
    while true
        set -l action (_pwdtintii_menu_pick)
        test -n "$action"; or break
        pwdtintii $action
        switch "$action"
            case list contrast
                _pwdtintii_pause; or break
        end
    end
end

# Hold a display action's output until a keypress: q quits the hub, any other key
# returns to the menu. fish read has no timeout, so the ESC-tail drain is best-effort.
function _pwdtintii_pause
    printf '\n  \e[2m— any key: back to menu · q: quit —\e[0m ' >/dev/tty
    read -l -P '' -n1 k </dev/tty
    printf '\n' >/dev/tty
    test "$k" = q; or test "$k" = Q; and return 1
    return 0
end

# Printed cheat-sheet: the no-fzf fallback for `pt`, and `pt help`.
function _pwdtintii_help
    set -l fam $_PWDTINTII_FAMILY
    test -n "$fam"; or set fam '?'
    set -l shd $_PWDTINTII_SHADE_IDX
    test -n "$shd"; or set shd '?'
    printf '%s\n' "pwdtintii — directory-derived terminal tinting"
    printf '%s\n' "  now: $fam · shade $shd"
    _pwdtintii_is_stale; and printf '%s\n' "  (plugin changed on disk — re-source or open a new shell)"
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
end

# ── Hooks ────────────────────────────────────────────────────────────────────
# Preserve $status around the tint emit so a prompt reading the last command's
# exit status sees it, not pwdtintii_apply's — the same load-bearing guard as the
# bash/zsh precmd (without it the handler hands the prompt apply's status, not the
# user's last command's).
function _pwdtintii_precmd --on-event fish_prompt
    set -l __pt_rc $status
    pwdtintii_apply
    return $__pt_rc
end

function _pwdtintii_release_hook --on-event fish_exit
    _pwdtintii_release
end

# ── Boot ─────────────────────────────────────────────────────────────────────
_pwdtintii_load_palette
_pwdtintii_load_overrides
if test (count $_pwdtintii_families) -eq 0
    printf '%s\n' "pwdtintii: palette '$PWDTINTII_PALETTE' has no families — tinting disabled" >&2
end
