#!/usr/bin/env bats
# Tests for 'pt version' command backed by the single-source VERSION file.

load helper

setup()    { need_bash; setup_sandbox; }
teardown() { teardown_sandbox; }

@test "bash: pt version prints a string containing the VERSION file contents" {
  run bash_eval / / 'pwdtintii version'
  [ "$status" -eq 0 ]
  local ver; ver="$(cat "$REPO_ROOT/VERSION" | tr -d '[:space:]')"
  [[ "$output" == *"$ver"* ]]
}

@test "zsh: pt version prints a string containing the VERSION file contents" {
  need_zsh
  run zsh_eval / / 'pwdtintii version'
  [ "$status" -eq 0 ]
  local ver; ver="$(cat "$REPO_ROOT/VERSION" | tr -d '[:space:]')"
  [[ "$output" == *"$ver"* ]]
}

@test "fish: pt version prints a string containing the VERSION file contents" {
  need_fish
  run fish_eval 'pwdtintii version'
  [ "$status" -eq 0 ]
  local ver; ver="$(cat "$REPO_ROOT/VERSION" | tr -d '[:space:]')"
  [[ "$output" == *"$ver"* ]]
}

@test "version parity: bash, zsh, and fish all print the identical version string" {
  need_zsh
  need_fish
  local vb vz vf
  vb="$(bash_eval / / 'pwdtintii version')"
  vz="$(zsh_eval  / / 'pwdtintii version')"
  vf="$(fish_eval 'pwdtintii version')"
  [ -n "$vb" ]
  [ "$vb" = "$vz" ]
  [ "$vb" = "$vf" ]
}

@test "doc-drift guard: VERSION file contents appear in README.md Status line" {
  local ver; ver="$(cat "$REPO_ROOT/VERSION" | tr -d '[:space:]')"
  grep -qF "Status: $ver" "$REPO_ROOT/README.md"
}
