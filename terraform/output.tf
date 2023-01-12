output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.website.id
}

output "assume_role_arn" {
  value = aws_iam_role.pipeline.arn
}

output "bucket_name" {
  value = aws_s3_bucket.website.bucket
}