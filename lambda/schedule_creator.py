import os
import json
import boto3
import datetime

# AWSサービスクライアントの初期化
scheduler = boto3.client('scheduler')
sns = boto3.client('sns')
lambda_client = boto3.client('lambda')

def lambda_handler(event, context):
    """
    S3バケットへのデプロイイベントをトリガーとして、監視の即時実行および
    短期間（1時間限定）の継続的なポーリングスケジュールを動的に作成します。

    Args:
        event (dict): S3のイベントデータ
        context (LambdaContext): AWS Lambdaコンテキストオブジェクト
    """
    print(f"S3 Event Received: {json.dumps(event)}")

    target_lambda_arn = os.environ['TARGET_LAMBDA_ARN']
    scheduler_role_arn = os.environ['SCHEDULER_ROLE_ARN']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    site_name = os.environ.get('SITE_NAME', '対象Webサイト')
    web_url = os.environ['WEB_URL']
    schedule_name_prefix = os.environ.get('SCHEDULE_NAME_PREFIX', 'WebCheck-Dynamic-')

    # 日本標準時 (JST) でタイムスタンプを生成
    jst = datetime.timezone(datetime.timedelta(hours=9))
    now = datetime.datetime.now(jst)
    timestamp = now.strftime('%Y/%m/%d %H:%M:%S')

    # S3バケットの更新をSNSに通知し、デプロイ完了を報告
    try:
        # メッセージの構造化 (1行目: サイト名更新告知, 2行目: URL, 3行目: 時刻)
        deploy_message = (
            f"{site_name} のソースが更新されました。\n"
            f"URL: {web_url}\n"
            f"更新時刻: {timestamp}"
        )
        sns.publish(
            TopicArn=sns_topic_arn,
            Message=deploy_message,
            Subject="S3デプロイ通知"
        )
    except Exception as e:
        print(f"SNS notification error: {e}")

    # デプロイ直後の状態を即時確認するため、Web Checker Lambdaを非同期で直接実行
    try:
        lambda_client.invoke(
            FunctionName=target_lambda_arn,
            InvocationType='Event',
            Payload=json.dumps({"source": "s3-event-immediate", "triggered_at": timestamp})
        )
    except Exception as e:
        print(f"Immediate check invocation error: {e}")

    # デプロイ後の波及的な変更を監視するため、EventBridge Schedulerで1時間限定のスケジュールを作成
    bucket_name = event['Records'][0]['s3']['bucket']['name'] if 'Records' in event and len(event['Records']) > 0 else "unknown"
    
    # 即時実行との重複を避けるため、10分後からポーリングを開始
    ten_minutes_later = now + datetime.timedelta(minutes=10)
    one_hour_later = now + datetime.timedelta(hours=1)
    
    # 衝突を回避するため、ユニークなスケジュール名を生成
    unique_schedule_name = f"{schedule_name_prefix}{int(datetime.datetime.now().timestamp() * 1000)}"

    schedule_params = {
        'Name': unique_schedule_name,
        'ScheduleExpression': 'rate(10 minutes)',
        'StartDate': ten_minutes_later,
        'EndDate': one_hour_later,
        'ActionAfterCompletion': 'DELETE', # 終了後にリソースを自動削除
        'Target': {
            'Arn': target_lambda_arn,
            'RoleArn': scheduler_role_arn,
            'Input': json.dumps({
                "source": "dynamic-scheduler",
                "triggered_by_s3": bucket_name,
                "triggered_at": timestamp
            })
        },
        'FlexibleTimeWindow': { 'Mode': 'OFF' }
    }

    try:
        scheduler.create_schedule(**schedule_params)
        print(f"Schedule created successfully: {unique_schedule_name}")
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Schedule Created", "scheduleName": unique_schedule_name})
        }
    except Exception as e:
        print(f"Schedule creation error: {e}")
        raise e
