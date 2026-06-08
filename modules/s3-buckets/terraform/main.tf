resource "aws_s3_bucket" "test_atlantis" {
  bucket = "test-atlantis-${var.environment}"
}

resource "aws_s3_bucket" "test_atlantis_2" {
  bucket = "test-atlantis-2-${var.environment}"
}
