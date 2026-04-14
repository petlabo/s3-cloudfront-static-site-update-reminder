import os
import json
import boto3

# SNSクライアントの初期化
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    SQSキューにメッセージが入った際に自動的に起動される関数。
    SQSの内容を読み取り、SNSトピックへと再発行（Publish）します。
    """
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    for record in event['Records']:
        try:
            # SQSのメッセージボディ（JSON）を解析
            body = json.loads(record['body'])
            message = body.get('message', 'Webサイトの更新が検知されました（SQS経由）')
            
            # SNSへメッセージを発行
            print(f"SNSへ通知を発行中: {message}")
            sns.publish(
                TopicArn=topic_arn,
                Message=message,
                Subject="Webサイト更新通知"
            )
        except Exception as e:
            print(f"メッセージの処理中にエラーが発生しました: {e}")
        
    return {"status": "ok"}
