output "webhook_url" {
  value = "${aws_api_gateway_stage.webhook.invoke_url}/webhook"
}

output "sessions_table_name" {
  value = aws_dynamodb_table.sessions.name
}

output "lambda_function_arn" {
  value = aws_lambda_function.webhook.arn
}
