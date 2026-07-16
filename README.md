# sec-pipelines

Production-grade **multi-cloud DevSecOps pipeline** with secure infrastructure-as-code.

Shift-left security gates, zero-trust OIDC authentication (no long-lived cloud
credentials), and multi-cloud deploy (AWS + Azure). Runs on **GitHub Actions,
GitLab CI, and Jenkins** from one shared implementation.

## Portable by design

The security logic lives in `./scripts` and is exposed through a `Makefile`.
Every CI platform is a thin wrapper that calls the same `make` targets, so the
gates behave identically everywhere — only orchestration (job graph, OIDC login,
approval gates) is platform-specific.

```
scripts/*.sh   →  Makefile targets  →  { .github/workflows/devsecops.yml
                                         .gitlab-ci.yml
                                         Jenkinsfile }
```

| Concern | GitHub Actions | GitLab CI | Jenkins |
|---------|---------------|-----------|---------|
| Gate logic | `make scan-*` | `make scan-*` | `make scan-*` |
| Parallel gates | job fan-out | shared `scan` stage | `parallel {}` |
| OIDC token | `configure-aws-credentials` / `azure/login` | `id_tokens:` | OIDC Provider plugin |
| Token → creds | native action | `scripts/aws-oidc-login.sh` | `scripts/aws-oidc-login.sh` |
| SARIF sink | Security tab | job artifacts | archived artifacts |
| Prod gate | protected environment | `when: manual` | `input` step |

Run any gate locally too: `make scan-secrets`, `make build-scan APP=app-python`, etc.

## Architecture — fail-fast enforcement

Three-stage DAG. Stage boundaries enforced by `needs:`. Any red job kills
everything downstream — the image is never built, never pushed, never deployed.

```
STAGE 1 (parallel gates, PR + push)
  secrets-scan ─┐
  iac-scan ─────┤
  sast ─────────┼──▶ STAGE 2: build + trivy scan ──▶ STAGE 3: deploy staging ──▶ deploy prod
  sca ──────────┘       (push to ECR/ACR only            (OIDC, no keys)       (protected env,
                         AFTER image passes scan)                              manual approval)
```

Within each job, scanners run with hard-fail flags. A threshold breach produces
a non-zero exit, which fails the job and stops the pipeline. SARIF still uploads
on failure (`if: always()`) so findings land in the GitHub Security tab.

## Security gates

| Stage | Tool | Scope | Fail condition |
|-------|------|-------|----------------|
| Secrets | Gitleaks | Full git history (`fetch-depth: 0`) | Any finding |
| IaC | Checkov | Terraform + GitHub Actions | HIGH/CRITICAL policy fail (`soft_fail: false`) |
| SAST (Python) | Semgrep | `app-python/` | Any blocking finding (`--error`) |
| SAST (Java) | Semgrep | `app-java/` | Any blocking finding (`--error`) |
| SCA (Python) | pip-audit | `requirements.txt` | Any known vuln (`--strict`) |
| SCA (Java) | OWASP Dependency-Check | Maven deps | `failBuildOnCVSS=7` |
| Image | Trivy | Built image, pre-push | HIGH/CRITICAL (`exit-code: 1`) |

## Zero-trust authentication

No AWS access keys, no Azure client secrets are ever stored. Auth is OIDC only:

- **AWS** — `aws-actions/configure-aws-credentials` assumes an IAM role whose
  trust policy exact-matches `repo:acaacx/sec-pipelines:environment:<env>`.
- **Azure** — `azure/login` uses an Entra federated identity credential with the
  same subject claim. No secret exists.

The only real secrets in GitHub are `NVD_API_KEY` (NVD feed access) and the
optional `GITLEAKS_LICENSE`. Cloud identifiers (role ARNs, client/tenant/
subscription IDs) live in GitHub Environment **variables**, not secrets.

## Layout

```
Makefile                          # portable entry point (also for local dev)
scripts/                          # shared gate/build/deploy/OIDC logic
.github/workflows/devsecops.yml   # GitHub Actions wrapper
.gitlab-ci.yml                    # GitLab CI wrapper
Jenkinsfile                       # Jenkins wrapper
terraform/oidc_setup.tf           # AWS IAM OIDC + Entra federated identity (GitHub)
terraform/oidc_ci.tf              # GitLab + Jenkins OIDC (feature-flagged)
terraform/environments/*.tfvars   # per-env non-secret vars
.gitleaks.toml                    # secrets-scan tuning
.checkov.yaml                     # IaC-scan tuning
app-python/                       # sample Flask workload + Dockerfile
app-java/                         # sample Spring Boot workload + Dockerfile
```

## Enabling GitLab / Jenkins OIDC

`oidc_setup.tf` covers GitHub. For the other platforms, set the feature flags in
`oidc_ci.tf` (each is a distinct OIDC issuer + subject claim, so each needs its
own trust policy and Entra federated credential):

```bash
# GitLab
terraform apply -var enable_gitlab=true -var gitlab_project_path=mygroup/sec-pipelines
# Jenkins (issuer/subject from the OpenID Connect Provider plugin)
terraform apply -var enable_jenkins=true \
  -var jenkins_issuer=https://jenkins.example.com/oidc \
  -var jenkins_subject='...'
```

## Setup

1. Create GitHub Environments `staging` and `production` (prod: required reviewers).
2. From a trusted workstation with owner-level AWS + Azure credentials, apply the
   OIDC federation once:
   ```bash
   cd terraform
   terraform init
   terraform apply -var-file=environments/staging.tfvars
   ```
3. Paste the `terraform output` values into GitHub Environment **variables**
   (`AWS_STAGING_ROLE_ARN`, `AWS_PRODUCTION_ROLE_ARN`, `AZURE_CLIENT_ID`,
   `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`).
4. Add the `NVD_API_KEY` repo secret.

From then on the pipeline holds zero cloud credentials.
