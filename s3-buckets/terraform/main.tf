resource "aws_s3_bucket" "test_atlantis" {
  bucket = "test-atlantis-${var.environment}"
}
