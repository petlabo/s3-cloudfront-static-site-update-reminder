variable "region" {
  description = "AWSリソースをデプロイする対象リージョン（デフォルトは東京リージョン）。"
  type        = string
  default     = "ap-northeast-1"
}

# --- 監視対象のインフラ設定 ---
variable "web_site_name" {
  description = "通知メッセージに使用するWebサイトの表示名。"
  type        = string
  default     = "対象Webサイト"
}

variable "web_url" {
  description = "更新監視を行う対象のWebサイトURL。プロトコル（http/https）を含めて指定。"
  type        = string
}

variable "product_bucket_name" {
  description = "監視のトリガーとなる既存の製品用S3バケット名。このバケットへのオブジェクト追加を検知します。"
  type        = string
}

# --- 監視システム管理用設定 ---
variable "monitor_state_bucket_name" {
  description = "監視システムが内部状態（ハッシュ値等）を保持するために使用する専用S3バケット名。"
  type        = string
  default     = "web-check-monitor-state-bucket"
}

variable "discord_webhook_url" {
  description = "通知の送信先となるDiscord Webhook URL。機密情報として扱われます。"
  type        = string
  sensitive   = true
}

# --- 動的スケジューラの設定 ---
variable "lambda_schedule_creator_name" {
  description = "S3イベントをトリガーに動的スケジュールを生成するLambda関数名。"
  type        = string
  default     = "web-check-schedule-creator"
}

variable "scheduler_role_name" {
  description = "Amazon EventBridge SchedulerがLambdaを起動する際に使用するIAMロール名。"
  type        = string
  default     = "web-check-scheduler-role"
}

variable "schedule_name_prefix" {
  description = "動的に生成されるスケジュールの識別用プレフィックス。"
  type        = string
  default     = "WebCheck-Dynamic-"
}

# --- 各リソースの識別名設定 ---
variable "sns_topic_name" {
  description = "アラート通知を集約するためのSNSトピック名。"
  type        = string
  default     = "web-check-alerts-topic"
}

variable "lambda_discord_notifier_name" {
  description = "SNSメッセージを受け取り、Discordへ転送するLambda関数名。"
  type        = string
  default     = "discord_notifier"
}

variable "lambda_web_checker_name" {
  description = "実際にWebサイトのコンテンツを取得・比較するLambda関数名。"
  type        = string
  default     = "web_checker"
}

variable "iam_role_name" {
  description = "Lambda関数群に付与する共通IAMロール名。"
  type        = string
  default     = "web_check_lambda_role"
}

variable "iam_policy_name" {
  description = "Lambda用IAMロールにアタッチするインラインポリシー名。"
  type        = string
  default     = "web_check_lambda_policy"
}
