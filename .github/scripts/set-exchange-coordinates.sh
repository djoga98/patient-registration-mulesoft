#!/usr/bin/env bash
# Sets an application's Maven groupId and version for publishing to Exchange.
# Exchange requires groupId = the business group (organization) ID, and released
# versions are immutable, so every deployment publishes a new version.
#
#   .github/scripts/set-exchange-coordinates.sh <app-dir> <business-group-id> <version>
#
# Edits only the project's own <groupId>/<version> (the first ones in the POM; the
# applications have no parent). Runs on the CI runner checkout, never committed.
set -euo pipefail

app="${1:?app directory}"; group="${2:?business group id}"; version="${3:?version}"
pom="$app/pom.xml"

[[ "$group" =~ ^[A-Za-z0-9-]+$ ]] || { echo "invalid business group id" >&2; exit 1; }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid version: $version" >&2; exit 1; }

sed -i -e "0,/<groupId>com\.acme\.clinic<\/groupId>/s//<groupId>${group}<\/groupId>/" \
       -e "0,/<version>1\.0\.0<\/version>/s//<version>${version}<\/version>/" "$pom"

if ! grep -q "<groupId>${group}</groupId>" "$pom" || ! grep -q "<version>${version}</version>" "$pom"; then
    echo "could not set coordinates in $pom" >&2
    exit 1
fi
echo "$app -> ${group}:$(basename "$app"):${version}"
