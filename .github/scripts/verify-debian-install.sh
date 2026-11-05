#!/usr/bin/env bash
# CI smoke test for the built packages and the signed repository before publishing.
# Check installation/configuration and CLI startup, either from local .debs or
# authenticated APT downloads. This does not test firmware or Secure Boot behavior.
# Run only as root in a disposable trixie container without host EFI mounts.
set -euo pipefail

[[ $# -eq 1 && ( "$1" == deb || "$1" == apt ) ]] || {
  echo 'Usage: verify-debian-install.sh {deb|apt} (mount /artifacts and /repo)' >&2
  exit 1
}
export DEBIAN_FRONTEND=noninteractive
apt-get update --error-on=any
apt-get install -y --no-install-recommends ca-certificates

binary=(/artifacts/sbctl-bin_*_amd64.deb)
automation=(/artifacts/sbctl_*_all.deb)
[[ ${#binary[@]} -eq 1 && -f "${binary[0]}" && ${#automation[@]} -eq 1 && -f "${automation[0]}" ]]
binary_version="$(dpkg-deb -f "${binary[0]}" Version)"
automation_version="$(dpkg-deb -f "${automation[0]}" Version)"

if [[ "$1" == deb ]]; then
  apt-get install -y --no-install-recommends "${binary[0]}" "${automation[0]}"
else
  install -Dm644 /repo/sbctl-archive-keyring.gpg /etc/apt/keyrings/sbctl-archive-keyring.gpg
  cat > /etc/apt/sources.list.d/sbctl.sources <<'EOF'
Types: deb
URIs: file:/repo
Suites: trixie
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/sbctl-archive-keyring.gpg
EOF
  # A source-restricted update otherwise removes the Debian dependency indexes.
  lists_dir="$(mktemp -d)"
  chmod 755 "$lists_dir"
  source_options=(
    -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/sbctl.sources
    -o Dir::Etc::sourceparts=-
    -o "Dir::State::lists=$lists_dir"
  )
  # Refresh the candidate source explicitly and fail on any signature or index
  # error. No trusted=yes or insecure repository overrides.
  apt-get "${source_options[@]}" update --error-on=any
  download_dir="$(mktemp -d)"
  chmod 755 "$download_dir"
  # Restrict package retrieval to this source, even if Debian has the same
  # version. Re-enable Debian sources only for dependency resolution at install.
  (cd "$download_dir" && apt-get "${source_options[@]}" download \
    "sbctl-bin=$binary_version" "sbctl=$automation_version")
  downloaded_binary=("$download_dir"/sbctl-bin_*_amd64.deb)
  downloaded_automation=("$download_dir"/sbctl_*_all.deb)
  [[ ${#downloaded_binary[@]} -eq 1 && ${#downloaded_automation[@]} -eq 1 ]]
  cmp "${binary[0]}" "${downloaded_binary[0]}"
  cmp "${automation[0]}" "${downloaded_automation[0]}"
  apt-get install -y --no-install-recommends "${downloaded_binary[0]}" "${downloaded_automation[0]}"
fi

for package in sbctl-bin sbctl; do
  [[ "$(dpkg-query -W -f='${Status}' "$package")" == 'install ok installed' ]]
done
[[ "$(dpkg-query -W -f='${Version}' sbctl-bin)" == "$binary_version" ]]
[[ "$(dpkg-query -W -f='${Version}' sbctl)" == "$automation_version" ]]
[[ -z "$(dpkg --audit)" ]]
/usr/bin/sbctl --help
/usr/bin/sbctl completion bash > /dev/null
test -s /usr/share/man/man8/sbctl.8.gz
test -s /etc/sbctl/sbctl.conf
