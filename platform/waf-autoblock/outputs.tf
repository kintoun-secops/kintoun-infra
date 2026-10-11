output "function_url" {
  value = aws_lambda_function_url.autoblock.function_url
}

output "token_parameter_name" {
  value = aws_ssm_parameter.token.name
}