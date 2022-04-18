variable "site_name" {
  type        = string
  default     = "ubogdan.com"
  description = "The domain name for the website."
}

variable "custom_orgin_headers" {
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "minimum_protocol_version" {
  type        = string
  default     = "TLSv1.2_2021"
  description = "Minimum version of the SSL protocol used for HTTPS connections. One of: SSLv3, TLSv1, TLSv1.1_2016, TLSv1.2_2018 , TLSv1.2_2019 and TLSv1.2_2021"
}

data "aws_acm_certificate" "wildcard" {
  domain   = "*.ubogdan.com"
  statuses = ["ISSUED"]
}

