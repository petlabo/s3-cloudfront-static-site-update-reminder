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

    # S3イベントから詳細情報を抽出
    record = event['Records'][0] if 'Records' in event and len(event['Records']) > 0 else {}
    object_key = record.get('s3', {}).get('object', {}).get('key', 'unknown')
    event_name = record.get('eventName', 'unknown')
    bucket_name = record.get('s3', {}).get('bucket', {}).get('name', 'unknown')

    # 【重複対策1】完全一致のチェック
    # prefixフィルターをすり抜けた一時ファイル（index.html.tmp等）をここで完全に排除します
    if object_key != 'index.html':
        print(f"Skipping trigger for non-target file: {object_key}")
        return {"statusCode": 200, "body": "Skipped"}

    # S3バケットの更新をSNSに通知し、デプロイ完了を報告
    try:
        deploy_message = (
            f"【発火要因】S3デプロイ検知 ({event_name})\n"
            f"トリガーファイル: {object_key}\n"
            f"対象サイト: {site_name}\n"
            f"URL: {web_url}\n"
            f"検知時刻: {timestamp}"
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
            Payload=json.dumps({
                "source": "s3-event-immediate", 
                "trigger_file": object_key,
                "triggered_at": timestamp
            })
        )
    except Exception as e:
        print(f"Immediate check invocation error: {e}")

    # デプロイ後の波及的な変更を監視するため、EventBridge Schedulerで1時間限定のスケジュールを作成
    # 即時実行との重複を避けるため、10分後からポーリングを開始
    ten_minutes_later = now + datetime.timedelta(minutes=10)
    one_hour_later = now + datetime.timedelta(hours=1)
    
    # 【重複対策2】スケジュール名の固定化
    # タイムスタンプを削除し、固定名にすることで、複数回呼ばれても既存のスケジュールを「更新」するだけに留めます
    unique_schedule_name = f"{schedule_name_prefix}Main"

    schedule_params = {
        'Name': unique_schedule_name,
        'ScheduleExpression': 'rate(10 minutes)',
        'StartDate': ten_minutes_later,
        'EndDate': one_hour_later,
        'ActionAfterCompletion': 'DELETE',
        'Target': {
            'Arn': target_lambda_arn,
            'RoleArn': scheduler_role_arn,
            'Input': json.dumps({
                "source": "dynamic-scheduler",
                "trigger_file": object_key,
                "triggered_by_s3": bucket_name,
                "triggered_at": timestamp
            })
        },
        'FlexibleTimeWindow': { 'Mode': 'OFF' }
    }

    try:
        # 既存のスケジュールがある場合は一度削除（または上書き）して、常に最新の1つだけに維持します
        try:
            scheduler.delete_schedule(Name=unique_schedule_name)
        except scheduler.exceptions.ResourceNotFoundException:
            pass

        scheduler.create_schedule(**schedule_params)
        print(f"Schedule created successfully: {unique_schedule_name}")
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Schedule Created", "scheduleName": unique_schedule_name})
        }
    except Exception as e:
        print(f"Schedule creation error: {e}")
        return {"statusCode": 500, "body": str(e)}
