output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "lock_table" {
  value = aws_dynamodb_table.lock.name
}

output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}

output "terraform_apply_role_arn" {
  value = aws_iam_role.terraform_apply.arn
}

output "terraform_plan_role_arn" {
  value = aws_iam_role.terraform_plan.arn
}
