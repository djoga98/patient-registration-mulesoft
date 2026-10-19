#!/usr/bin/env bash
# Live failure-mode checks against the locally running stack (complements MUnit,
# where lower APIs are mocked).
#
#   scripts/e2e-failure-modes.sh <existing-patient-id>
#
# 1. Database down: the PostgreSQL container is stopped (not removed; no data is
#    touched) -> GET and POST answer 502 DOWNSTREAM_ERROR through all layers, with
#    no stack trace, SQL or host name in the body. The container is restarted and
#    the API recovers.
# 2. System API unreachable: patient-sys-api is undeployed from the local runtime
#    -> the Process API retries the GET 3 times, the Experience API makes 1 call and
#    answers 502; a POST is attempted exactly once. The app is redeployed afterwards.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
patient_id="${1:?usage: $0 <existing-patient-id>}"
exp="http://localhost:8081/api/patients"
mule_base="${MULE_BASE:-$root/.mule-base}"
log_dir="${MULE_LOG_DIR:-${MULE_HOME:?set MULE_HOME (or MULE_LOG_DIR)}/logs}"
body="$root/scripts/fixtures/failure-mode-registration.json"
fail=0

check() { # name expected-status actual-status body
    if [[ "$3" == "$2" ]] && grep -q '"code": *"DOWNSTREAM_ERROR"' <<<"$4" \
       && ! grep -qiE 'exception|select |insert |jdbc|localhost|\bat [a-z]+\.' <<<"$4"; then
        echo "PASS: $1 -> $3 DOWNSTREAM_ERROR, no internals in body"
    else
        echo "FAIL: $1 -> $3: $4"; fail=1
    fi
}
call() { # method url [body-file] -> sets status, response
    local cid; cid="failure-mode-$(date +%s%N)"
    local args=(-s -w '\n%{http_code}' -X "$1" "$2" -H "X-Correlation-ID: $cid")
    [[ $# -ge 3 ]] && args+=(-H 'Content-Type: application/json' --data-binary "@$3")
    local out; out=$(curl "${args[@]}")
    status=${out##*$'\n'}; response=${out%$'\n'*}; last_cid=$cid
}
events() { # app event [field=value ...] -> how many of that app's events the last call logged
    local app="$1"; shift
    node "$root/scripts/log-events.js" count "$log_dir/$app.log" "$last_cid" "$@"
}
wait_for() { # url expected-status
    for _ in $(seq 1 60); do
        [[ "$(curl -s -o /dev/null -w '%{http_code}' "$1")" == "$2" ]] && return 0; sleep 2
    done
    return 1
}

echo "== 1. database down"
docker stop patient-registration-postgres >/dev/null
call GET "$exp/$patient_id";   check "GET with database down" 502 "$status" "$response"
call POST "$exp" "$body";      check "POST with database down" 502 "$status" "$response"
docker start patient-registration-postgres >/dev/null
wait_for "$exp/$patient_id" 200 && echo "PASS: recovered after database restart" || { echo "FAIL: no recovery"; fail=1; }

echo "== 2. System API unreachable"
rm -f "$mule_base/apps/patient-sys-api-anchor.txt"          # undeploys the app
# Wait until the runtime has removed the app, not just until the port refuses new
# connections: the Process API's pooled keep-alive connections are served until disposal ends.
for _ in $(seq 1 60); do [[ -d "$mule_base/apps/patient-sys-api" ]] || break; sleep 1; done
sleep 3
call GET "$exp/$patient_id";   check "GET with System API down" 502 "$status" "$response"
sleep 2   # application loggers are asynchronous
attempts=$(events patient-prc-api downstream.request target=system-api method=GET)
calls=$(events patient-exp-api downstream.request target=process-api method=GET)
[[ "$attempts" == 3 && "$calls" == 1 ]] \
    && echo "PASS: Process API made 3 GET attempts, Experience API 1 call" \
    || { echo "FAIL: GET attempts prc=$attempts exp=$calls (expected 3 and 1)"; fail=1; }
call POST "$exp" "$body";      check "POST with System API down" 502 "$status" "$response"
sleep 2
attempts=$(events patient-prc-api downstream.request target=system-api method=POST)
[[ "$attempts" == 1 ]] && echo "PASS: POST attempted once (never retried)" || { echo "FAIL: POST attempts=$attempts"; fail=1; }

cp "$root/patient-sys-api/target/patient-sys-api-1.0.0-mule-application.jar" "$mule_base/apps/patient-sys-api.jar"
wait_for "$exp/$patient_id" 200 && echo "PASS: recovered after System API redeploy" || { echo "FAIL: no recovery"; fail=1; }

exit $fail
