#!/usr/bin/env bash
# Installs the GUT test framework (v9.7.1, the release for Godot 4.7) into addons/gut. Not vendored to keep the repo small.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d addons/gut ] && { echo "addons/gut already present"; exit 0; }
tmp=$(mktemp -d)
git clone -q --depth 1 --branch v9.7.1 https://github.com/bitwes/Gut "$tmp/gut"
mkdir -p addons && cp -r "$tmp/gut/addons/gut" addons/gut
rm -rf "$tmp"
echo "GUT installed"
