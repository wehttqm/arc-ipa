import {
  to = aws_s3_bucket.magento_order_history
  id = "magento-order-history-${var.environment}"
}

import {
  to = aws_s3_bucket.switch_adapter
  id = "switch-adapter-${var.environment}"
}
