resource "aws_lambda_function" "this" {
  function_name = "ecomm-switch-retail-adapter-function"
  handler       = "index.handler"
  role          = "arn:aws:iam::${var.account_id}:role/ecomm_lambda_role"
  runtime       = "nodejs20.x"
  s3_bucket     = var.s3_bucket
  s3_key        = "lambda.zip"
  timeout       = 900

  lifecycle {
    ignore_changes = [last_modified]
  }
}

resource "aws_lambda_function_url" "this" {
  authorization_type = "NONE"
  function_name      = aws_lambda_function.this.function_name
}
