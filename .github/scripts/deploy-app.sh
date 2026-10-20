#!/usr/bin/env bash
# Publishes one application to Exchange and deploys it to CloudHub 2.0
# (mule-maven-plugin, profile cloudhub2). Tests are skipped: the build-test job
# already ran them on the same commit.
#
#   .github/scripts/deploy-app.sh <app-dir>
#
# Environment (from the workflow): CLOUDHUB_ENVIRONMENT, CLOUDHUB_TARGET,
# CLOUDHUB_MULE_VERSION, CLOUDHUB_RELEASE_CHANNEL, plus the variables the cloudhub2
# profile reads (ANYPOINT_*, MULE_SECURE_KEY, DB_URL, SYS_API_HOST, PRC_API_HOST,
# SYS_API_CLIENT_ID/SECRET, PRC_API_CLIENT_ID/SECRET). SYS_API_ID / PRC_API_ID are the
# API Manager instance IDs of the System / Process API: when set, the app pairs with it
# (autodiscovery) and the gatekeeper stays on (flexible); when empty, the placeholder
# ID 0 is used with the gatekeeper disabled, so the unmanaged API is not blocked.
set -euo pipefail

app="${1:?app directory}"
args=(
    -B -ntp -s "${GITHUB_WORKSPACE:?}/.ci-settings.xml"
    -P cloudhub2 -DmuleDeploy -DskipMunitTests
    "-Dcloudhub.environment=${CLOUDHUB_ENVIRONMENT:?}"
    "-Dcloudhub.target=${CLOUDHUB_TARGET:?}"
    "-Dcloudhub.muleVersion=${CLOUDHUB_MULE_VERSION:?}"
    "-Dcloudhub.releaseChannel=${CLOUDHUB_RELEASE_CHANNEL:?}"
)

case "$app" in
    patient-sys-api) api_id="${SYS_API_ID:-}" ;;
    patient-prc-api) api_id="${PRC_API_ID:-}" ;;
    *)               api_id="" ;;
esac
if [[ -n "$api_id" ]]; then
    args+=("-Dcloudhub.apiId=$api_id" "-Dcloudhub.gatekeeper=flexible")
else
    args+=("-Dcloudhub.apiId=0" "-Dcloudhub.gatekeeper=disabled")
fi

cd "$app"
mvn "${args[@]}" clean deploy
