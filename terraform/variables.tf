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

// OIDC setup
variable "provider_url" {
  description = "URL of the OIDC Provider. Use provider_urls to specify several URLs."
  type        = string
  default     = "https://token.actions.githubusercontent.com"
}

variable "max_session_duration" {
  description = "Maximum CLI/API session duration in seconds between 3600 and 43200"
  type        = number
  default     = 3600
}

variable "oidc_fully_qualified_subjects" {
  description = "The fully qualified OIDC subjects to be added to the role policy"
  type        = set(string)
  default     = ["repo:ubogdan/ubogdan.github.io:ref:refs/heads/website"]
}

variable "oidc_subjects_with_wildcards" {
  description = "The OIDC subject using wildcards to be added to the role policy"
  type        = set(string)
  default     = []
}

variable "oidc_fully_qualified_audiences" {
  description = "The audience to be added to the role policy. Set to sts.amazonaws.com for cross-account assumable role. Leave empty otherwise."
  type        = set(string)
  default     = ["sts.amazonaws.com"]
}

