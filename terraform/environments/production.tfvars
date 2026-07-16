# Production deployment variables — non-secret. Real values set per account.
github_org             = "acaacx"
github_repo            = "sec-pipelines"
aws_region             = "eu-west-1"
azure_subscription_id  = "00000000-0000-0000-0000-000000000000"
terraform_state_bucket = "acaacx-sec-pipelines-tfstate"
terraform_lock_table   = "acaacx-sec-pipelines-tflock"
ecr_repository_prefix  = "devsecops-demo"
acr_id                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.ContainerRegistry/registries/devsecopsdemoacr"
environments           = ["production"]
