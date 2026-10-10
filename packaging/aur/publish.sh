#!/usr/bin/env bash
# Publishes this folder to the AUR as talkify-omarchy: the PKGBUILD, its
# install hooks and a fresh .SRCINFO. The AUR account needs this machine's
# key (~/.ssh/aur.pub here) under My Account → SSH Public Key. Run it again
# after bumping pkgver or pkgrel.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone --quiet ssh://aur@aur.archlinux.org/talkify-omarchy.git "$work"
cp "$here/PKGBUILD" "$here/talkify-omarchy.install" "$work/"
(cd "$here" && makepkg --printsrcinfo) > "$work/.SRCINFO"

cd "$work"
git add PKGBUILD .SRCINFO talkify-omarchy.install
if git diff --cached --quiet; then
  echo "The AUR already has this version."
  exit 0
fi
version="$(sed -n 's/^\tpkgver = //p' .SRCINFO)-$(sed -n 's/^\tpkgrel = //p' .SRCINFO)"
git commit --quiet -m "talkify-omarchy $version"
git push --quiet origin HEAD:master
echo "Published talkify-omarchy $version: https://aur.archlinux.org/packages/talkify-omarchy"
