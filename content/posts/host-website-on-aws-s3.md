---
title: "Using Terraform to host a Static Website on AWS S3"
description: ""
date: "2021-06-23T18:25:44+03:00"
thumbnail: ""
categories:
- "Terraform"
- "DevOps"
- "Amazon Web Services"
tags:
- "terraform"
- "aws"
widgets:
- "categories"
- "taglist"
---

By the time you finish reading this article, you will know how to get your static websites up and running using AWS S3.

<!--more--> 

## config.tf
Terraform needs plugins called providers to interact with remote systems.
This file acts as the main file for the Terraform configuration.

In this case, we are only dealing with AWS but Terraform can also interact with other cloud services such as Azure and Google Cloud.

```terraform
# config.tf

provider "aws" {
  region = "eu-central-1"
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

## vars.tf
In this file, we define the variables that we are going to use.

```terraform
# vars.tf

variable "site_name" {
  type = string
  description = "The domain name for the website."
}

variable "allowed_paths" {
  type = list(string)
  default = ["*"]
  description = "List of bucket items paths can be accessed trough CloudFront."
}
```

## s3.tf
 In order to use a bucket as a website we need to configure the bucket name as the domain name and to set the bucket acl to "public-read".

```terraform
# s3.tf

resource "aws_s3_bucket" "website" {
  bucket = var.site_name
  acl    = "public-read"

  website {
    index_document = "index.html"
    //error_document = "404.hml"
  }

}
```

## iam.tf
  The following configuration allows public access to S3 bucket.

```terraform
# iam.tf

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    actions = ["s3:GetObject"]
    effect = "Allow"
    principals {
      identifiers = ["*"]
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

## terraform.tfvars
  Finally, we neet to chose a fqdn name for our website.

```terraform
# terraform.tfvars

site_name = "blog.example.com"
```