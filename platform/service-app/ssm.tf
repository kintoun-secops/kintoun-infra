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
