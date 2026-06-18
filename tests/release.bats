#!/usr/bin/env bats
# tests/release.bats — unit tests for scripts/release.sh
#
# Each test operates on a throwaway git repo in TEST_HOME.
# The real repo files are never modified.

load helper

RELEASE_SH="${REPO_ROOT}/scripts/release.sh"

# ── fixture helpers ───────────────────────────────────────────────────────────

# Set up a minimal git repo at TEST_HOME with fake CHANGELOG/README/VERSION.
# Symlinks scripts/release.sh into TEST_HOME so REPO_ROOT derivation resolves there.
# $1 (optional) = CHANGELOG.md content override
_init_fixture_repo() {
  local changelog_content="${1:-}"

  if [[ -z "$changelog_content" ]]; then
    changelog_content="$(printf '%s\n' \
      '# Changelog' \
      '' \
      '## [Unreleased]' \
      '' \
      '### Added' \
      '- something new' \
      '' \
      '## [0.0.1] — 2025-01-01' \
      '' \
      '### Added' \
      '- initial release')"
  fi

  printf '%s\n' "$changelog_content" > "${TEST_HOME}/CHANGELOG.md"

  printf '%s\n' \
    '# My Project' \
    '' \
    'Status: 0.0.1 · alpha · zsh + bash' \
    '' \
    'Some description.' > "${TEST_HOME}/README.md"

  printf '%s\n' '0.0.1' > "${TEST_HOME}/VERSION"

  # Symlink the script into a scripts/ subdir so REPO_ROOT derivation gives TEST_HOME.
  mkdir -p "${TEST_HOME}/scripts"
  ln -sf "${RELEASE_SH}" "${TEST_HOME}/scripts/release.sh"

  git -C "${TEST_HOME}" init -q
  # Ensure we are on 'main' (git default branch may be 'master').
  git -C "${TEST_HOME}" checkout -q -b main 2>/dev/null \
    || git -C "${TEST_HOME}" -c user.email="t@t.t" -c user.name="T" \
       checkout -q -B main 2>/dev/null || true
  git -C "${TEST_HOME}" -c user.email="t@t.t" -c user.name="T" \
    add CHANGELOG.md README.md VERSION
  git -C "${TEST_HOME}" -c user.email="t@t.t" -c user.name="T" \
    commit -q -m "initial commit"
}

# Shorthand: run the symlinked script (so REPO_ROOT = TEST_HOME).
_release() {
  bash "${TEST_HOME}/scripts/release.sh" "$@"
}

setup() {
  setup_sandbox
}
teardown() {
  teardown_sandbox
}

# ── semver validation ─────────────────────────────────────────────────────────

@test "rejects non-semver version" {
  _init_fixture_repo
  run _release "notasemver" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid semver"* ]]
}

@test "rejects version with extra components" {
  _init_fixture_repo
  run _release "1.2.3.4" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid semver"* ]]
}

@test "rejects version with leading v" {
  _init_fixture_repo
  run _release "v1.2.3" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid semver"* ]]
}

# ── no [Unreleased] section ───────────────────────────────────────────────────

@test "errors with guidance when CHANGELOG has no [Unreleased] section" {
  local no_unreleased
  no_unreleased="$(printf '%s\n' \
    '# Changelog' \
    '' \
    '## [0.1.0] — 2025-01-01' \
    '' \
    '### Added' \
    '- initial release')"
  _init_fixture_repo "$no_unreleased"

  run _release "0.2.0" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"[Unreleased]"* ]]
}

# ── preflight: empty [Unreleased] section ─────────────────────────────────────

@test "preflight exits non-zero when [Unreleased] section body is empty" {
  # Header exists but there is NO blank line and NO content before the next version
  # marker, so the ci.yml awk extracts 0 bytes. (A blank line alone between headers
  # would produce a newline byte and pass -s; the truly empty case needs no gap.)
  local empty_body
  empty_body="$(printf '%s\n' \
    '# Changelog' \
    '' \
    '## [Unreleased]' \
    '## [0.0.1] — 2025-01-01' \
    '' \
    '### Added' \
    '- initial release')"
  _init_fixture_repo "$empty_body"

  run _release "0.1.0" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]] || [[ "$output" == *"EMPTY"* ]]
}

@test "preflight on empty section: no tag is created" {
  local empty_body
  empty_body="$(printf '%s\n' \
    '# Changelog' \
    '' \
    '## [Unreleased]' \
    '## [0.0.1] — 2025-01-01' \
    '' \
    '### Added' \
    '- initial release')"
  _init_fixture_repo "$empty_body"

  run _release "0.1.0" --yes 2>&1
  [ "$status" -ne 0 ]

  local tags
  tags="$(git -C "${TEST_HOME}" tag -l 'v*')"
  [ -z "$tags" ]
}

# ── header flip ───────────────────────────────────────────────────────────────

@test "[Unreleased] header is replaced with [X.Y.Z]" {
  _init_fixture_repo

  _release "1.0.0" --yes

  grep -q "^## \[1\.0\.0\]" "${TEST_HOME}/CHANGELOG.md"
  # [Unreleased] must be gone.
  local cnt
  cnt="$(grep -c '^\#\# \[Unreleased\]' "${TEST_HOME}/CHANGELOG.md" || true)"
  [ "$cnt" = "0" ]
}

@test "em dash (U+2014, bytes e2 80 94) survives in the CHANGELOG header" {
  _init_fixture_repo

  _release "1.0.0" --yes

  local header_hex
  header_hex="$(grep "^## \[1\.0\.0\]" "${TEST_HOME}/CHANGELOG.md" | head -n1 \
    | od -An -tx1 | tr -d ' \n')"
  [[ "$header_hex" == *"e28094"* ]]
}

@test "CHANGELOG header contains today's date" {
  _init_fixture_repo

  _release "1.0.0" --yes

  local today
  today="$(date +%F)"
  grep -q "^## \[1\.0\.0\].*${today}" "${TEST_HOME}/CHANGELOG.md"
}

@test "CHANGELOG body content is preserved after the header flip" {
  _init_fixture_repo

  _release "1.0.0" --yes

  grep -q "something new" "${TEST_HOME}/CHANGELOG.md"
  grep -q "## \[0\.0\.1\]" "${TEST_HOME}/CHANGELOG.md"
}

# ── VERSION file ──────────────────────────────────────────────────────────────

@test "VERSION file is updated to the new version" {
  _init_fixture_repo

  _release "1.0.0" --yes

  local v
  v="$(cat "${TEST_HOME}/VERSION")"
  [ "$v" = "1.0.0" ]
}

@test "VERSION file is created if it does not exist" {
  _init_fixture_repo
  git -C "${TEST_HOME}" -c user.email="t@t.t" -c user.name="T" rm -f VERSION >/dev/null 2>&1 || true
  git -C "${TEST_HOME}" -c user.email="t@t.t" -c user.name="T" \
    commit -q --allow-empty -m "drop VERSION"

  _release "1.0.0" --yes

  local v
  v="$(cat "${TEST_HOME}/VERSION")"
  [ "$v" = "1.0.0" ]
}

# ── README Status line ────────────────────────────────────────────────────────

@test "README Status line version token is updated" {
  _init_fixture_repo

  _release "1.0.0" --yes

  grep -q "^Status: 1\.0\.0" "${TEST_HOME}/README.md"
}

@test "README Status line rest of line is preserved" {
  _init_fixture_repo

  _release "1.0.0" --yes

  # Should still contain the suffix after the version.
  grep -q "^Status: 1\.0\.0 · alpha" "${TEST_HOME}/README.md"
}

# ── dry-run (no --yes) ────────────────────────────────────────────────────────

@test "dry-run makes no commit" {
  _init_fixture_repo

  local before_hash
  before_hash="$(git -C "${TEST_HOME}" rev-parse HEAD)"

  _release "1.0.0"

  local after_hash
  after_hash="$(git -C "${TEST_HOME}" rev-parse HEAD)"
  [ "$before_hash" = "$after_hash" ]
}

@test "dry-run creates no tag" {
  _init_fixture_repo

  _release "1.0.0"

  local tags
  tags="$(git -C "${TEST_HOME}" tag -l 'v*')"
  [ -z "$tags" ]
}

@test "dry-run output tells user to re-run with --yes" {
  _init_fixture_repo

  run _release "1.0.0" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"--yes"* ]]
}

@test "dry-run leaves the working tree clean (no in-place edits)" {
  _init_fixture_repo

  _release "1.0.0"

  # A preview must not touch the tracked files, so a later --yes still sees a
  # clean tree.
  git -C "${TEST_HOME}" diff --quiet HEAD
}

@test "dry-run then --yes applies and tags (the preview → apply flow)" {
  _init_fixture_repo

  # The documented two-step flow: preview, then commit for real. Regression
  # guard — the dry-run used to mv into place and dirty the tree, so this --yes
  # aborted on the clean-tree precondition.
  _release "1.0.0"
  _release "1.0.0" --yes

  git -C "${TEST_HOME}" rev-parse "v1.0.0" >/dev/null 2>&1
  grep -q "^## \[1\.0\.0\]" "${TEST_HOME}/CHANGELOG.md"
  local v
  v="$(cat "${TEST_HOME}/VERSION")"
  [ "$v" = "1.0.0" ]
}

# ── --yes path: commit and tag ────────────────────────────────────────────────

@test "--yes creates an annotated tag vX.Y.Z" {
  _init_fixture_repo

  _release "1.0.0" --yes

  git -C "${TEST_HOME}" rev-parse "v1.0.0" >/dev/null 2>&1
}

@test "--yes annotated tag has correct name" {
  _init_fixture_repo

  _release "1.0.0" --yes

  local tag_name
  tag_name="$(git -C "${TEST_HOME}" tag -l 'v1.0.0')"
  [ "$tag_name" = "v1.0.0" ]
}

@test "--yes commit message is 'release: vX.Y.Z'" {
  _init_fixture_repo

  _release "1.0.0" --yes

  local msg
  msg="$(git -C "${TEST_HOME}" log -1 --format='%s')"
  [ "$msg" = "release: v1.0.0" ]
}

@test "--yes does NOT push (no remote configured, script must still succeed)" {
  _init_fixture_repo
  # No remote is configured; a push would fail. Script must exit 0.
  run _release "1.0.0" --yes 2>&1
  [ "$status" -eq 0 ]
}

@test "--yes output prints push instructions" {
  _init_fixture_repo

  run _release "1.0.0" --yes 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"git push origin main"* ]]
  [[ "$output" == *"git push origin v1.0.0"* ]]
}

# ── preconditions ─────────────────────────────────────────────────────────────

@test "fails with actionable message when working tree is dirty" {
  _init_fixture_repo
  printf 'dirty\n' >> "${TEST_HOME}/README.md"

  run _release "1.0.0" 2>&1
  [ "$status" -ne 0 ]
  # Message must tell user what to do.
  [[ "$output" == *"uncommitted changes"* ]] || [[ "$output" == *"commit or stash"* ]]
}

@test "fails when the tag already exists" {
  _init_fixture_repo
  git -C "${TEST_HOME}" tag -a "v1.0.0" -m "already here"

  run _release "1.0.0" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}
