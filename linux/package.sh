#!/usr/bin/env bash
# Builds the Linux archive from the mod already compiled by package.bat.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT

mkdir "$stage/DR2_Autosave_Mod"
tr -d '\r' <"$root/linux/install.sh" >"$stage/DR2_Autosave_Mod/install.sh"
chmod +x "$stage/DR2_Autosave_Mod/install.sh"
cp "$root/out/d3dx9_43.dll" "$root/linux/README-LINUX.txt" "$stage/DR2_Autosave_Mod/"
# The neutral owner keeps the builder's user name out of the published archive.
(cd "$stage" && tar --owner=0 --group=0 --numeric-owner -czf archive.tar.gz DR2_Autosave_Mod)
mv -f "$stage/archive.tar.gz" "$root/dist/DR2_Autosave_Mod_1.0_Linux.tar.gz"
echo "Package ready: dist/DR2_Autosave_Mod_1.0_Linux.tar.gz"
