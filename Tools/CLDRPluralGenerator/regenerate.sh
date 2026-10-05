#!/bin/sh
# Maintainer workflow: regenerate the checked-in CLDR plural tables from the
# vendored data in Data/. Performs no network access.
set -eu
cd "$(dirname "$0")"
(cd Data && shasum -a 256 -c SHA256SUMS)
swift run --package-path . CLDRPluralGenerator
