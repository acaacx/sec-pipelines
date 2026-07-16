#!/usr/bin/env bash
# =============================================================================
# Shared helpers + pinned tool versions.
# Sourced by every scan/build script so behaviour is IDENTICAL across
# GitHub Actions, GitLab CI, and Jenkins. The CI YAML is a thin wrapper;
# the security logic lives here.
# =============================================================================
set -euo pipefail

# ---- Pinned tool versions — single source of truth --------------------------
export GITLEAKS_VERSION="${GITLEAKS_VERSION:-8.21.2}"
export CHECKOV_VERSION="${CHECKOV_VERSION:-3.2.334}"
export SEMGREP_VERSION="${SEMGREP_VERSION:-1.97.0}"
export TRIVY_VERSION="${TRIVY_VERSION:-0.58.1}"
export PIP_AUDIT_VERSION="${PIP_AUDIT_VERSION:-2.7.3}"
export DEPENDENCY_CHECK_MAVEN_VERSION="${DEPENDENCY_CHECK_MAVEN_VERSION:-12.1.0}"

# ---- Repo root, independent of caller CWD -----------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# ---- Logging helpers --------------------------------------------------------
log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
