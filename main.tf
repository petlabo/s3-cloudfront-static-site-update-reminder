# ==============================================================================
# Web Check Alert Discord - Infrastructure Configuration (Terraform)
# ==============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region
}

# ------------------------------------------------------------------------------
# SNS (Simple Notification Service)
# アラート通知を集約し、各プロトコル（Lambda, Email等）へ配信するためのハブ。
# ------------------------------------------------------------------------------
resource "aws_sns_topic" "discord_alerts" {
  name = var.sns_topic_name
}

# SNSトピックに対するパブリッシュ権限をLambdaサービスに付与するアクセスポリシー
resource "aws_sns_topic_policy" "default" {
  arn = aws_sns_topic.discord_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowLambdaPublish"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.discord_alerts.arn
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# S3 (Simple Storage Service)
# 状態管理（ハッシュ値保存）用バケットおよび、監視対象（製品用）バケットの設定。
# ------------------------------------------------------------------------------

# 監視システムの内部状態（前回取得したWebコンテンツのハッシュ値）を保持するバケット
resource "aws_s3_bucket" "monitor_state_bucket" {
  bucket        = var.monitor_state_bucket_name
  force_destroy = true
}

# 監視対象となる既存のS3バケット。デプロイイベントを検知するために参照
data "aws_s3_bucket" "product_bucket" {
  bucket = var.product_bucket_name
}

# 製品用バケットに特定のファイル（index.html）が作成・更新された際にLambdaをトリガー
resource "aws_s3_bucket_notification" "product_bucket_notification" {
  bucket = data.aws_s3_bucket.product_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.schedule_creator.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = "index.html"
  }

  depends_on = [aws_lambda_permission.allow_s3_to_call_creator]
}

# ------------------------------------------------------------------------------
# Lambda: Schedule Creator
# S3デプロイイベントをフックし、直後の即時実行および短期間のポーリングスケジュールを動的に作成。
# ------------------------------------------------------------------------------
data "archive_file" "schedule_creator_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/schedule_creator.py"
  output_path = "${path.module}/schedule_creator.zip"
}

resource "aws_lambda_function" "schedule_creator" {
  filename      = data.archive_file.schedule_creator_zip.output_path
  function_name = var.lambda_schedule_creator_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "schedule_creator.lambda_handler"
  runtime       = "python3.9"

  environment {
    variables = {
      TARGET_LAMBDA_ARN    = aws_lambda_function.web_checker.arn
      SCHEDULER_ROLE_ARN   = aws_iam_role.scheduler_role.arn
      SNS_TOPIC_ARN        = aws_sns_topic.discord_alerts.arn
      WEB_URL              = var.web_url
      SCHEDULE_NAME_PREFIX = var.schedule_name_prefix
    }
  }
}

# S3サービスからSchedule Creator Lambdaを呼び出すための権限設定
resource "aws_lambda_permission" "allow_s3_to_call_creator" {
  statement_id  = "AllowExecutionFromProductS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.schedule_creator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.product_bucket_name}"
}

# ------------------------------------------------------------------------------
# Lambda: Web Checker
# Webサイトのコンテンツを取得し、S3に保存された前回のハッシュ値と比較して更新を判定。
# ------------------------------------------------------------------------------
data "archive_file" "web_checker_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/web_checker.py"
  output_path = "${path.module}/web_checker.zip"
}

resource "aws_lambda_function" "web_checker" {
  filename      = data.archive_file.web_checker_zip.output_path
  function_name = var.lambda_web_checker_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "web_checker.lambda_handler"
  runtime       = "python3.9"
  timeout       = 30

  environment {
    variables = {
      SITE_NAME       = var.web_site_name
      WEB_URL         = var.web_url
      S3_BUCKET_NAME  = aws_s3_bucket.monitor_state_bucket.id
      SNS_TOPIC_ARN   = aws_sns_topic.discord_alerts.arn
    }
  }
}

# EventBridge SchedulerサービスからWeb Checker Lambdaを呼び出すための権限設定
resource "aws_lambda_permission" "allow_scheduler_to_call_checker" {
  statement_id  = "AllowExecutionFromScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.web_checker.function_name
  principal     = "scheduler.amazonaws.com"
}

# ------------------------------------------------------------------------------
# Lambda: Discord Notifier
# SNSトピックからメッセージを受信し、外部のDiscord Webhook APIを呼び出す。
# ------------------------------------------------------------------------------
data "archive_file" "discord_notifier_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/discord_notifier.py"
  output_path = "${path.module}/discord_notifier.zip"
}

resource "aws_lambda_function" "discord_notifier" {
  filename      = data.archive_file.discord_notifier_zip.output_path
  function_name = var.lambda_discord_notifier_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "discord_notifier.lambda_handler"
  runtime       = "python3.9"

  environment {
    variables = {
      DISCORD_WEBHOOK_URL = var.discord_webhook_url
    }
  }
}

# SNSトピックへのサブスクリプション設定（プロトコル：Lambda）
resource "aws_sns_topic_subscription" "discord_sns_sub" {
  topic_arn = aws_sns_topic.discord_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_notifier.arn
}

# SNSサービスからDiscord Notifier Lambdaを呼び出すための権限設定
resource "aws_lambda_permission" "with_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.discord_alerts.arn
}

# ------------------------------------------------------------------------------
# IAM Roles & Policies
# ------------------------------------------------------------------------------

# 各Lambda関数に付与する共通実行ロール
resource "aws_iam_role" "lambda_role" {
  name = var.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Lambda実行に必要なログ出力、S3アクセス、SNSパブリッシュ、スケジューラ操作等の権限
resource "aws_iam_role_policy" "lambda_policy" {
  name = var.iam_policy_name
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowLogging"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid      = "AllowS3Access"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Effect   = "Allow"
        Resource = [
          "arn:aws:s3:::${var.monitor_state_bucket_name}",
          "arn:aws:s3:::${var.monitor_state_bucket_name}/*",
          "arn:aws:s3:::${var.product_bucket_name}",
          "arn:aws:s3:::${var.product_bucket_name}/*"
        ]
      },
      {
        Sid      = "AllowSNSPublish"
        Action   = "sns:Publish"
        Effect   = "Allow"
        Resource = aws_sns_topic.discord_alerts.arn
      },
      {
        Sid      = "AllowLambdaInvoke"
        Action   = "lambda:InvokeFunction"
        Effect   = "Allow"
        Resource = aws_lambda_function.web_checker.arn
      },
      {
        Sid      = "AllowSchedulerCreation"
        Action   = ["scheduler:CreateSchedule"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Sid      = "AllowPassRole"
        Action   = "iam:PassRole"
        Effect   = "Allow"
        Resource = aws_iam_role.scheduler_role.arn
      }
    ]
  })
}

# EventBridge SchedulerがLambda関数を実行する際に使用する信頼ロール
resource "aws_iam_role" "scheduler_role" {
  name = var.scheduler_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

# Schedulerが特定のターゲット（Web Checker）を起動するための権限
resource "aws_iam_role_policy" "scheduler_policy" {
  name = "web-check-scheduler-policy"
  role = aws_iam_role.scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "lambda:InvokeFunction"
      Effect   = "Allow"
      Resource = aws_lambda_function.web_checker.arn
    }]
  })
}
