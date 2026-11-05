#!/usr/bin/env bash
# Shared APT repository construction for the CI smoke test and Pages publishing.
# Using one builder lets PRs test the repository format with a disposable key,
# without exposing the release signing key or testing a separate implementation.
set -euo pipefail

[[ $# -eq 2 ]] || { echo 'Usage: build-apt-repository.sh <artifacts> <repo>' >&2; exit 1; }
artifacts="$1"
repo="$2"
: "${APT_GPG_KEY_ID:?Missing signing key ID}"
: "${APT_GPG_PUBLIC_KEY:?Missing public key}"

shopt -s nullglob
packages=("$artifacts"/*.deb)
binary=("$artifacts"/sbctl-bin_*_amd64.deb)
automation=("$artifacts"/sbctl_*_all.deb)
[[ ${#packages[@]} -eq 2 && ${#binary[@]} -eq 1 && ${#automation[@]} -eq 1 ]] || {
  echo 'Expected exactly one sbctl all package and one sbctl-bin amd64 package.' >&2
  exit 1
}

mkdir -p "$repo/pool/main" "$repo/dists/trixie/main/binary-amd64"
cp "${packages[@]}" "$repo/pool/main/"
(cd "$repo" && dpkg-scanpackages --arch amd64 pool > dists/trixie/main/binary-amd64/Packages)
gzip -9c "$repo/dists/trixie/main/binary-amd64/Packages" > "$repo/dists/trixie/main/binary-amd64/Packages.gz"
xz -9c "$repo/dists/trixie/main/binary-amd64/Packages" > "$repo/dists/trixie/main/binary-amd64/Packages.xz"

apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="Thomas Adamcik" \
  -o APT::FTPArchive::Release::Label="sbctl-debian" \
  -o APT::FTPArchive::Release::Suite="trixie" \
  -o APT::FTPArchive::Release::Codename="trixie" \
  -o APT::FTPArchive::Release::Architectures="amd64" \
  -o APT::FTPArchive::Release::Components="main" \
  -o APT::FTPArchive::Release::Description="sbctl Debian packages" \
  release "$repo/dists/trixie" > "$repo/dists/trixie/Release"

gpg --batch --yes --pinentry-mode loopback --default-key "$APT_GPG_KEY_ID" \
  --clearsign -o "$repo/dists/trixie/InRelease" "$repo/dists/trixie/Release"
gpg --batch --yes --pinentry-mode loopback --default-key "$APT_GPG_KEY_ID" \
  -abs -o "$repo/dists/trixie/Release.gpg" "$repo/dists/trixie/Release"
printf '%s' "$APT_GPG_PUBLIC_KEY" | gpg --batch --dearmor -o "$repo/sbctl-archive-keyring.gpg"
printf '%s\n' "$APT_GPG_PUBLIC_KEY" > "$repo/sbctl-archive-keyring.asc"
