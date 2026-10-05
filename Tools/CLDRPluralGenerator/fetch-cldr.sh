#!/bin/sh
# Maintainer workflow: download the pinned cldr-json release into Data/ and
# verify it against the recorded checksums.
#
# To move to a new CLDR release: change the tag and commit in Data/SOURCE, run
# this script with UPDATE_CHECKSUMS=1, review the diff of Data/, then run
# regenerate.sh and the package tests.
set -eu
cd "$(dirname "$0")/Data"
commit=$(sed -n 's/^commit: //p' SOURCE)
base="https://raw.githubusercontent.com/unicode-org/cldr-json/$commit"
curl -fsSL -o plurals.json "$base/cldr-json/cldr-core/supplemental/plurals.json"
curl -fsSL -o ordinals.json "$base/cldr-json/cldr-core/supplemental/ordinals.json"
curl -fsSL -o LICENSE "$base/LICENSE"
if [ "${UPDATE_CHECKSUMS:-0}" = 1 ]; then
    shasum -a 256 LICENSE ordinals.json plurals.json > SHA256SUMS
fi
shasum -a 256 -c SHA256SUMS
