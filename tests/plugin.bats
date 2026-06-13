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
