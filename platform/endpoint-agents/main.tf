# 내려받는 패키지의 SHA256. 버전을 올리면 여기에 항목을 더해야 한다 — 없는 버전은 plan 에서 실패한다.
# 값은 공개 배포 파일에서 계산한다: curl -sfL <url> | sha256sum
locals {
  wazuh_sha256 = {
    "4.14.8-1" = {
      deb_amd64   = "6ed202e211fd8c544d1906c9b94dcd4b503d1829eef7d0a82ce4bcf4a1688967"
      deb_arm64   = "33028279fde10e008ed92dd228c2b42ab5aa84f28705f80b76ce867b48e48bad"
      rpm_x86_64  = "b4195adae68eefa70da9395f324201ed642c5db178a2ec8c968e61fe9c127d8f"
      rpm_aarch64 = "eb12b629c6b15246f5cceffe2fb7f1d38c97a26f05cd7c3083a345fff1b9f1ac"
    }
  }

  velociraptor_sha256 = {
    "0.77.2" = {
      amd64 = "6c4c23c466d892788ff56ddcd3a31f844e4c0d797ade454c5e2625eb9e427077"
      arm64 = "54d36c23f374a572a4a60106d896e0e39bc6fcafd0d6150cf56aec6c49454ea0"
    }
  }

  wazuh        = local.wazuh_sha256[var.wazuh_agent_version]
  velociraptor = local.velociraptor_sha256[var.velociraptor_version]

  install_script = templatefile("${path.module}/files/agents-install.sh.tftpl", {
    velociraptor_base_url      = var.velociraptor_base_url
    velociraptor_client_config = trimspace(file("${path.module}/files/velociraptor-client.config.yaml"))
    velociraptor_sha256_amd64  = local.velociraptor.amd64
    velociraptor_sha256_arm64  = local.velociraptor.arm64
    velociraptor_version       = var.velociraptor_version
    wazuh_agent_group          = var.wazuh_agent_group
    wazuh_agent_version        = var.wazuh_agent_version
    wazuh_base_url             = var.wazuh_base_url
    wazuh_manager              = var.wazuh_manager
    wazuh_sha256_deb_amd64     = local.wazuh.deb_amd64
    wazuh_sha256_deb_arm64     = local.wazuh.deb_arm64
    wazuh_sha256_rpm_aarch64   = local.wazuh.rpm_aarch64
    wazuh_sha256_rpm_x86_64    = local.wazuh.rpm_x86_64
  })
}

# =======================================================
# 에이전트 설치 SSM 문서
# =======================================================
# 문서 본문 한도는 64KB 다. 스크립트가 그 안에 들어가므로 S3 를 거치지 않는다.
resource "aws_ssm_document" "endpoint_agents" {
  name            = "${var.project_name}-endpoint-agents"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install Wazuh agent and Velociraptor client, matching the host distribution"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "installEndpointAgents"
      inputs = {
        runCommand       = split("\n", trimspace(local.install_script))
        timeoutSeconds   = "900"
        workingDirectory = "/tmp"
      }
    }]
  })

  tags = {
    Name      = "${var.project_name}-endpoint-agents"
    ManagedBy = "Terraform"
  }
}

# =======================================================
# State Manager 연결
# =======================================================
# 태그로 대상을 고르므로 나중에 같은 태그로 만든 인스턴스도 자동으로 포함된다.
# 스크립트가 설치 상태를 먼저 확인하기 때문에 주기적 재실행은 에이전트 이탈만 되돌린다.
resource "aws_ssm_association" "endpoint_agents" {
  name                = aws_ssm_document.endpoint_agents.name
  association_name    = "${var.project_name}-endpoint-agents"
  schedule_expression = var.association_schedule

  # 한 대씩 돌려 패키지 저장소에 동시 요청을 보내지 않는다.
  # 한 대가 실패해도 남은 대상은 계속 설치한다 (실패는 연결 실행 이력에 남는다).
  max_concurrency = "1"
  max_errors      = "100%"

  targets {
    key    = "tag:${var.target_tag_key}"
    values = [var.target_tag_value]
  }
}
