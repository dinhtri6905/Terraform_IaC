terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.34.0"
    }
  }
}

provider "aws" {
  // đã dùng aws CLI để config profile để ẩn access & secret, nên provider có thể tự động lấy thông tin từ ~/.aws/credentials(security)
  # region = "ap-southeast-1"
}