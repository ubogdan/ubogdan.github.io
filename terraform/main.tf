provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = ">= 0.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    encrypt = true
    region  = "eu-central-1"
    bucket  = "ubogdan-terraform-state"
    key     = "website"
  }
}

resource "aws_s3_bucket" "website" {
  bucket = var.site_name
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Identity used to allow Cloudfront access to S3"
}

data "aws_cloudfront_cache_policy" "cache_policy" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "request_policy" {
  name = "Managed-CORS-S3Origin"
}

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  wait_for_deployment = false
  default_root_object = "index.html"
  aliases             = [var.site_name, "www.${var.site_name}"]

  origin {
    domain_name = aws_s3_bucket.website.bucket_domain_name
    origin_id   = "S3-${aws_s3_bucket.website.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }

    dynamic "custom_header" {
      for_each = [for h in var.custom_orgin_headers : h]
      content {
        name  = custom_header.value.name
        value = custom_header.value.value
      }
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.website.id}"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    // Request rewrite
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.cloudfront_viewer_request.arn
    }

    // Add custom headers to response
    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.cloudfront_viewer_response.arn
    }

    cache_policy_id          = data.aws_cloudfront_cache_policy.cache_policy.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.request_policy.id
  }

  custom_error_response {
    error_caching_min_ttl = 86400
    error_code            = 403
    response_code         = 403
    response_page_path    = "/403.html"
  }

  custom_error_response {
    error_caching_min_ttl = 86400
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["RU", "BY"]
    }
  }


  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.wildcard.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = var.minimum_protocol_version
  }

}

resource "aws_cloudfront_function" "cloudfront_viewer_request" {
  name    = replace("${var.site_name}_viewer_request", ".", "_")
  runtime = "cloudfront-js-1.0"
  comment = "Rewrite request headers"
  publish = true
  code    = file("viewer_request.js")
}

resource "aws_cloudfront_function" "cloudfront_viewer_response" {
  name    = replace("${var.site_name}_viewer_response", ".", "_")
  runtime = "cloudfront-js-1.0"
  comment = "Add security headers to viewer response"
  publish = true
  code    = file("viewer_response.js")
}

resource "aws_s3_bucket_public_access_block" "block_public_access" {
  depends_on = [aws_cloudfront_distribution.website, aws_s3_bucket_policy.resource_bucket_policy]

  bucket                  = aws_s3_bucket.website.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject"
    ]

    effect = "Allow"
    principals {
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
      type        = "AWS"
    }

    resources = [
      aws_s3_bucket.website.arn,
      "${aws_s3_bucket.website.arn}/*"
    ]

    sid = var.site_name
  }
}

resource "aws_s3_bucket_policy" "resource_bucket_policy" {
  bucket = aws_s3_bucket.website.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}

resource "aws_iam_user" "pipeline" {
  name = "github-actions-ubogdan.com-pipeline"
}

data "aws_iam_policy_document" "bucket" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    effect    = "Allow"
    resources = [aws_s3_bucket.website.arn, "${aws_s3_bucket.website.arn}/*"]
  }
}

resource "aws_iam_user_policy" "bucket_policy" {
  name   = "PipelineBucketAccess"
  user   = aws_iam_user.pipeline.name
  policy = data.aws_iam_policy_document.bucket.json
}

data "aws_iam_policy_document" "cloudfront" {
  statement {
    actions = [
      "cloudfront:CreateInvalidation",
    ]

    effect    = "Allow"
    resources = [aws_cloudfront_distribution.website.arn]
  }
}

resource "aws_iam_user_policy" "cloudfront_policy" {
  name   = "PipelineCloudFrontAccess"
  user   = aws_iam_user.pipeline.name
  policy = data.aws_iam_policy_document.cloudfront.json
}

resource "aws_iam_access_key" "access_key" {
  user = aws_iam_user.pipeline.name
}