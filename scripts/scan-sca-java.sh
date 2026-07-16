#!/usr/bin/env bash
# Gate 4b — Java SCA via OWASP Dependency-Check. failBuildOnCVSS=7 => any
# dependency with CVSS >= 7 fails the build.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

: "${NVD_API_KEY:?NVD_API_KEY must be set for the NVD data feed}"

log "OWASP Dependency-Check: scanning app-java Maven dependencies"
cd "$REPO_ROOT/app-java"
mvn --batch-mode --no-transfer-progress \
  "org.owasp:dependency-check-maven:${DEPENDENCY_CHECK_MAVEN_VERSION}:check" \
  -DnvdApiKey="${NVD_API_KEY}" \
  -DdataDirectory="${HOME}/.dependency-check-data" \
  -DfailBuildOnCVSS=7 \
  -DsuppressionFiles=dependency-check-suppressions.xml \
  -Dformats=HTML,JSON
