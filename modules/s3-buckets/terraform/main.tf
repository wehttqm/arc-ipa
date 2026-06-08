resource "aws_s3_bucket" "test_atlantis_2" {
  bucket = "test-atlantis_2-${var.environment}"
}
