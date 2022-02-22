output "secret_name" {
  value = aws_iam_access_key.access_key.id
}

output "secret_access_key" {
  sensitive = true
  value = aws_iam_access_key.access_key.secret
}