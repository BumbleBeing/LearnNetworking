#!/usr/bin/env bash
# Installs the GUT test framework (v9.3.0) into addons/gut. Not vendored to keep the repo small.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d addons/gut ] && { echo "addons/gut already present"; exit 0; }
tmp=$(mktemp -d)
git clone -q --depth 1 --branch v9.3.0 https://github.com/bitwes/Gut "$tmp/gut"
mkdir -p addons && cp -r "$tmp/gut/addons/gut" addons/gut
rm -rf "$tmp"
echo "GUT installed"
