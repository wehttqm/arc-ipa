resource "aws_s3_bucket" "agent_source" {
  bucket_prefix = "${var.stack_name}-source-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "agent_source" {
  bucket                  = aws_s3_bucket.agent_source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "agent_source" {
  type        = "zip"
  source_dir  = "${path.module}/agent-code"
  output_path = "${path.module}/.terraform/agent-code.zip"
}

resource "aws_s3_object" "agent_source" {
  bucket = aws_s3_bucket.agent_source.id
  key    = "agent-code-${data.archive_file.agent_source.output_md5}.zip"
  source = data.archive_file.agent_source.output_path
  etag   = data.archive_file.agent_source.output_md5
}
