#!/usr/bin/env bash
# Run the pwdtintii test suite. Requires `bats`. Honors PWDTINTII_TEST_BASH to
# point at a bash >= 4 if the default `bash` is older (e.g. macOS /bin/bash).
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v bats >/dev/null 2>&1; then
  echo "tests: 'bats' not found — install bats-core (brew install bats-core)" >&2
  exit 127
fi

exec bats "$SELF_DIR"
