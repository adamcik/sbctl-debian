# Building sbctl Debian packages (local trixie)

This repository contains a local-only Debian packaging variant intended to
produce installable packages on Debian trixie.

## Build dependencies

Install the required build tools on the host:

```bash
sudo apt install --no-install-recommends \
  asciidoc-base \
  golang-any \
  libpcsclite-dev \
  pkgconf \
  debhelper \
  devscripts
```

## Build

From the repository root:

```bash
dpkg-buildpackage -us -uc -b -nc
```

Notes:
- `-nc` skips the `clean` step and avoids permission issues if previous builds
  left read-only files under `debian/.debhelper`.
- Generated packages are placed in the parent directory.

## Install locally

```bash
sudo apt install ../sbctl-bin_*_amd64.deb ../sbctl_*_all.deb
```

## Verify install

```bash
command -v sbctl
sbctl status
```

## GitHub Pages APT publishing

The repository includes a GitHub Actions workflow at
`.github/workflows/debian-apt-repo.yml` that:

1. Builds trixie `.deb` artifacts from this branch.
2. Creates and signs an APT repository structure.
3. Publishes it to the `gh-pages` branch.

### Required GitHub environment

Create a protected GitHub Actions environment named `apt-signing` and keep it
restricted to your `trixie` branch.

Add these secrets in that environment:

- `APT_GPG_PRIVATE_KEY`: ASCII-armored private key used to sign Release files.
- `APT_GPG_PUBLIC_KEY`: matching ASCII-armored public key.
- `APT_GPG_KEY_ID`: key id or fingerprint used by `gpg --default-key`.

Repository URL shape after publishing:

```text
https://adamcik.github.io/sbctl-debian
```

Example local source setup (signed):

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://adamcik.github.io/sbctl-debian/sbctl-archive-keyring.gpg | \
  sudo tee /etc/apt/keyrings/sbctl-archive-keyring.gpg >/dev/null
cat <<'EOF' | sudo tee /etc/apt/sources.list.d/sbctl.sources >/dev/null
Types: deb
URIs: https://adamcik.github.io/sbctl-debian
Suites: trixie
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/sbctl-archive-keyring.gpg
EOF
cat <<'EOF' | sudo tee /etc/apt/preferences.d/sbctl.pref >/dev/null
Package: sbctl sbctl-bin
Pin: origin adamcik.github.io
Pin-Priority: 700

Package: *
Pin: origin adamcik.github.io
Pin-Priority: -1
EOF
sudo apt update
sudo apt install sbctl
```
