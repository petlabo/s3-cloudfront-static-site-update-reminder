import os
import json
import boto3
import urllib3
import hashlib
import datetime

# 外部接続およびAWSサービスとの通信用クライアント初期化
s3 = boto3.client('s3')
sns = boto3.client('sns')
http = urllib3.PoolManager()

def lambda_handler(event, context):
    """
    指定されたWebサイトのコンテンツを取得し、前回の実行時と比較して変更を検知します。
    変更が確認された場合、SNSトピックを介して通知を発行します。

    Args:
        event (dict): スケジューラまたはS3イベントから渡されるペイロード
        context (LambdaContext): AWS Lambdaコンテキストオブジェクト
    """
    web_url = os.environ['WEB_URL']
    site_name = os.environ.get('SITE_NAME', '対象Webサイト')
    state_bucket = os.environ['S3_BUCKET_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    state_file = "web_check_state.txt"

    # 日本標準時 (JST) でタイムスタンプを生成
    jst = datetime.timezone(datetime.timedelta(hours=9))
    timestamp = datetime.datetime.now(jst).strftime('%Y/%m/%d %H:%M:%S')

    # Webサイトのコンテンツを取得し、比較用のSHA-256ハッシュ値を生成
    try:
        print(f"Checking URL: {web_url}")
        response = http.request('GET', web_url, timeout=10)
        current_content = response.data
        current_hash = hashlib.sha256(current_content).hexdigest()
    except Exception as e:
        print(f"Error fetching web page: {e}")
        return {"status": "error", "message": str(e)}

    # S3バケットから直近の正常実行時のハッシュ値を取得
    previous_hash = None
    try:
        s3_obj = s3.get_object(Bucket=state_bucket, Key=state_file)
        previous_hash = s3_obj['Body'].read().decode('utf-8').strip()
    except s3.exceptions.NoSuchKey:
        print("First execution or state file missing. Proceeding to save initial state.")
    except Exception as e:
        print(f"Error reading state from S3: {e}")

    # 呼び出し元情報の取得（デバッグ用）
    source = event.get('source', 'unknown-trigger')
    trigger_file = event.get('trigger_file', 'n/a')
    
    # 日本語のソース名に変換
    source_display = {
        "s3-event-immediate": "S3デプロイ直後の即時確認",
        "dynamic-scheduler": "定期ポーリング監視",
        "unknown-trigger": "直接実行または不明なトリガー"
    }.get(source, source)

    # ハッシュ値の比較を行い、不一致（更新）がある場合にSNS通知を実行
    if previous_hash and current_hash != previous_hash:
        print(f"Change detected for URL: {web_url}")
        
        message = (
            f"【発火要因】{source_display}\n"
            f"トリガーファイル: {trigger_file}\n"
            f"対象サイト: {site_name}\n"
            f"URL: {web_url}\n"
            f"検知時刻: {timestamp}"
        )
        sns.publish(
            TopicArn=sns_topic_arn,
            Message=message,
            Subject="Webサイト更新通知"
        )
    
    # 次回比較のため、現在のハッシュ値をS3に永続化
    try:
        s3.put_object(
            Bucket=state_bucket, 
            Key=state_file, 
            Body=current_hash.encode('utf-8'),
            ContentType='text/plain'
        )
    except Exception as e:
        print(f"Error saving state to S3: {e}")

    return {"status": "ok", "hash": current_hash}
