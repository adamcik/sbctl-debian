#!/usr/bin/env bash
# Prepare a merge of an immutable Foxboron/sbctl release tag.
set -euo pipefail

readonly UPSTREAM_REPOSITORY='https://github.com/Foxboron/sbctl.git'
readonly UPSTREAM_REMOTE='upstream'
readonly RELEASE_FILE='.github/upstream-release'

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

read_release_file() {
  local key value

  [[ -f "$RELEASE_FILE" ]] || die "Missing $RELEASE_FILE"
  while IFS='=' read -r key value; do
    case "$key" in
      tag) recorded_tag="$value" ;;
      commit) recorded_commit="$value" ;;
    esac
  done < "$RELEASE_FILE"

  [[ -n "${recorded_tag:-}" && -n "${recorded_commit:-}" ]] || \
    die "Invalid $RELEASE_FILE"
}

fetch_tag() {
  local tag="$1"

  if git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
    [[ "$(git remote get-url "$UPSTREAM_REMOTE")" == "$UPSTREAM_REPOSITORY" ]] || \
      die "The $UPSTREAM_REMOTE remote does not point to $UPSTREAM_REPOSITORY"
  else
    git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_REPOSITORY"
  fi

  git fetch --no-tags "$UPSTREAM_REMOTE" \
    "refs/tags/$tag:refs/tags/upstream/$tag"
}

latest_tag() {
  local tag

  tag="$(gh api 'repos/Foxboron/sbctl/releases/latest' --jq '.tag_name' 2>/dev/null || true)"
  if [[ -z "$tag" || "$tag" == 'null' ]]; then
    tag="$(git ls-remote --tags --refs "$UPSTREAM_REPOSITORY" | \
      cut -f2 | sed 's#refs/tags/##' | \
      grep -E '^[v]?[0-9]+([.][0-9]+){1,2}$' | sort -V | tail -n1 || true)"
  fi

  [[ -n "$tag" ]] || die 'Could not determine an upstream stable release tag'
  printf '%s\n' "$tag"
}

update_changelog() {
  local tag="$1" version
  version="${tag#v}"

  command -v dch >/dev/null || die 'dch is required to update debian/changelog'
  dch --newversion "${version}-1~local1" --distribution experimental --urgency medium \
    "New upstream release ${tag}."
}

prepare() {
  local tag="$1" tag_commit

  [[ "$tag" =~ ^v?[0-9]+([.][0-9]+){1,2}$ ]] || \
    die "Invalid upstream release tag: $tag"
  read_release_file
  fetch_tag "$tag"
  tag_commit="$(git rev-parse "refs/tags/upstream/$tag^{commit}")"

  if [[ "$tag" == "$recorded_tag" && "$tag_commit" != "$recorded_commit" ]]; then
    die "Recorded commit for $tag does not match its upstream tag"
  fi

  if git merge-base --is-ancestor "$tag_commit" HEAD; then
    if [[ "$tag" == "$recorded_tag" ]]; then
      printf 'Upstream release %s is already represented.\n' "$tag"
      return
    fi
    die "Recorded release $recorded_tag is newer than requested release $tag"
  fi

  if ! git merge-base --is-ancestor "$recorded_commit" HEAD; then
    if [[ "$tag" != "$recorded_tag" ]]; then
      die "Upstream ancestry is not initialized. Review and merge a baseline PR for $recorded_tag before syncing $tag."
    fi

    # The initial Debian import has no shared Git ancestry with upstream. This
    # records the already-vendored release as a second parent without changing
    # its tree; every later release uses Git's normal merge strategy.
    git merge --no-ff --no-edit -s ours --allow-unrelated-histories \
      "refs/tags/upstream/$tag"
    return
  fi

  git merge --no-ff --no-edit "refs/tags/upstream/$tag"
  update_changelog "$tag"
  printf 'tag=%s\ncommit=%s\n' "$tag" "$tag_commit" > "$RELEASE_FILE"
}

needs_sync() {
  local tag="$1"

  read_release_file
  if [[ "$tag" != "$recorded_tag" ]] || \
    ! git cat-file -e "${recorded_commit}^{commit}" 2>/dev/null || \
    ! git merge-base --is-ancestor "$recorded_commit" HEAD; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

case "${1:-}" in
  latest)
    latest_tag
    ;;
  needs-sync)
    [[ $# -eq 2 ]] || die 'Usage: sync-upstream-release.sh needs-sync <tag>'
    needs_sync "$2"
    ;;
  prepare)
    [[ $# -eq 2 ]] || die 'Usage: sync-upstream-release.sh prepare <tag>'
    prepare "$2"
    ;;
  *)
    die 'Usage: sync-upstream-release.sh {latest|needs-sync <tag>|prepare <tag>}'
    ;;
esac
