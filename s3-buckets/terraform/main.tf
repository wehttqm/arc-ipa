resource "aws_s3_bucket" "magento_order_history" {
  bucket = "magento-order-history-${var.environment}"
}

resource "aws_s3_bucket" "switch_adapter" {
  bucket = "switch-adapter-${var.environment}"
}

resource "aws_s3_bucket" "test_atlantis" {
  bucket = "test-atlantis-${var.environment}"
}
