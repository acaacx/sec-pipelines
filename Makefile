# =============================================================================
# Portable entry point for every CI platform (and local dev).
# GitHub Actions, GitLab CI, and Jenkins all call these targets, so the
# security gates behave identically everywhere. Each target exits non-zero on a
# threshold breach — that is the fail-fast contract.
# =============================================================================
SHELL := /usr/bin/env bash
S     := scripts

.PHONY: help install \
        scan scan-secrets scan-iac scan-sast scan-sca \
        sast-python sast-java sca-python sca-java \
        build-scan deploy-staging deploy-production

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

install:            ## Install pinned scanner versions on the agent
	@$(S)/install-tools.sh

# ---- Stage 1: security gates ------------------------------------------------
scan: scan-secrets scan-iac scan-sast scan-sca  ## Run all Stage-1 gates

scan-secrets:       ## Gitleaks — secrets over full history
	@$(S)/scan-secrets.sh

scan-iac:           ## Checkov — Terraform + Actions
	@$(S)/scan-iac.sh

scan-sast: sast-python sast-java  ## Semgrep — all languages
sast-python:        ## Semgrep — Python
	@$(S)/scan-sast.sh app-python python
sast-java:          ## Semgrep — Java
	@$(S)/scan-sast.sh app-java java

scan-sca: sca-python sca-java     ## SCA — all languages
sca-python:         ## pip-audit — Python deps
	@$(S)/scan-sca-python.sh
sca-java:           ## OWASP Dependency-Check — Java deps
	@$(S)/scan-sca-java.sh

# ---- Stage 2: build + image scan --------------------------------------------
# APP=app-python|app-java
build-scan:         ## Build image + Trivy scan (no push). APP=app-python
	@ref=$$($(S)/build-image.sh $(APP)); \
	  $(S)/scan-image.sh $$ref $(APP)

# ---- Stage 3: deploy --------------------------------------------------------
deploy-staging:     ## terraform apply — staging
	@$(S)/deploy.sh staging
deploy-production:  ## terraform apply — production
	@$(S)/deploy.sh production
