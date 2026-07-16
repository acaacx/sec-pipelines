// =============================================================================
// DevSecOps Pipeline — Jenkins wrapper (declarative).
//
// Same shared logic as GitHub Actions and GitLab CI: every stage calls a
// `make` target backed by ./scripts. Jenkins-specific bits: parallel Stage-1
// gates, OIDC via the "OpenID Connect Provider" plugin (no stored cloud
// credentials), and an `input` step as the production approval gate.
//
// Prereqs on the controller/agents:
//   * Docker available on the agent
//   * Plugins: "OpenID Connect Provider" (issues id tokens for AWS/Azure STS),
//     "Pipeline", "Credentials Binding"
//   * OIDC credentials configured:
//       - oidc-aws   (audience: sts.amazonaws.com)
//       - oidc-azure (audience: api://AzureADTokenExchange)
//   * AWS IAM trust + Entra federated credential whose subject matches this
//     Jenkins issuer/subject (see terraform/oidc_ci.tf, enable_jenkins).
//
// Fail-fast: any make target exiting non-zero fails the stage; declarative
// Jenkins aborts the run and skips all downstream stages.
// =============================================================================
pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }

  environment {
    AWS_REGION            = 'eu-west-1'
    ECR_REPOSITORY        = 'devsecops-demo'
    ACR_NAME              = 'devsecopsdemoacr'
    IMAGE_TAG             = "${env.GIT_COMMIT}"
    // Non-secret identifiers — configure as Jenkins global env or folder props:
    //   AWS_STAGING_ROLE_ARN, AWS_PRODUCTION_ROLE_ARN,
    //   AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
    // NVD_API_KEY is the only real secret (Jenkins credential id: nvd-api-key).
  }

  stages {
    stage('Setup') {
      steps { sh 'make install' }
    }

    // ---- Stage 1: security gates (parallel, fail-fast) ----------------------
    stage('Security Gates') {
      parallel {
        stage('Secrets')     { steps { sh 'make scan-secrets' } }
        stage('IaC')         { steps { sh 'make scan-iac' } }
        stage('SAST Python') { steps { sh 'make sast-python' } }
        stage('SAST Java')   { steps { sh 'make sast-java' } }
        stage('SCA Python')  { steps { sh 'make sca-python' } }
        stage('SCA Java') {
          steps {
            withCredentials([string(credentialsId: 'nvd-api-key', variable: 'NVD_API_KEY')]) {
              sh 'make sca-java'
            }
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: '*.sarif, app-java/target/dependency-check-report.*',
                           allowEmptyArchive: true
        }
      }
    }

    // ---- Stage 2: build + Trivy gate + push --------------------------------
    stage('Build, Scan & Push') {
      matrix {
        axes {
          axis { name 'APP'; values 'app-python', 'app-java' }
        }
        stages {
          stage('Build + Trivy') {
            steps { sh 'make build-scan APP=${APP}' }
            post {
              always {
                archiveArtifacts artifacts: "trivy-${APP}.sarif", allowEmptyArchive: true
              }
            }
          }
          stage('Push to ECR + ACR') {
            when { branch 'main' }
            steps {
              // Plugin injects fresh OIDC JWTs into the bound env vars.
              withCredentials([
                string(credentialsId: 'oidc-aws',   variable: 'AWS_OIDC_TOKEN'),
                string(credentialsId: 'oidc-azure', variable: 'AZURE_OIDC_TOKEN')
              ]) {
                sh '''
                  export AWS_ROLE_ARN="$AWS_STAGING_ROLE_ARN"
                  eval "$(scripts/aws-oidc-login.sh)"
                  scripts/azure-oidc-login.sh
                  scripts/push-image.sh "$APP" "$APP:$IMAGE_TAG"
                '''
              }
            }
          }
        }
      }
    }

    // ---- Stage 3: deploy ----------------------------------------------------
    stage('Deploy Staging') {
      when { branch 'main' }
      steps {
        withCredentials([
          string(credentialsId: 'oidc-aws',   variable: 'AWS_OIDC_TOKEN'),
          string(credentialsId: 'oidc-azure', variable: 'AZURE_OIDC_TOKEN')
        ]) {
          sh '''
            export AWS_ROLE_ARN="$AWS_STAGING_ROLE_ARN"
            eval "$(scripts/aws-oidc-login.sh)"
            scripts/azure-oidc-login.sh
            make deploy-staging
          '''
        }
      }
    }

    stage('Approve Production') {
      when { branch 'main' }
      steps {
        // Manual approval gate — the Jenkins equivalent of a protected env.
        input message: 'Deploy to production?', ok: 'Deploy'
      }
    }

    stage('Deploy Production') {
      when { branch 'main' }
      steps {
        withCredentials([
          string(credentialsId: 'oidc-aws',   variable: 'AWS_OIDC_TOKEN'),
          string(credentialsId: 'oidc-azure', variable: 'AZURE_OIDC_TOKEN')
        ]) {
          sh '''
            export AWS_ROLE_ARN="$AWS_PRODUCTION_ROLE_ARN"
            eval "$(scripts/aws-oidc-login.sh)"
            scripts/azure-oidc-login.sh
            make deploy-production
          '''
        }
      }
    }
  }

  post {
    failure {
      echo 'Pipeline failed — a security gate or deploy step returned non-zero.'
    }
  }
}
