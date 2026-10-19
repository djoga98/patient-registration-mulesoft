#!/usr/bin/env bash
# Writes the Maven settings.xml used by the workflows. Values come only from the
# environment (GitHub Secrets); the file is created on the runner and never committed.
#
#   ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET   Connected App (client credentials).
#       Server "anypoint-exchange-v3": Exchange Maven facade, used to download Exchange
#       dependencies and to publish the applications before a CloudHub 2.0 deployment.
#       Format documented by MuleSoft: username ~~~Client~~~, password clientID~?~clientSecret.
#   MULE_EE_REPO_USERNAME / MULE_EE_REPO_PASSWORD (optional)
#       MuleSoft Enterprise repository ("MuleRepository", releases-ee). MUnit downloads the
#       Mule EE runtime from it; MuleSoft issues these credentials to customers via Support.
#       Without them, the build can only use EE artifacts already in the Maven cache.
#
#   .github/scripts/write-maven-settings.sh <output-file>
set -euo pipefail

out="${1:?usage: $0 <output-file>}"
: "${ANYPOINT_CLIENT_ID:?ANYPOINT_CLIENT_ID secret is not set}"
: "${ANYPOINT_CLIENT_SECRET:?ANYPOINT_CLIENT_SECRET secret is not set}"

xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g" <<<"$1"; }

ee_server="" ee_profile="" ee_active=""
if [[ -n "${MULE_EE_REPO_USERNAME:-}" && -n "${MULE_EE_REPO_PASSWORD:-}" ]]; then
    ee_server="
    <server>
      <id>MuleRepository</id>
      <username>$(xml_escape "$MULE_EE_REPO_USERNAME")</username>
      <password>$(xml_escape "$MULE_EE_REPO_PASSWORD")</password>
    </server>"
    ee_profile="
    <profile>
      <id>mule-enterprise</id>
      <repositories>
        <repository>
          <id>MuleRepository</id>
          <url>https://repository.mulesoft.org/nexus-ee/content/repositories/releases-ee/</url>
        </repository>
      </repositories>
      <pluginRepositories>
        <pluginRepository>
          <id>MuleRepository</id>
          <url>https://repository.mulesoft.org/nexus-ee/content/repositories/releases-ee/</url>
        </pluginRepository>
      </pluginRepositories>
    </profile>"
    ee_active="
    <activeProfile>mule-enterprise</activeProfile>"
    echo "settings.xml: Exchange (Connected App) + MuleSoft Enterprise repository"
else
    echo "settings.xml: Exchange (Connected App) only; MULE_EE_REPO_* not set" >&2
fi

umask 077
cat > "$out" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0 https://maven.apache.org/xsd/settings-1.2.0.xsd">
  <servers>
    <server>
      <id>anypoint-exchange-v3</id>
      <username>~~~Client~~~</username>
      <password>$(xml_escape "$ANYPOINT_CLIENT_ID")~?~$(xml_escape "$ANYPOINT_CLIENT_SECRET")</password>
    </server>${ee_server}
  </servers>
  <profiles>${ee_profile}
  </profiles>
  <activeProfiles>${ee_active}
  </activeProfiles>
</settings>
XML
