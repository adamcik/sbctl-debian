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
2. Creates a simple APT repository structure.
3. Publishes it to the `gh-pages` branch.

Repository URL shape after publishing:

```text
https://<github-user>.github.io/<repo>
```

Example local source list entry (unsigned quick setup):

```bash
echo "deb [trusted=yes] https://<github-user>.github.io/<repo> trixie main" | \
  sudo tee /etc/apt/sources.list.d/sbctl-local.list
sudo apt update
sudo apt install sbctl
```

For production-style use, add GPG signing to the workflow and use
`signed-by=` instead of `trusted=yes`.
