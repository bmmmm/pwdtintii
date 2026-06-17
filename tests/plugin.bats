#!/usr/bin/env bats
# Behavioural tests for the bash plugin (logic mirrored in zsh; parity.bats
# guarantees the two agree on key/family/hash).

load helper

setup() { need_bash; setup_sandbox; }
teardown() { teardown_sandbox; }

@test "git-root wins over first-component key" {
  mkdir -p "$TEST_HOME/work/myrepo/.git" "$TEST_HOME/work/myrepo/src"
  run bash_eval "$TEST_HOME" "$TEST_HOME/work/myrepo/src" '_pwdtintii_default_key'
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_HOME/work/myrepo" ]
}

@test "override file beats the hash" {
  printf 'myrepo\twine\n' > "$TEST_HOME/ov.tsv"
  export PWDTINTII_OVERRIDES_FILE="$TEST_HOME/ov.tsv"
  run bash_eval "$TEST_HOME" "/whatever" '_pwdtintii_family_for "/x/myrepo"'
  [ "$status" -eq 0 ]
  [ "$output" = "wine" ]
}

@test "emit accepts a valid hex" {
  run bash_eval / / '_pwdtintii_emit "#001f70" >/dev/null; echo $?'
  [ "$output" = "0" ]
}

@test "emit rejects junk (no escape injection)" {
  run bash_eval / / '_pwdtintii_emit "bogus; rm -rf /" 2>/dev/null; echo $?'
  [ "$output" = "1" ]
}

@test "emit rejects a short hex" {
  run bash_eval / / '_pwdtintii_emit "#fff" 2>/dev/null; echo $?'
  [ "$output" = "1" ]
}

@test "empty palette: apply is a no-op, no division-by-zero" {
  printf '# just a comment\n' > "$TEST_HOME/empty.tsv"
  PWDTINTII_PALETTE="$TEST_HOME/empty.tsv" run bash_eval / / 'pwdtintii_apply; echo "rc=$?"'
  [[ "$output" == *"rc=0"* ]]
  [[ "$output" != *"division"* ]]
}

@test "empty palette warns loudly at load" {
  printf '# just a comment\n' > "$TEST_HOME/empty.tsv"
  run env PWDTINTII_PALETTE="$TEST_HOME/empty.tsv" "$BASH4" -c 'source "'"$REPO_ROOT"'/pwdtintii.plugin.bash" 2>&1'
  [[ "$output" == *"no families"* ]]
}

@test "menu rejects choice 0 (no negative-index wraparound)" {
  run bash_eval / / 'printf "0\n" | _pwdtintii_pick_menu 2>&1 | tail -1'
  [[ "$output" == *"out of range"* ]]
}

@test "menu rejects out-of-range high choice" {
  run bash_eval / / 'printf "9999\n" | _pwdtintii_pick_menu 2>&1 | tail -1'
  [[ "$output" == *"out of range"* ]]
}

@test "menu handles a leading-zero choice without octal error (08)" {
  run bash_eval / / 'printf "08\n" | _pwdtintii_pick_menu 2>&1'
  [[ "$output" != *"value too great"* ]]
  [[ "$output" != *"out of range"* ]]
}

@test "pick rejects an unknown family" {
  run bash_eval / / 'pwdtintii_pick nosuchfamily 2>&1; echo "rc=$?"'
  [[ "$output" == *"unknown family"* ]]
  [[ "$output" == *"rc=1"* ]]
}

@test "release removes the registry file when last entry leaves" {
  run bash_eval / / '
    keyhash=testhash
    reg="$PWDTINTII_SHADES_DIR/$keyhash.tsv"
    mkdir -p "$PWDTINTII_SHADES_DIR"
    printf "%s\t0\t1\n" "$$" > "$reg"
    _PWDTINTII_REG="$reg"
    _pwdtintii_release
    [[ -f "$reg" ]] && echo PRESENT || echo GONE
    ls "$PWDTINTII_SHADES_DIR"/*.t 2>/dev/null && echo LEFTOVER || echo CLEAN
  '
  [[ "$output" == *"GONE"* ]]
  [[ "$output" == *"CLEAN"* ]]
}

@test "release drops our entry but keeps other shells'" {
  # Verify inside the inner shell, where $$ matches the row we wrote. Use the
  # surviving line count (2 → 1) rather than tab-matching to avoid quote pain.
  run bash_eval / / '
    reg="$PWDTINTII_SHADES_DIR/h.tsv"
    mkdir -p "$PWDTINTII_SHADES_DIR"
    printf "999999\t1\t1\n%s\t0\t1\n" "$$" > "$reg"
    _PWDTINTII_REG="$reg"
    _pwdtintii_release
    echo "lines=$(grep -c . "$reg")"
    grep -q 999999 "$reg" && echo OTHERKEPT || echo OTHERLOST
  '
  [[ "$output" == *"lines=1"* ]]
  [[ "$output" == *"OTHERKEPT"* ]]
}

@test "hash command is detected (shasum or sha1sum)" {
  run bash_eval / / 'echo "$_PWDTINTII_HASHCMD"'
  [[ "$output" == "shasum" || "$output" == "sha1sum" ]]
}

@test "pick_shade skips a shade held by a live PID" {
  run bash_eval / / '
    mkdir -p "$PWDTINTII_SHADES_DIR"
    sleep 30 & live=$!
    printf "%s\t0\t1\n" "$live" > "$PWDTINTII_SHADES_DIR/hh.tsv"
    _pwdtintii_pick_shade "k" "" "hh"
    kill "$live" 2>/dev/null
  '
  [ "$output" = "1" ]
}

@test "pick_shade reclaims a shade from a dead PID" {
  run bash_eval / / '
    mkdir -p "$PWDTINTII_SHADES_DIR"
    printf "999999\t0\t1\n" > "$PWDTINTII_SHADES_DIR/hh.tsv"
    _pwdtintii_pick_shade "k" "" "hh"
  '
  [ "$output" = "0" ]
}

@test "pick_shade leaves no stale lock dir behind" {
  run bash_eval / / '
    _pwdtintii_pick_shade "k" "" "hh" >/dev/null
    [[ -e "$PWDTINTII_SHADES_DIR/hh.tsv.lock" ]] && echo LOCKED || echo CLEAN
  '
  [ "$output" = "CLEAN" ]
}

# ── pt dispatcher ────────────────────────────────────────────────────────────

@test "dispatcher: help lists the pt subcommands" {
  run bash_eval / / 'pwdtintii help'
  [ "$status" -eq 0 ]
  [[ "$output" == *"pt pick"* ]]
  [[ "$output" == *"pt contrast"* ]]
}

@test "dispatcher: unknown command fails with guidance" {
  run bash_eval / / 'pwdtintii frobnicate 2>&1; echo "rc=$?"'
  [[ "$output" == *"unknown command"* ]]
  [[ "$output" == *"rc=1"* ]]
}

@test "dispatcher: a bare subcommand routes to its function" {
  run bash_eval / / 'pwdtintii list'
  [ "$status" -eq 0 ]
  [[ "$output" == *"families ("* ]]
}

@test "every hub action has a dispatch arm (menu↔dispatch parity)" {
  # bin/pwdtintii actions is the single source of truth: each catalog row's
  # machine name (field 1) is re-run through pwdtintii(). Drive every action
  # through the dispatcher and assert none falls through to the unknown-command
  # arm — that is the failure mode if a menu row gains no matching case arm.
  # fzf is stubbed to exit instantly so the 'pick' action can't open a picker.
  local stub="$TEST_HOME/bin"; mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'exit 0' > "$stub/fzf"; chmod +x "$stub/fzf"
  local n out
  for n in $("$REPO_ROOT/bin/pwdtintii" actions | cut -f1); do
    out=$(PT_REPO="$REPO_ROOT" PT_PAL="$PWDTINTII_PALETTE" PT_SH="$PWDTINTII_SHADES_DIR" PT_STUB="$stub" \
      "$BASH4" -c '
        export PWDTINTII_PALETTE="$PT_PAL" PWDTINTII_SHADES_DIR="$PT_SH" PATH="$PT_STUB:$PATH"
        source "$PT_REPO/pwdtintii.plugin.bash" 2>/dev/null
        pwdtintii "'"$n"'" </dev/null 2>&1
        :') || true
    [[ "$out" != *"unknown command"* ]] || { echo "no dispatch arm for action: $n"; return 1; }
  done
}

@test "preview is a back-compat alias for view (not the deleted preview.sh)" {
  # scripts/preview.sh is gone; `pt preview` must route to `pt view`. Stub fzf so
  # view can't open a real picker, then assert no 'unknown command', no missing-
  # file error from the old path, and a clean exit.
  local stub="$TEST_HOME/bin"; mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'cat >/dev/null 2>&1; exit 0' > "$stub/fzf"; chmod +x "$stub/fzf"
  local out
  out=$(PT_REPO="$REPO_ROOT" PT_PAL="$PWDTINTII_PALETTE" PT_SH="$PWDTINTII_SHADES_DIR" PT_STUB="$stub" \
    "$BASH4" -c '
      export PWDTINTII_PALETTE="$PT_PAL" PWDTINTII_SHADES_DIR="$PT_SH" PATH="$PT_STUB:$PATH"
      source "$PT_REPO/pwdtintii.plugin.bash" 2>/dev/null
      pwdtintii preview </dev/null 2>&1
      echo "rc=$?"') || true
  [[ "$out" != *"unknown command"* ]]
  [[ "$out" != *"No such file"* ]]
  [[ "$out" != *"unbound variable"* ]]
  [[ "$out" == *"rc=0"* ]]
}

@test "hub: runs the picked action, loops, then exits on an empty pick" {
  # Drive _pwdtintii_hub with a stubbed menu (no fzf/tty needed): the first
  # pick is 'list', the second is empty to end the loop; pause is stubbed to
  # continue. The picked action must actually run (list prints "families (").
  run bash_eval / / '
    flag="$PWDTINTII_SHADES_DIR/hub.flag"
    mkdir -p "$PWDTINTII_SHADES_DIR"
    _pwdtintii_menu_pick() { if [[ -e "$flag" ]]; then echo ""; else : > "$flag"; echo list; fi; }
    _pwdtintii_pause() { return 0; }
    _pwdtintii_hub
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"families ("* ]]
}

@test "stale detection: flags a plugin file changed since load" {
  # Point the staleness check at a throwaway file. Equal mtime → fresh; a
  # load-time mtime older than the file's actual mtime → stale.
  run bash_eval / / '
    mkdir -p "$PWDTINTII_SHADES_DIR"
    f="$PWDTINTII_SHADES_DIR/fake.plugin"; : > "$f"
    _PWDTINTII_PLUGIN_FILE="$f"
    _PWDTINTII_LOADED_MTIME="$(_pwdtintii_mtime "$f")"
    _pwdtintii_is_stale && echo "unexpected-stale" || echo "fresh-ok"
    _PWDTINTII_LOADED_MTIME=1
    _pwdtintii_is_stale && echo "stale-detected" || echo "missed"
  '
  [[ "$output" == *"fresh-ok"* ]]
  [[ "$output" == *"stale-detected"* ]]
}

@test "pt auto-reloads a stale shell before dispatching" {
  need_bash
  # Corrupt the family list and force the staleness check to fire; dispatching
  # any command must re-source the plugin (restoring all 37 families) and clear
  # the stale flag — i.e. `pt` self-heals after the plugin changed on disk.
  run bash_eval "$TEST_HOME" "$TEST_HOME" '
    _pwdtintii_families=(bogus)
    _PWDTINTII_LOADED_MTIME=1
    pwdtintii list >/dev/null 2>&1
    _pwdtintii_is_stale && echo "still-stale" || echo "healed"
    echo "count=${#_pwdtintii_families[@]}"
  '
  [[ "$output" == *"healed"* ]]
  [[ "$output" == *"count=37"* ]]
}

@test "pt does not re-source when the plugin is unchanged" {
  need_bash
  # Same corruption, fresh (non-stale) shell: the dispatcher must NOT re-source,
  # so the corruption survives. Guards against re-sourcing on every invocation.
  run bash_eval "$TEST_HOME" "$TEST_HOME" '
    _pwdtintii_families=(bogus)
    pwdtintii list >/dev/null 2>&1
    echo "count=${#_pwdtintii_families[@]}"
  '
  [[ "$output" == *"count=1"* ]]
}

@test "self-reload does not re-register the prompt hook (no double OSC 11)" {
  need_bash
  # A framework that spaces out the `;` separators slips past the substring
  # guard; the one-shot install flag must stop a self-reload from appending
  # _pwdtintii_precmd a second time (which would emit OSC 11 twice per prompt).
  run bash_eval "$TEST_HOME" "$TEST_HOME" '
    PROMPT_COMMAND="starship_precmd ; _pwdtintii_precmd"   # space-padded separator
    _PWDTINTII_LOADED_MTIME=1                              # force staleness
    pwdtintii list >/dev/null 2>&1                         # dispatch → self-reload
    n=$(grep -o _pwdtintii_precmd <<< "$PROMPT_COMMAND" | grep -c .)
    echo "count=$n"
  '
  [[ "$output" == *"count=1"* ]]
}

@test "hook install dedupes an array PROMPT_COMMAND (bash 5.1+), no double OSC 11" {
  need_bash
  # bash 5.1 lets PROMPT_COMMAND be an array. The old [0]-only substring check
  # missed a hook sitting in a later element and appended a second copy; install
  # now scans every element, so a pre-existing hook in a non-[0] slot blocks it.
  run bash_eval "$TEST_HOME" "$TEST_HOME" '
    [[ ${BASH_VERSINFO[0]} -gt 5 || ( ${BASH_VERSINFO[0]} -eq 5 && ${BASH_VERSINFO[1]} -ge 1 ) ]] \
      || { echo "count=1"; exit 0; }   # array PROMPT_COMMAND predates 5.1 — nothing to test
    unset _PWDTINTII_HOOK_INSTALLED
    PROMPT_COMMAND=( "starship_precmd" "_pwdtintii_precmd" )   # our hook already in [1]
    _pwdtintii_install_hook
    n=0; for e in "${PROMPT_COMMAND[@]}"; do [[ "$e" == *_pwdtintii_precmd* ]] && (( ++n )); done
    echo "count=$n"
  '
  [[ "$output" == *"count=1"* ]]
}

@test "the prompt hook preserves \$? (the prompt shows the real exit status)" {
  need_bash
  # pwdtintii_apply returns 0; without restoring $? a prompt that reads the last
  # exit status (a captured $?, zsh %?) would always show success. _pwdtintii_precmd
  # must hand back the status it was entered with.
  run bash_eval "$TEST_HOME" "$TEST_HOME" '
    ( exit 42 )                        # a recognizable non-zero status
    _pwdtintii_precmd >/dev/null 2>&1
    echo "rc=$?"
  '
  [[ "$output" == *"rc=42"* ]]
}

@test "self-reload refuses a syntactically broken plugin (keeps the running one)" {
  need_bash
  # A reload that lands mid-edit must not partially redefine the plugin: bash -n
  # rejects the broken file, the dispatcher reports it, and the running
  # definitions survive (here pwdtintii_apply stays callable).
  run bash_eval "$TEST_HOME" "$TEST_HOME" '
    broken="$PWDTINTII_SHADES_DIR/broken.bash"
    mkdir -p "$PWDTINTII_SHADES_DIR"
    printf "pwdtintii_apply() {\n" > "$broken"   # truncated: unterminated function
    _PWDTINTII_PLUGIN_FILE="$broken"
    _PWDTINTII_LOADED_MTIME=1                     # force staleness
    msg=$(pwdtintii list 2>&1 >/dev/null) || true
    echo "$msg"
    type pwdtintii_apply >/dev/null 2>&1 && echo "apply-intact" || echo "apply-gone"
  '
  [[ "$output" == *"won't parse"* ]]
  [[ "$output" == *"apply-intact"* ]]
}

# ── pt off / disable + re-enable ─────────────────────────────────────────────

@test "off sets the disabled flag and makes apply a no-op" {
  run bash_eval "$TEST_HOME" "$TEST_HOME" '
    pwdtintii_apply >/dev/null        # tint once
    pwdtintii_off >/dev/null          # real off, not just unpin
    out=$(pwdtintii_apply)            # must emit nothing now
    printf "disabled=%s applyout=[%s]\n" "${_PWDTINTII_DISABLED:-}" "$out"
  '
  [[ "$output" == *"disabled=1"* ]]
  [[ "$output" == *"applyout=[]"* ]]
}

@test "pick re-enables tinting after off" {
  run bash_eval "$TEST_HOME" "$TEST_HOME" '
    pwdtintii_off >/dev/null
    pwdtintii_pick blue >/dev/null
    printf "disabled=[%s] family=%s\n" "${_PWDTINTII_DISABLED:-}" "$_PWDTINTII_FAMILY"
  '
  [[ "$output" == *"disabled=[]"* ]]
  [[ "$output" == *"family=blue"* ]]
}

@test "pick treats bare 'auto' as unpin, not a family lookup" {
  run bash_eval "$TEST_HOME" "$TEST_HOME" '
    pwdtintii_pick blue >/dev/null 2>&1          # pin a family first
    pwdtintii_pick auto >/dev/null 2>&1; rc=$?   # `pt pick auto` must unpin
    printf "forced=[%s] rc=%s\n" "${_PWDTINTII_FORCED_FAMILY:-}" "$rc"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"forced=[]"* ]]
  [[ "$output" == *"rc=0"* ]]
}

# ── pick: dark/light group toggle ────────────────────────────────────────────
# The fzf picker's ctrl-t toggle commits through _pwdtintii_set_palette; the
# interactive loop itself needs a real tty, but the commit logic is unit-testable.

@test "set_palette switches the active palette and its shades" {
  run bash_eval "$TEST_HOME" "$TEST_HOME" '
    dark="${_pwdtintii_shades[blue]}"
    _pwdtintii_set_palette "$_pwdtintii_self/palettes/light.tsv"
    light="${_pwdtintii_shades[blue]}"
    [[ "$PWDTINTII_PALETTE" == *"/light.tsv" ]] && echo pal-ok
    [[ -n "$light" && "$dark" != "$light" ]] && echo shades-differ
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"pal-ok"* ]]
  [[ "$output" == *"shades-differ"* ]]
}

@test "committing a light-group pick pins the family with light shades" {
  # Call pwdtintii_pick directly (not in $()) so its palette/family state
  # persists; `run` captures the OSC it emits to stdout either way.
  run bash_eval "$TEST_HOME" "$TEST_HOME" '
    _pwdtintii_set_palette "$_pwdtintii_self/palettes/light.tsv"   # picker does this on commit
    pwdtintii_pick blue
    printf "\nfamily=%s pal=%s\n" "$_PWDTINTII_FAMILY" "${PWDTINTII_PALETTE##*/}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"family=blue"* ]]
  [[ "$output" == *"pal=light.tsv"* ]]
  [[ "$output" == *"]11;#"* ]]    # an OSC 11 background was emitted
  [[ "$output" != *"#001f70"* ]]  # ...and it is not the dark-palette blue
}

@test "doctor reports the setup and skips the live query off-tty" {
  run bash_eval / / 'pwdtintii doctor'
  [ "$status" -eq 0 ]
  [[ "$output" == *"pwdtintii doctor"* ]]
  [[ "$output" == *"palette:"* ]]
  [[ "$output" == *"osc 11:"* ]]
}

# ── palette validation ───────────────────────────────────────────────────────

@test "palette load skips a family with malformed shades, keeps the good one" {
  printf 'good\t#001f70\t#002d8f\t#0a38a8\t#1442c0\n' >  "$TEST_HOME/p.tsv"
  printf 'bad\t#001f70\tnothex\t#0a38a8\t#1442c0\n'   >> "$TEST_HOME/p.tsv"
  run env PWDTINTII_PALETTE="$TEST_HOME/p.tsv" "$BASH4" -c '
    source "'"$REPO_ROOT"'/pwdtintii.plugin.bash" 2>&1
    printf "fams=[%s]\n" "${_pwdtintii_families[*]}"
  '
  [[ "$output" == *"skipping 'bad'"* ]]
  [[ "$output" == *"fams=[good]"* ]]
}
