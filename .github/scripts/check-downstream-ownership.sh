#!/usr/bin/env bash
# Enforce that normal downstream work stays in the packaging boundary.
set -euo pipefail

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

is_locally_owned() {
  case "$1" in
    debian/*|BUILDING.md|.github/workflows/debian-apt-repo.yml|.github/workflows/sync-upstream.yml|.github/scripts/*|.github/upstream-release)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_local_only() {
  local from="$1" to="$2" path
  local -a invalid=()

  while IFS= read -r path; do
    is_locally_owned "$path" || invalid+=("$path")
  done < <(git diff --name-only "$from" "$to")

  if ((${#invalid[@]})); then
    printf 'Downstream commits modified upstream-owned files:\n' >&2
    printf '  %s\n' "${invalid[@]}" >&2
    die 'Only debian/**, BUILDING.md, and the sync/package workflow files are locally maintained.'
  fi
}

[[ $# -eq 2 ]] || die 'Usage: check-downstream-ownership.sh <base> <head>'
base="$1"
head="$2"

git cat-file -e "${base}^{commit}" || git fetch origin "$base"
git cat-file -e "${head}^{commit}"

[[ -f .github/upstream-release ]] || die 'Missing .github/upstream-release'
recorded_tag="$(awk -F= '$1 == "tag" { print $2 }' .github/upstream-release)"
recorded_commit="$(awk -F= '$1 == "commit" { print $2 }' .github/upstream-release)"
[[ -n "$recorded_tag" && -n "$recorded_commit" ]] || die 'Invalid .github/upstream-release'
[[ "$recorded_tag" =~ ^v?[0-9]+([.][0-9]+){1,2}$ ]] || \
  die 'Invalid upstream release tag in .github/upstream-release'

git fetch --no-tags https://github.com/Foxboron/sbctl.git \
  "refs/tags/${recorded_tag}:refs/tags/ownership-check/${recorded_tag}"
expected_commit="$(git rev-parse "refs/tags/ownership-check/${recorded_tag}^{commit}")"
[[ "$recorded_commit" == "$expected_commit" ]] || \
  die 'The recorded upstream release does not match its immutable upstream tag.'

mapfile -t merges < <(git rev-list --merges "${base}..${head}")
upstream_merge=''
for merge in "${merges[@]}"; do
  if [[ "$(git rev-parse "${merge}^2")" == "$recorded_commit" ]]; then
    [[ -z "$upstream_merge" ]] || die 'A sync update may contain only one upstream merge commit.'
    upstream_merge="$merge"
  fi
done

if [[ -z "$upstream_merge" ]]; then
  require_local_only "$base" "$head"
  exit 0
fi

merge="$upstream_merge"
parent_one="$(git rev-parse "${merge}^1")"
git merge-base --is-ancestor "$base" "$parent_one" || \
  die 'The first parent of the upstream merge must descend from the PR base.'

# Only the tagged merge may change upstream-owned files. Both first-parent
# setup and follow-up versioning commits remain within the local boundary.
require_local_only "$base" "$parent_one"
require_local_only "$merge" "$head"
