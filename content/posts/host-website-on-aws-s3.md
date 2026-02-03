---
title: "Using Terraform to host a Static Website on AWS S3"
date: 2021-06-23T18:25:44+03:00
lastmod: 2026-02-03
description: "By the time you finish reading this article, you will know how to get your static websites up and running using AWS S3."
categories:
  - "Terraform"
  - "DevOps"
  - "Amazon Web Services"
tags:
  - "terraform"
  - "aws"
---

By the time you finish reading this article, you will know how to get your static websites up and running using AWS S3.

<!--more-->

## Static Hosting Options: Why AWS S3?

There are many alternatives for hosting static websites, each with different trade-offs:

- **Traditional web hosting** - Simple but limited scalability and often require SSH access management
- **GitHub Pages** - Free but limited customization and tied to a specific Git workflow
- **Netlify/Vercel** - Great DX but vendor lock-in and potential costs at scale
- **AWS S3 + CloudFront** - Highly scalable, cost-effective, and offers a generous free tier

**AWS S3 is an excellent choice** because it provides automatic scaling, low latency through CloudFront CDN integration, and most importantly, **it can be completely free** if you stay within the AWS Free Tier limits (12 months of free access with certain conditions). For small to medium-sized projects, you might never pay anything.

This guide uses Terraform to define infrastructure as code, making your hosting configuration reproducible, versionable, and easy to maintain.

## Infrastructure as Code Best Practices

Before we dive into the configuration, here are important Terraform best practices we'll follow:

1. **Separate concerns** - Use multiple `.tf` files for different resources (config, variables, S3, IAM)
2. **Use variables** - Avoid hardcoding values; use `variables.tf` for all configurable parameters
3. **State management** - Store Terraform state in S3 with encryption enabled
4. **Proper versioning** - Specify provider versions to ensure reproducible deployments
5. **Documentation** - Add descriptions to all variables and resources

## Configuration Structure

We'll organize our Terraform code into logical files: `config.tf` for provider configuration, `var.tf` for input variables, `s3.tf` for bucket resources, and `iam.tf` for access policies.

## config.tf

Terraform needs plugins called providers to interact with remote systems. This file acts as the main configuration file for Terraform.

In this case, we are dealing with AWS, but Terraform can also interact with other cloud services such as Azure and Google Cloud. Notice how we specify the AWS provider version (`~> 5.0`) - this ensures compatibility and prevents unexpected breaking changes in future updates.

```terraform
# config.tf

provider "aws" {
  region = "eu-central-1"
}

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    encrypt = true
    region  = "eu-central-1"
  }
}
```

## var.tf

In this file, we define the variables that we are going to use. Using variables makes our configuration reusable and flexible. You can override these values without modifying the code.

```terraform
# var.tf

variable "site_name" {
  type        = string
  description = "The domain name for the website."
}

variable "allowed_paths" {
  type        = list(string)
  default     = ["*"]
  description = "List of bucket items paths that can be accessed through CloudFront."
}
```

## s3.tf

To use a bucket as a website, we need to configure the bucket name as the domain name and set the bucket ACL appropriately. Note that we're using `"public-read"` here, but in production, consider using `"private"` with CloudFront as the only public access point for better security.

```terraform
# s3.tf

resource "aws_s3_bucket" "website" {
  bucket = var.site_name

  website {
    index_document = "index.html"
    # error_document = "404.html"
  }

  tags = {
    Name        = var.site_name
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_acl" "website" {
  bucket = aws_s3_bucket.website.id
  acl    = "public-read"
}
```

## iam.tf

The following configuration allows public access to the S3 bucket. This IAM policy explicitly defines who (principals) can perform what actions (s3:GetObject) on which resources.

```terraform
# iam.tf

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    actions = ["s3:GetObject"]
    effect  = "Allow"
    
    principals {
      identifiers = ["*"]
      type        = "AWS"
    }
    
    resources = [for path in var.allowed_paths : join("/", [aws_s3_bucket.website.arn, trimprefix(path, "/")])]
    sid       = var.site_name
  }
}

resource "aws_s3_bucket_policy" "resource_bucket_policy" {
  bucket = aws_s3_bucket.website.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}
```

## terraform.tfvars

Finally, we specify the values for our variables. The `terraform.tfvars` file should be in your `.gitignore` if it contains sensitive data, but in this case it's safe to commit since it only contains the domain name.

```terraform
# terraform.tfvars

site_name = "blog.example.com"
```

## Deploying Your Infrastructure

Once you have all files in place, run:

```bash
terraform init      # Initialize Terraform and download providers
terraform plan      # Preview changes before applying
terraform apply     # Create resources in AWS
```

Your static website is now live on S3! Next, consider adding CloudFront for HTTPS, better performance, and global distribution.

## Best Practices Summary

- Always use `terraform plan` before `terraform apply`
- Store state files securely with encryption
- Use version constraints for all providers
- Tag all resources for better cost tracking and organization
- Keep `terraform.tfvars` in `.gitignore` for sensitive values
- Consider using `terraform fmt` to maintain consistent code style
- Use remote state management for team collaboration
