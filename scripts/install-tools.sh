#!/usr/bin/env bash
# =============================================================================
# Idempotently install pinned scanner versions on a Linux CI agent.
# Safe to run on GitHub Actions, GitLab CI, or Jenkins. Installs only what is
# missing. Python tools via pipx/pip; Go binaries downloaded to /usr/local/bin.
# Java Dependency-Check runs via the Maven plugin (no install needed).
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib.sh"

BIN_DIR="${BIN_DIR:-/usr/local/bin}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) GH_ARCH="x64"; TRIVY_ARCH="64bit" ;;
  aarch64 | arm64) GH_ARCH="arm64"; TRIVY_ARCH="ARM64" ;;
  *) die "unsupported arch: $ARCH" ;;
esac

sudo_if() { if [ "$(id -u)" -ne 0 ]; then sudo "$@"; else "$@"; fi; }

install_gitleaks() {
  have gitleaks && return 0
  log "installing gitleaks ${GITLEAKS_VERSION}"
  local url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GH_ARCH}.tar.gz"
  curl -sSfL "$url" | tar -xz -C /tmp gitleaks
  sudo_if install -m 0755 /tmp/gitleaks "${BIN_DIR}/gitleaks"
}

install_trivy() {
  have trivy && return 0
  log "installing trivy ${TRIVY_VERSION}"
  local url="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz"
  curl -sSfL "$url" | tar -xz -C /tmp trivy
  sudo_if install -m 0755 /tmp/trivy "${BIN_DIR}/trivy"
}

install_python_tools() {
  log "installing checkov/semgrep/pip-audit via pip"
  python3 -m pip install --quiet --upgrade pip
  python3 -m pip install --quiet \
    "checkov==${CHECKOV_VERSION}" \
    "semgrep==${SEMGREP_VERSION}" \
    "pip-audit==${PIP_AUDIT_VERSION}"
}

install_gitleaks
install_trivy
install_python_tools

log "tool versions:"
gitleaks version || true
trivy --version || true
checkov --version || true
semgrep --version || true
pip-audit --version || true
