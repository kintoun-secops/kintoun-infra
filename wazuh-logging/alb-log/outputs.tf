output "alb_logs_bucket_name" {
  description = "ALB 로그 저장과 Wazuh 수집에 사용할 S3 버킷 이름"
  value       = aws_s3_bucket.alb_logs.id
}