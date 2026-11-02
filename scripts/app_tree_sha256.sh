#!/bin/bash
# Path-independent app-bundle tree hash: hash each file's sha256 with its bundle-relative path, sorted.
# The digest depends only on bundle contents (file set + bytes), not on where the bundle is staged.
set -euo pipefail
APP="${1:?usage: app_tree_sha256.sh APP_BUNDLE}"
[ -d "$APP" ] || { echo "missing" ; exit 3; }
( cd "$APP" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}' )
