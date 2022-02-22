---
title: "Using Terraform to host a Secure Static Website with AWS S3 and Cloudfront"
date: "2021-06-25T8:00:00+03:00"
categories:
- "Terraform"
- "DevOps"
- "Amazon Web Services"
tags:
- "terraform"
- "s3"
- "cloudfront"
---

By the time you finish reading this article, you will know how to get your static websites up and running securely on AWS using Terraform. This can be a very cost-effective way of hosting a website. 

<!--more--> 

## config.tf
Terraform needs plugins called providers to interact with remote systems. 
This file acts as the main file for the Terraform configuration.

In this case, we are only dealing with AWS but Terraform can also interact with other cloud services such as Azure and Google Cloud.

```terraform
# config.tf

provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = ">= 0.14"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    encrypt = true
    region = "eu-central-1"
  }
}
```
Here we are specifying the version of Terraform that we are using as well as the version of the AWS provider. This is to ensure that any future breaking changes to Terraform or the AWS provider does not stop our scripts from working.


## vars.tf

In this file, we define the variables that we are going to use. 

```terraform
# vars.tf

variable "site_name" {
  type = string
  description = "The domain name for the website."
}

variable "bucket_name" {
  type = string
  description = "The name of the bucket without the www. prefix. Normally domain_name."
}

variable "allowed_paths" {
  type = list(string)
  default = ["*"]
  description = "List of bucket items paths can be accessed trough CloudFront."
}

variable "minimum_protocol_version" {
  type = string
  default = "TLSv1.2_2021"
  description = "Minimum version of the SSL protocol used for HTTPS connections. One of: SSLv3, TLSv1, TLSv1.1_2016, TLSv1.2_2018 , TLSv1.2_2019 and TLSv1.2_2021"
}
```

## s3.tf

In this file, we are going to set up the S3 bucket that will store our static website files. I chose to go with "no public access" in order to prevent additional costs and to keep the security at a higher level.

```terraform
# s3.tf

resource "aws_s3_bucket" "website" {
  bucket = vars.bucket_name
}

resource "aws_s3_bucket_public_access_block" "block_public_access" {
  depends_on = [aws_cloudfront_distribution.website, aws_s3_bucket_policy.resource_bucket_policy]

  bucket = aws_s3_bucket.website.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}
```
## acm.tf
Next, we need to set up our SSL certificate.
After running `terraform apply` for the first time you need to visit the [AWS ACM](https://console.aws.amazon.com/acm/home?region=us-east-1) page and finish the domain validation.

```terraform
# acm.tf

resource "aws_acm_certificate" "ssl_certificate" {
  domain_name               = "*.${var.site_name}"
  subject_alternative_names = [var.site_name]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
```

## cloudfront.tf
 Now that we have done the S3 and SSL certificate we can look at creating the Cloudfront distributions.

```terraform
# cloudfront.tf

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Identity used to allow Cloudfront access to S3"
}

data "aws_acm_certificate" "wildcard" {
  domain = "*.${var.site_name}"
  statuses = ["ISSUED"]
}

resource "aws_cloudfront_distribution" "website" {
  enabled = true
  wait_for_deployment = false
  default_root_object = "index.html"
  aliases = [ var.site_name, "www.${var.site_name}"]

  origin {
    domain_name = aws_s3_bucket.website.bucket_domain_name
    origin_id = "S3-${aws_s3_bucket.website.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods = ["GET","HEAD"]
    cached_methods =  ["GET","HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.website.id}"
    compress = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl = 0
    default_ttl = 86400
    max_ttl = 31536000
  }

  // Replace default CloudFront 403 error with 404.html
  custom_error_response {
    error_caching_min_ttl = 3600
    error_code = 403
    response_code = 403
    response_page_path = "/404.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.wildcard.arn
    ssl_support_method = "sni-only"
    minimum_protocol_version = var.minimum_protocol_version
  }
}
```

## iam.tf
  Because we are using a private bucket we need to setup cloudfront permissions for the s3 bucket.

```terraform
# iam.tf

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    actions = ["s3:GetObject"]
    effect = "Allow"
    principals {
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
      type = "AWS"
    }
    resources = [for path in var.allowed_paths: join("/", [aws_s3_bucket.website.arn, trimprefix(path,"/")])]
    sid = var.site_name
  }
}

resource "aws_s3_bucket_policy" "resource_bucket_policy" {
  bucket = aws_s3_bucket.website.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}
```

# terraform.tfvars
The tfvars file is used to specify variable values. These will need to be updated for your domain.

```terraform
# terraform.tfvars

domain_name = "example.com"
bucket_name = "example.com"

```

