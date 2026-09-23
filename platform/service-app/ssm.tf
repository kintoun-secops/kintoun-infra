# =======================================================
# 현재 릴리스 기록
# =======================================================
resource "aws_ssm_parameter" "current_release" {
  for_each = local.release_parameters

  name  = each.value
  type  = "String"
  value = "bootstrap"

  tags = {
    Name      = "${var.project_name}-service-${each.key}-current-release"
    ManagedBy = "Terraform"
  }

  lifecycle {
    ignore_changes = [value]
  }
}

# =======================================================
# 배포 전용 SSM 문서
# =======================================================
resource "aws_ssm_document" "deploy" {
  name            = "${var.project_name}-service-deploy"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Pull and activate a release by commit SHA"
    parameters = {
      sha = {
        type           = "String"
        description    = "Commit SHA of the release to activate"
        allowedPattern = "^[0-9a-f]{40}$"
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "deploy"
      inputs = {
        runCommand = ["/opt/deploy/pull.sh {{ sha }}"]
      }
    }]
  })

  tags = {
    Name      = "${var.project_name}-service-deploy"
    ManagedBy = "Terraform"
  }
}
