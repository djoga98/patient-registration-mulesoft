#!/usr/bin/env bash
# Runs the three applications on a local Mule 4 standalone runtime, without the
# Tanuki service wrapper (which needs an interactive console).
#
#   MULE_HOME=/path/to/mule-enterprise-standalone-4.x scripts/run-mule-local.sh [app ...]
#
# - Packages each app (tests skipped: run `mvn clean verify` for those).
# - Uses a separate MULE_BASE (default: ./.mule-base, git-ignored), so the runtime
#   installation itself is never modified.
# - Reads MULE_SECURE_KEY from infrastructure/.env and passes it as -Dsecure.key.
# - The runtime is not paired with API Manager (no platform credentials), so the API
#   gatekeeper is disabled: in its default FLEXIBLE mode it would block the System and
#   Process APIs (autodiscovery, see global.xml) with 503 until policies are applied.
# - MULE_EXTRA_OPTS adds JVM system properties, which override the apps' property files,
#   e.g. MULE_EXTRA_OPTS="-Ddb.url=jdbc:postgresql://localhost:5432/other_db" for a
#   separate test database.
# Stop with Ctrl-C.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
: "${MULE_HOME:?set MULE_HOME to a Mule 4.9+ standalone runtime}"
MULE_BASE="${MULE_BASE:-$root/.mule-base}"
apps=("$@")
[[ ${#apps[@]} -gt 0 ]] || apps=(patient-sys-api patient-prc-api patient-exp-api)

set -a; source "$root/infrastructure/.env"; set +a
: "${MULE_SECURE_KEY:?MULE_SECURE_KEY missing in infrastructure/.env}"

if [[ ! -f "$root/patient-sys-api/src/main/resources/config/secure-local.yaml" ]]; then
    "$root/scripts/generate-local-secrets.sh"
fi

mkdir -p "$MULE_BASE/apps" "$MULE_BASE/domains" "$MULE_BASE/logs" "$MULE_BASE/conf"
[[ -f "$MULE_BASE/conf/log4j2.xml" ]] || cp -r "$MULE_HOME/conf/." "$MULE_BASE/conf/"
# The container loads services and server plugins from MULE_BASE: link, don't copy.
for dir in services server-plugins; do
    [[ -e "$MULE_BASE/$dir" || ! -d "$MULE_HOME/$dir" ]] && continue
    if command -v cygpath >/dev/null; then
        MSYS_NO_PATHCONV=1 cmd /c mklink /J "$(cygpath -w "$MULE_BASE/$dir")" "$(cygpath -w "$MULE_HOME/$dir")" >/dev/null
    else
        ln -s "$MULE_HOME/$dir" "$MULE_BASE/$dir"
    fi
done

for app in "${apps[@]}"; do
    (cd "$root/$app" && mvn -q -o clean package -DskipTests)
    cp "$root/$app/target/$app-1.0.0-mule-application.jar" "$MULE_BASE/apps/$app.jar"
done

# Paths for the Windows JVM when running under Git Bash.
to_native() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
home="$(to_native "$MULE_HOME")"
base="$(to_native "$MULE_BASE")"

extra=()
[[ -n "${MULE_EXTRA_OPTS:-}" ]] && read -r -a extra <<<"$MULE_EXTRA_OPTS"

opens=()
for pkg in java.base/java.lang java.base/java.lang.reflect java.base/java.lang.invoke java.sql/java.sql \
           java.naming/javax.naming java.base/jdk.internal.ref java.base/java.nio java.base/sun.nio.ch \
           java.management/sun.management jdk.management/com.sun.management.internal; do
    opens+=("--add-opens=$pkg=org.mule.runtime.jpms.utils")
done

exec "${JAVA_HOME:+$JAVA_HOME/bin/}java" \
    -Xms1024m -Xmx1024m -XX:MaxMetaspaceSize=512m \
    -Dmule.home="$home" -Dmule.base="$base" \
    -Djava.net.preferIPv4Stack=TRUE -Dfile.encoding=UTF-8 \
    -Danypoint.platform.analytics_enabled=false \
    -Danypoint.platform.gatekeeper=disabled \
    -Dmule.bootstrap.container.wrapper.class=org.mule.runtime.module.boot.internal.MuleContainerBasicWrapper \
    -Denv=local -Dsecure.key="$MULE_SECURE_KEY" \
    "${extra[@]}" \
    "${opens[@]}" \
    -cp "$base/conf" \
    --module-path "$home/lib/boot" \
    --add-modules java.se,org.mule.runtime.boot.log4j,org.mule.runtime.logging,org.mule.runtime.jpms.utils,com.fasterxml.jackson.core,org.apache.commons.codec \
    -m com.mulesoft.mule.boot/com.mulesoft.mule.runtime.MuleContainerBootstrap
