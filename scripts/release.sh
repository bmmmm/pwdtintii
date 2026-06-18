#!/usr/bin/env bash
# Release automation for pwdtintii.
#
# Usage: scripts/release.sh <X.Y.Z> [--desc "short description"] [-y|--yes]
#
# Without --yes: validates, edits files, shows diff, then STOPS.
#   With --yes: also commits and creates an annotated tag.
# NEVER pushes — human runs: git push origin main && git push origin vX.Y.Z

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SELF_DIR}/.." && pwd)"

# ── helpers ───────────────────────────────────────────────────────────────────

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  printf '%s\n' \
    "Usage: scripts/release.sh <X.Y.Z> [--desc \"description\"] [-y|--yes]" \
    "" \
    "  <X.Y.Z>             semver version to release (must match X.Y.Z)" \
    "  --desc <text>       annotated tag message body (default: 'release vX.Y.Z')" \
    "  -y, --yes           after preflight, commit + tag (without: stops at dry-run)" \
    "" \
    "Edits in place: CHANGELOG.md (flips [Unreleased]), README.md (Status line), VERSION." \
    "Never pushes. After tagging it prints the commands to push." >&2
  exit 1
}

# Temp files are registered into _TMPFILES at each call site, not inside
# _make_tmp: a `+=` there would run in the `$(_make_tmp)` command-substitution
# subshell and never reach this (parent) array, leaving _cleanup a no-op.
_TMPFILES=()
_make_tmp() { mktemp "${TMPDIR:-/tmp}/release.XXXXXXXX"; }

_cleanup() {
  local f
  for f in "${_TMPFILES[@]+"${_TMPFILES[@]}"}"; do
    rm -f "$f"
  done
}
trap _cleanup EXIT

# ── parse args ────────────────────────────────────────────────────────────────

VERSION=""
DESC=""
DO_COMMIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    -y|--yes)  DO_COMMIT=1; shift ;;
    --desc)
      [[ $# -ge 2 ]] || die "--desc requires an argument"
      DESC="$2"; shift 2 ;;
    --desc=*)  DESC="${1#--desc=}"; shift ;;
    -*)        die "unknown option: $1 (try --help)" ;;
    *)
      [[ -z "$VERSION" ]] || die "unexpected argument: $1 (version already set to '$VERSION')"
      VERSION="$1"; shift ;;
  esac
done

[[ -n "$VERSION" ]] || usage

# ── validate semver ───────────────────────────────────────────────────────────

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "version '$VERSION' is not valid semver X.Y.Z (e.g. 1.2.3)"
fi

TAG="v${VERSION}"
[[ -z "$DESC" ]] && DESC="release ${TAG}"

# ── locate repo files ─────────────────────────────────────────────────────────

CHANGELOG="${REPO_ROOT}/CHANGELOG.md"
README="${REPO_ROOT}/README.md"
VERSION_FILE="${REPO_ROOT}/VERSION"

[[ -f "$CHANGELOG" ]] || die "CHANGELOG.md not found at ${CHANGELOG}"
[[ -f "$README"    ]] || die "README.md not found at ${README}"

# ── preconditions ─────────────────────────────────────────────────────────────

git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || die "not a git repository (expected repo at ${REPO_ROOT})"

current_branch=""
current_branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "main" ]]; then
  die "not on main branch (currently on '${current_branch}'); switch with: git checkout main"
fi

if ! git -C "$REPO_ROOT" diff --quiet HEAD 2>/dev/null; then
  die "working tree has uncommitted changes; commit or stash them first (see: git status)"
fi

if git -C "$REPO_ROOT" rev-parse "${TAG}" >/dev/null 2>&1; then
  die "tag ${TAG} already exists; choose a different version, or delete: git tag -d ${TAG}"
fi

# ── check [Unreleased] exists in CHANGELOG ───────────────────────────────────

if ! grep -q '^## \[Unreleased\]' "$CHANGELOG"; then
  die "no '## [Unreleased]' section found in CHANGELOG.md
  Add a section before the first versioned entry, e.g.:

    ## [Unreleased]

    ### Added
    - your change here

  Then re-run this script."
fi

# ── build em dash safely (UTF-8 bytes: e2 80 94) ─────────────────────────────
# Never embed the multibyte char in sed patterns — it mangles on some systems.
# Construct it from hex escapes (ASCII) and pass it as an awk variable instead.

EM_DASH="$(printf '\xe2\x80\x94')"
TODAY="$(date +%F)"

# ── edit CHANGELOG.md ─────────────────────────────────────────────────────────
# Replace the FIRST "## [Unreleased]" line with "## [X.Y.Z] — YYYY-MM-DD".
# awk writes to a temp file, then mv replaces the original (atomic-ish).

TMP_CHANGELOG="$(_make_tmp)"; _TMPFILES+=("$TMP_CHANGELOG")

awk -v ver="$VERSION" -v today="$TODAY" -v emdash="$EM_DASH" '
  /^## \[Unreleased\]/ {
    if (done == 0) {
      printf "## [%s] %s %s\n", ver, emdash, today
      done = 1
      next
    }
  }
  { print }
' "$CHANGELOG" > "$TMP_CHANGELOG"

if ! grep -q "^## \[${VERSION}\]" "$TMP_CHANGELOG"; then
  die "CHANGELOG rewrite failed — replacement header not found in output (unexpected)"
fi

# ── edit README.md ────────────────────────────────────────────────────────────
# Rewrite the version token in the "Status: X.Y.Z · ..." line.

TMP_README="$(_make_tmp)"; _TMPFILES+=("$TMP_README")

awk -v ver="$VERSION" '
  /^Status: [0-9]+\.[0-9]+\.[0-9]+/ {
    sub(/[0-9]+\.[0-9]+\.[0-9]+/, ver)
  }
  { print }
' "$README" > "$TMP_README"

if ! grep -qE "^Status: ${VERSION}" "$TMP_README"; then
  die "README.md rewrite failed — 'Status: X.Y.Z' line not found (is the format 'Status: X.Y.Z · ...'?)"
fi

# ── VERSION file ──────────────────────────────────────────────────────────────

TMP_VERSION="$(_make_tmp)"; _TMPFILES+=("$TMP_VERSION")
printf '%s\n' "$VERSION" > "$TMP_VERSION"

# ── preflight: verbatim ci.yml awk on the edited CHANGELOG ───────────────────
# This is the EXACT awk from .github/workflows/ci.yml's "Extract changelog" step.
# If it would produce an empty file the CI release job would exit 1 — catch it here.

TMP_NOTES="$(_make_tmp)"; _TMPFILES+=("$TMP_NOTES")

awk -v ver="$VERSION" '
  /^## \[/ {
    if (found) exit
    if ($0 ~ "\\[" ver "\\]") { found=1; next }
  }
  found { print }
' "$TMP_CHANGELOG" > "$TMP_NOTES"

if [[ ! -s "$TMP_NOTES" ]]; then
  die "preflight failed: CHANGELOG section for [${VERSION}] extracts as EMPTY.
  The GitHub CI release job would exit 1 on this tag.
  Add at least one entry under ## [${VERSION}] in CHANGELOG.md then re-run."
fi

# ── verify em dash survived ───────────────────────────────────────────────────

header_hex=""
header_hex="$(grep "^## \[${VERSION}\]" "$TMP_CHANGELOG" | head -n1 | od -An -tx1 | tr -d ' \n')"
if [[ "$header_hex" != *"e28094"* ]]; then
  die "em dash (U+2014, bytes e2 80 94) did not survive CHANGELOG rewrite.
  Header bytes: ${header_hex}"
fi

# ── show the proposed diff (temp vs current — nothing is written yet) ─────────
# A dry-run must be side-effect-free: diff the temp files against the current
# ones so a preview leaves the working tree untouched, and a later --yes still
# sees a clean tree. (This used to mv into place during the dry-run, which
# dirtied the tree and made the documented dry-run → --yes sequence abort on the
# script's own clean-tree precondition — and the header flip left no
# [Unreleased] for a second pass to find.)

_diff_pair() {
  local real="$1" tmp="$2"
  [[ -f "$real" ]] || real=/dev/null
  git -C "$REPO_ROOT" diff --no-index -- "$real" "$tmp" 2>/dev/null || true
}

printf '\n=== Version bump diff (current → proposed) ===\n'
_diff_pair "$CHANGELOG"    "$TMP_CHANGELOG"
_diff_pair "$README"       "$TMP_README"
_diff_pair "$VERSION_FILE" "$TMP_VERSION"
printf '=================================\n\n'

# ── dry-run stop: nothing was modified ────────────────────────────────────────

if [[ "$DO_COMMIT" -eq 0 ]]; then
  printf '%s\n' \
    "Dry-run complete. No files were modified — this was a preview only." \
    "" \
    "Preflight passed: CHANGELOG section for [${VERSION}] is non-empty." \
    "" \
    "To apply the edits, commit, and tag, re-run with --yes:" \
    "  scripts/release.sh ${VERSION} --desc \"${DESC}\" --yes" \
    "" \
    "That will:" \
    "  1. apply the diff above to CHANGELOG.md README.md VERSION" \
    "  2. git commit -m 'release: ${TAG}'" \
    "  3. git tag -a ${TAG} -m '${TAG} ${EM_DASH} ${DESC}'"
  exit 0
fi

# ── apply edits, then commit + tag ────────────────────────────────────────────

mv "$TMP_CHANGELOG" "$CHANGELOG"
mv "$TMP_README"    "$README"
mv "$TMP_VERSION"   "$VERSION_FILE"

git -C "$REPO_ROOT" add -- CHANGELOG.md README.md VERSION
git -C "$REPO_ROOT" commit -m "release: ${TAG}"
git -C "$REPO_ROOT" tag -a "${TAG}" -m "${TAG} ${EM_DASH} ${DESC}"

printf '\n%s\n' \
  "Tagged ${TAG}. Human runs next (NEVER pushed automatically):" \
  "" \
  "  git push origin main && git push origin ${TAG}" \
  "" \
  "The GitHub CI release job fires from the pushed tag and creates a GitHub Release" \
  "using the CHANGELOG section you just wrote."
