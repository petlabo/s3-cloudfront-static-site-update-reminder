# Web Check & Alert Discord Notifier (IaC)

このプロジェクトは、S3の更新通知および定期的なWebサイトの死活・更新チェックを行い、Discordへ通知するAWSインフラをTerraformで構築します。

## 構成概要

1.  **S3更新通知**: GitHub Actions等によりS3バケットが更新されると、SNS経由でDiscordへ通知されます。
2.  **定期Webチェック**:
    *   5分ごとにEventBridgeがLambda(`web_checker`)を起動。
    *   指定したURLの内容をチェックし、前回と変更があればSQSへメッセージを送信。
    *   SQSからLambda(`sqs_to_sns`)を介してSNSへ、最終的にDiscordへ通知されます。

## 展開手順

### 1. 依存関係のセットアップ（初回のみ）

このディレクトリに移動し、セットアップスクリプトを実行します。このスクリプトは、`aws` CLIおよび `terraform` がインストールされているか確認し、不足している場合は自動的にインストールを試みます。
このスクリプトにより、[AWS CLI](https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip)、[terraform](https://apt.releases.hashicorp.com/gpg)がDLされる。

```bash
cd web-check-alert-discord
./setup.sh
```

インストール後、AWSの認証情報を設定してください（未設定の場合）。
```bash
aws configure
```

### 2. 変数の設定

設定テンプレートファイルをコピーして、実際の値を入力します。

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` をエディタで開き、以下の項目を設定してください：

*   `region`: デプロイ先のリージョン（例: `ap-northeast-1`）
*   `web_url`: チェック対象のWebサイトURL
*   `s3_bucket_name`: 監視対象のS3バケット名（この名前に基づいてARNが自動生成されます）
*   `discord_webhook_url`: DiscordのWebhook URL

### 3. Terraformの実行

```bash
# 初期化
terraform init

# 実行計画の確認
terraform plan

# 構築
terraform apply
```

## 動作確認

*   **S3通知**: 指定したS3バケットにファイルをアップロードすると、Discordに通知が届きます。
*   **Webチェック**: 5分おきにチェックが走り、内容に変更があればDiscordへ通知されます。初回のチェックでは現在のハッシュがS3に保存され、2回目以降の変更から通知が始まります。

## 管理とメンテナンス

### 変数についての補足
`s3_bucket_name` は、監視対象となるS3バケットの一意の名前を指定します。Terraform内部で自動的に `arn:aws:s3:::<bucket_name>` という形式のARNに変換され、SNSのアクセス権限ポリシーなどの設定に利用されます。

### リソースの削除
```bash
terraform destroy
```

## 注意事項
*   **S3の既存バケット**: このプロジェクトは新しいS3バケットを作成します。既存のバケットを監視したい場合は、`main.tf` 内の `aws_s3_bucket` を `data "aws_s3_bucket"` に変更する必要があります。
*   **実行環境**: `setup.sh` は Ubuntu/Debian 系の Linux 環境を想定しています。
