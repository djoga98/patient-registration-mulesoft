#!/usr/bin/env bash
# Publishes one application to Exchange and deploys it to CloudHub 2.0
# (mule-maven-plugin, profile cloudhub2). Tests are skipped: the build-test job
# already ran them on the same commit.
#
#   .github/scripts/deploy-app.sh <app-dir>
#
# Environment (from the workflow): CLOUDHUB_ENVIRONMENT, CLOUDHUB_TARGET,
# CLOUDHUB_MULE_VERSION, CLOUDHUB_RELEASE_CHANNEL, plus the variables the cloudhub2
# profile reads (ANYPOINT_*, MULE_SECURE_KEY, DB_URL, SYS_API_HOST, PRC_API_HOST).
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

cd "$app"
mvn "${args[@]}" clean deploy
