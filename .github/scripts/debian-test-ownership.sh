#!/usr/bin/env bash
# Exercise namespace migration without weakening the upstream ownership boundary.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
checker="$root/.github/scripts/debian-check-ownership.sh"
scratch="$(mktemp -d)"
trap 'rm -r "$scratch"' EXIT

git init -q "$scratch/repo"
cd "$scratch/repo"
git config user.name 'Ownership test'
git config user.email 'ownership-test@example.invalid'
mkdir -p .github/scripts .github/workflows
cp "$root/.github/debian-upstream-release" .github/debian-upstream-release
printf 'Upstream source\n' > README.md
printf 'Local helper\n' > .github/scripts/debian-fixture.sh
printf 'Legacy workflow\n' > .github/workflows/sync-upstream.yml
git add .
git commit -qm 'Create ownership fixture'
base="$(git rev-parse HEAD)"

expect_allowed() {
  "$checker" "$1" HEAD > "$scratch/check.log" 2>&1 || {
    cat "$scratch/check.log" >&2
    exit 1
  }
}

expect_rejected() {
  if "$checker" "$1" HEAD > "$scratch/check.log" 2>&1; then
    echo "Ownership check accepted an upstream-owned path: $2" >&2
    exit 1
  fi
  grep -F 'Downstream commits modified upstream-owned files:' "$scratch/check.log"
  grep -F "  $2" "$scratch/check.log"
}

printf 'Changed helper\n' >> .github/scripts/debian-fixture.sh
git commit -qam 'Change downstream helper'
expect_allowed "$base"

git switch -q --detach "$base"
git mv .github/workflows/sync-upstream.yml .github/workflows/debian-sync-upstream.yml
git commit -qm 'Migrate downstream workflow namespace'
expect_allowed "$base"
migrated="$(git rev-parse HEAD)"

printf 'Recreated legacy workflow\n' > .github/workflows/sync-upstream.yml
git add .
git commit -qm 'Recreate legacy workflow'
expect_rejected "$migrated" .github/workflows/sync-upstream.yml

git switch -q --detach "$base"
printf 'Changed source\n' >> README.md
git commit -qam 'Change upstream source'
expect_rejected "$base" README.md

git switch -q --detach "$base"
git mv README.md .github/scripts/debian-readme.sh
git commit -qm 'Move upstream source into downstream namespace'
expect_rejected "$base" README.md

git switch -q --detach "$base"
printf 'Unprefixed helper\n' > .github/scripts/fixture.sh
git add .
git commit -qm 'Add unprefixed helper'
expect_rejected "$base" .github/scripts/fixture.sh
printf 'Ownership namespace checks passed.\n'
