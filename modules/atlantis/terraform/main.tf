# Atlantis Infrastructure for EKS - Helm Deployment

data "terraform_remote_state" "eks" {
  backend   = "s3"
  workspace = terraform.workspace

  config = {
    bucket               = var.backend_bucket
    key                  = "eks/terraform.tfstate"
    workspace_key_prefix = "eks"
    region               = var.region
  }
}

data "terraform_remote_state" "vpc" {
  backend   = "s3"
  workspace = terraform.workspace

  config = {
    bucket               = var.backend_bucket
    key                  = "vpc/terraform.tfstate"
    workspace_key_prefix = "vpc"
    region               = var.region
  }
}

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "cluster" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

# ==============================================================================
# AWS SECRETS MANAGER - GitHub Credentials
# ==============================================================================

data "aws_secretsmanager_secret" "github_app_private_key" {
  name = var.github_app_private_key_asm_name
}

data "aws_secretsmanager_secret_version" "github_app_private_key" {
  secret_id = data.aws_secretsmanager_secret.github_app_private_key.id
}

data "aws_secretsmanager_secret" "github_webhook_secret" {
  name = var.github_webhook_secret_asm_name
}

data "aws_secretsmanager_secret_version" "github_webhook_secret" {
  secret_id = data.aws_secretsmanager_secret.github_webhook_secret.id
}

# ==============================================================================
# IAM - IRSA
# ==============================================================================

module "atlantis_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-atlantis-irsa"

  role_policy_arns = {
    atlantis = aws_iam_policy.atlantis_policy.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.eks.outputs.eks_oidc_provider_arn
      namespace_service_accounts = ["atlantis:atlantis"]
    }
  }
}

resource "aws_iam_policy" "atlantis_policy" {
  name        = "${var.cluster_name}-atlantis-policy"
  description = "Policy for Atlantis to manage Terraform-controlled AWS resources"

  policy = templatefile("${path.module}/iam-policy.json", {
    backend_bucket = var.backend_bucket
    region         = var.region
    account_id     = data.aws_caller_identity.current.account_id
    cluster_name   = var.cluster_name
  })
}

# ==============================================================================
# SECURITY GROUPS
# ==============================================================================

resource "aws_security_group" "atlantis_alb" {
  name        = "${var.cluster_name}-atlantis-alb-sg"
  description = "Security group for Atlantis ALB"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description = "HTTPS from allowed IPs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_ip_cidrs
  }

  ingress {
    description = "HTTP from allowed IPs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_ip_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "alb_to_nodes" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.atlantis_alb.id
  security_group_id        = data.terraform_remote_state.eks.outputs.node_security_group_id
  description              = "Allow Atlantis ALB to reach nodes/pods"
}

resource "aws_security_group_rule" "alb_to_cluster_primary_sg" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.atlantis_alb.id
  security_group_id        = data.terraform_remote_state.eks.outputs.cluster_primary_sg_id
  description              = "Allow Atlantis ALB to reach pods via cluster primary SG"
}

# ==============================================================================
# KUBERNETES
# ==============================================================================

resource "kubernetes_namespace" "atlantis" {
  metadata {
    name = "atlantis"
  }
}

resource "kubernetes_config_map" "atlantis_repos_config" {
  metadata {
    name      = "atlantis-repos-config"
    namespace = kubernetes_namespace.atlantis.metadata[0].name
  }

  data = {
    "repos.yaml" = file("${path.module}/files/repos.yaml")
  }
}

# ==============================================================================
# HELM RELEASE
# ==============================================================================

resource "helm_release" "atlantis" {
  name       = "atlantis"
  repository = "https://runatlantis.github.io/helm-charts"
  chart      = "atlantis"
  version    = var.atlantis_chart_version
  namespace  = kubernetes_namespace.atlantis.metadata[0].name

  wait            = true
  timeout         = 600
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      fullnameOverride = "atlantis"
      replicaCount     = 1

      serviceAccount = {
        create = true
        name   = "atlantis"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.atlantis_irsa_role.iam_role_arn
        }
      }

      orgAllowlist     = var.repo_allowlist
      atlantisUrl      = "https://${var.atlantis_domain}"
      defaultTFVersion = var.terraform_version
      logLevel         = "info"

      enableDiffMarkdownFormat = true
      hidePrevPlanComments     = true

      githubApp = {
        id             = var.github_app_id
        installationId = var.github_app_installation_id
        key            = local.github_app_key
        secret         = local.github_webhook_secret
      }

      environment = {
        AWS_REGION                                     = var.region
        ATLANTIS_PARALLEL_PLAN                         = "true"
        ATLANTIS_PARALLEL_APPLY                        = "false"
        TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE = "true"
        ATLANTIS_GH_ALLOW_MERGEABLE_BYPASS_APPLY       = "true"

        # Do NOT report a green commit status when a command matched zero
        # projects. Without this, a PR that touches no discovered project gets
        # `atlantis/plan|apply|policy_check — 0/0 ... successfully` (success),
        # which satisfies the *required* branch-protection checks and lets the
        # PR merge before any terraform runs. With this set, Atlantis withholds
        # the status so the required checks stay unsatisfied and the merge is
        # blocked until a real plan/apply reports. (runatlantis #1547/#1924)
        ATLANTIS_SILENCE_VCS_STATUS_NO_PROJECTS = "true"
      }

      resources = {
        requests = { memory = "512Mi", cpu = "250m" }
        limits   = { memory = "2Gi", cpu = "1000m" }
      }

      volumeClaim = {
        enabled     = true
        dataStorage = "10Gi"
      }

      ingress = {
        enabled          = true
        ingressClassName = "alb"
        path             = "/"
        pathType         = "Prefix"
        annotations = merge(
          {
            "alb.ingress.kubernetes.io/scheme"           = var.alb_scheme
            "alb.ingress.kubernetes.io/target-type"      = "ip"
            "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
            "alb.ingress.kubernetes.io/security-groups"  = aws_security_group.atlantis_alb.id
            "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
            "alb.ingress.kubernetes.io/certificate-arn"  = var.acm_certificate_arn
            "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
          }
        )
        hosts = [{
          host  = var.atlantis_domain
          paths = ["/"]
        }]
      }

      statefulSet = {
        securityContext = {
          fsGroup             = 1000
          runAsUser           = 100
          fsGroupChangePolicy = "OnRootMismatch"
        }
      }

      containerSecurityContext = {
        allowPrivilegeEscalation = false
        readOnlyRootFilesystem   = false
      }

      repoConfig = ""

      extraArgs = ["--repo-config=/etc/atlantis-config/repos.yaml"]

      service = { type = "ClusterIP", port = 4141, targetPort = 4141 }

      extraVolumes = [{
        name = "atlantis-repos-config"
        configMap = {
          name        = kubernetes_config_map.atlantis_repos_config.metadata[0].name
          defaultMode = 420
        }
      }]

      extraVolumeMounts = [{
        name      = "atlantis-repos-config"
        mountPath = "/etc/atlantis-config"
        readOnly  = true
      }]

      livenessProbe = {
        enabled             = true
        initialDelaySeconds = 30
        periodSeconds       = 60
      }

      readinessProbe = {
        enabled             = true
        initialDelaySeconds = 15
        periodSeconds       = 10
      }
    })
  ]

  depends_on = [
    module.atlantis_irsa_role,
    aws_iam_policy.atlantis_policy,
    aws_security_group.atlantis_alb
  ]
}

# ==============================================================================
# OUTPUTS
# ==============================================================================

output "service_account_arn" {
  value = module.atlantis_irsa_role.iam_role_arn
}

output "atlantis_url" {
  value = "https://${var.atlantis_domain}"
}
