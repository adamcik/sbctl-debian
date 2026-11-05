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
  libssl-dev \
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
- `dh_auto_test` runs the upstream `make test` target (`go test -v ./...`).
  Any failure stops the package build. `libssl-dev` supplies the headers needed
  by the command tests' software TPM simulator; these tests do not need a TPM.
- The separate upstream `make integration` suite is not run during the Debian
  build. Its `integration` build tag requires a QEMU/KVM VM and an OVMF Secure
  Boot image (see `tests/README.md`), which the build container does not provide.
  The default Go tests remain enabled, including the command tests.

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

**Pull requests use a new throwaway signing key, never the production key.**
This includes dispatched upstream-sync builds. Only a push to `trixie` uses
the production key, and deployment requires testing that signed repository.

The repository includes a GitHub Actions workflow at
`.github/workflows/debian-apt-repo.yml` that:

1. Checks downstream ownership and builds trixie `.deb` artifacts for every
   pull request (including stacked PRs), `trixie` push, and manual dispatch.
2. Installs both built packages in a clean trixie container, including their
   maintainer scripts, and checks package configuration, CLI startup, shell
   completion, and installed files.
3. Creates an APT repository with a disposable CI signing key and installs the
   exact built versions through APT in another clean trixie container. APT must
   authenticate the repository with its exported key. Downloads use only the
   candidate source and must match the built artifacts byte for byte; Debian
   sources supply dependencies at install time. A tampered signature must fail.
4. Only on a `trixie` push, signs with the protected release key and repeats the
   APT install check against that exact repository before uploading the Pages
   artifact. A separate dependent job deploys it to GitHub Pages, not a branch.

Both signing paths use `.github/scripts/debian-build-apt-repository.sh`. The install
checks use `.github/scripts/debian-smoke-test.sh`, with `/artifacts` and
`/repo` mounted read-only. Run this script only in disposable trixie containers:
installing `sbctl` can create local Secure Boot keys. The checks do not mount
host firmware or boot filesystems and do not test real key enrollment, boot
signing, or firmware behavior. They need neither signing secrets nor hardware.

## Upstream sync and ownership

`.github/workflows/debian-sync-upstream.yml` polls the newest stable
`Foxboron/sbctl` GitHub release weekly and can also be run manually. It creates
or updates a `sync/upstream-<tag>` pull request; it never merges that pull
request. The workflow fetches and merges the immutable upstream tag, and a
merge conflict fails the run for manual resolution. A sync PR dispatches the
Debian build workflow, but only a push to `trixie` can sign and publish the APT
repository.

GitHub does not emit normal PR workflow runs for PRs created with
`GITHUB_TOKEN`. The explicit dispatch therefore runs **all three** packaging
checks on the sync branch head, including ownership against `origin/trixie`.
Do not skip ownership for dispatches or replace this with `pull_request_target`:
the latter could expose privileged credentials to upstream code. If `trixie`
advances during sync review, rerun the sync workflow to regenerate the sync
branch from the new `trixie` tip, then review and check it again. The ownership
check requires that tip to precede the tagged upstream merge; using GitHub's
**Update branch** button to merge it afterward does not satisfy that model.
Do not rebase or squash the upstream merge.

The repository must allow merge commits and disable squash and rebase merges.
The sync workflow verifies these settings because a merge commit preserves the
upstream ancestry without copying upstream messages into a new commit. The sync
pull request links to the upstream compare view instead; copied issue links can
create cross-repository backlinks and notifications.

The initial `0.18` import has no shared Git ancestry with upstream. The first
sync run creates a reviewed, tree-preserving ancestry baseline for that tag.
Later release updates use ordinary Git merges. The sync helper updates the
first `debian/changelog` entry to `<upstream-version>-1~local1`, stripping a
leading `v` from upstream tags.

Locally maintained paths are `debian/**`, this file, `renovate.json`,
`.github/workflows/debian-*.yml`, `.github/scripts/debian-*.sh`, and
`.github/debian-upstream-release`. Renovate is limited to the
two locally maintained workflow files. The ownership job rejects ordinary pull
requests that modify other paths. A sync PR may modify upstream-owned paths
only through its tagged upstream merge; its follow-up Debian version and
metadata changes remain within the local boundary.

Downstream GitHub automation uses the `debian-` filename prefix and the
`Debian: …` workflow display prefix to distinguish it from mirrored upstream
automation and avoid filename collisions during syncs. Standard `debian/**`
filenames and this document keep their names. Required-check job names stay
stable when workflows are renamed. The ownership check permits deleting the
former downstream names during migration, but rejects recreating them.

### Required GitHub environment

Create a protected GitHub Actions environment named `apt-signing` and keep it
restricted to your `trixie` branch.
Use a selected **branch** rule named exactly `trixie`, not an all-protected-
branches rule. Keep the signing secrets out of repository and organization
secret scopes so same-repository PR workflows cannot access them. The package
workflow references them only in its push-only `apt-signing` job; PRs and
dispatches use a new throwaway key instead.

Add these secrets in that environment:

- `APT_GPG_PRIVATE_KEY`: ASCII-armored private key used to sign Release files.
- `APT_GPG_PUBLIC_KEY`: matching ASCII-armored public key.
- `APT_GPG_KEY_ID`: key id or fingerprint used by `gpg --default-key`.

### Administrator merge-gate settings

Inspection on 2026-11-04 found three active rulesets:

- `protect-trixie` (`15798536`) targets `refs/heads/trixie` and only blocks
  force pushes. It does not require checks.
- `Branch` (`24537982`) targets the default branch (`trixie`). It requires a
  PR, resolved conversations, approval of the latest reviewable push, and merge
  commits, but its approving-review count is zero. It also blocks deletion and
  force pushes.
- `Tags` (`24537878`) restricts tag creation, updates, and deletion.

The `apt-signing` environment already selects the `trixie` branch and holds
all three APT secrets; the repository-level secret list is empty. No ruleset,
environment, or repository setting was changed for this work.

After the updated workflow has run, a repository administrator should apply:

1. In **Settings → Rules → Rulesets → protect-trixie**, keep enforcement
   **Active**, target `trixie` explicitly, retain **Block force pushes**, and
   add **Require status checks to pass** with these exact check names, each
   sourced from **GitHub Actions** (integration ID `15368`):
   - `Verify downstream ownership boundary`
   - `Build trixie .deb artifacts`
   - `Verify Debian packages and signed APT repository`
2. Enable **Require branches to be up to date before merging**. Do not permit
   bypasses for the sync bot. A failed or missing dispatched check must block
   a sync PR just like a normal PR.
3. Recommended for upstream-sync review: in **Branch → Require a pull request
   before merging**, set **Required approvals: 1** and **Dismiss stale pull
   request approvals when new commits are pushed: enabled**. Keep approval of
   the latest push and conversation resolution enabled. GitHub branch rules
   cannot limit approval requirements to source branches named `sync/*`, so
   this also requires another reviewer for human-authored packaging PRs. A
   maintainer can approve bot-authored sync PRs; a sole maintainer cannot
   approve their own PRs. Add a reviewer before enabling this if necessary.
4. Keep **merge commits** as the only merge method, and leave **Require linear
   history** disabled. Leave the tag rules unchanged: syncing fetches upstream
   tags locally and does not need permission to create repository tags.

Do not require the publish/deploy jobs: they intentionally do not run on PRs.
The three packaging checks cover upstream-sync PRs without requiring the
upstream-owned CI workflows or modifying upstream source.

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
