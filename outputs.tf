output "sns_topic_arn" {
  value = aws_sns_topic.discord_alerts.arn
  description = "Web監視アラート用のSNSトピックARN"
}

output "monitor_state_bucket_id" {
  value = aws_s3_bucket.monitor_state_bucket.id
  description = "監視状態（ハッシュ値）を保存するS3バケット名"
}

output "lambda_schedule_creator_arn" {
  value = aws_lambda_function.schedule_creator.arn
  description = "動的スケジューラ作成LambdaのARN"
}

output "lambda_web_checker_arn" {
  value = aws_lambda_function.web_checker.arn
  description = "WebチェッカーLambdaのARN"
}
