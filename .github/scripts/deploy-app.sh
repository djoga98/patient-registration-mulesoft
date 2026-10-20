#!/usr/bin/env bash
# Publishes one application to Exchange and deploys it to CloudHub 2.0
# (mule-maven-plugin, profile cloudhub2). Tests are skipped: the build-test job
# already ran them on the same commit.
#
#   .github/scripts/deploy-app.sh <app-dir>
#
# CloudHub 2.0 deploys the asset from Exchange. The plugin's deploy phase either
# publishes to Exchange (plain `mvn deploy`) or deploys (`-DmuleDeploy`), never both, so:
#   1. mvn deploy: publish the version to Exchange;
#   2. wait until Exchange serves that version (it processes new versions asynchronously);
#   3. mvn deploy -DmuleDeploy: deploy it to CloudHub 2.0.
#
# Environment (from the workflow): CLOUDHUB_ENVIRONMENT, CLOUDHUB_TARGET,
# CLOUDHUB_MULE_VERSION, CLOUDHUB_RELEASE_CHANNEL, VERSION, plus the variables the
# cloudhub2 profile reads (ANYPOINT_*, MULE_SECURE_KEY, DB_URL, SYS_API_HOST,
# PRC_API_HOST, SYS_API_CLIENT_ID/SECRET, PRC_API_CLIENT_ID/SECRET). SYS_API_ID /
# PRC_API_ID are the API Manager instance IDs of the System / Process API: when set, the
# app pairs with it (autodiscovery) and the gatekeeper stays on (flexible); when empty,
# the placeholder ID 0 is used with the gatekeeper disabled, so the unmanaged API is not
# blocked.
set -euo pipefail

app="${1:?app directory}"
group="${ANYPOINT_BUSINESS_GROUP_ID:?}"
version="${VERSION:?}"
args=(
    -B -ntp -s "${GITHUB_WORKSPACE:?}/.ci-settings.xml"
    -P cloudhub2 -DskipMunitTests
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

# Polls the Exchange API until the version is published (at most ~5 minutes).
wait_for_exchange() {
    local token status url="https://anypoint.mulesoft.com/exchange/api/v2/assets/$group/$app/$version"
    token=$(printf 'grant_type=client_credentials&client_id=%s&client_secret=%s' \
                "${ANYPOINT_CLIENT_ID:?}" "${ANYPOINT_CLIENT_SECRET:?}" |
            curl -sf -X POST https://anypoint.mulesoft.com/accounts/api/v2/oauth2/token \
                 -H 'Content-Type: application/x-www-form-urlencoded' --data @- |
            jq -r '.access_token')
    [[ -n "$token" && "$token" != null ]] || { echo "could not get an Anypoint access token" >&2; return 1; }
    local body code
    body=$(mktemp)
    for _ in $(seq 1 30); do
        code=$(curl -s -o "$body" -w '%{http_code}' -H "Authorization: Bearer $token" "$url" || true)
        status=$(jq -r '.status // empty' "$body" 2>/dev/null || true)
        if [[ "$code" == 200 && ( -z "$status" || "$status" == published ) ]]; then
            echo "Exchange: $app $version is available"
            return 0
        fi
        echo "Exchange: waiting for $app $version (HTTP $code${status:+, $status})"
        sleep 10
    done
    echo "Exchange: $app $version was not published within 5 minutes" >&2
    return 1
}

cd "$app"
mvn "${args[@]}" clean deploy
wait_for_exchange
mvn "${args[@]}" -DmuleDeploy deploy
