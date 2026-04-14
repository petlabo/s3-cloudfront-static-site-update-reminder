import os
import json
import urllib3

# 再利用可能なHTTP接続プールの初期化
http = urllib3.PoolManager()

def lambda_handler(event, context):
    """
    SNSトピックから転送されたメッセージを解析し、外部のDiscord Webhookに通知を送信します。
    複数のSNSレコードが含まれる場合を考慮し、一括で処理を行います。

    Args:
        event (dict): SNSのレコードリストを含むイベントオブジェクト
        context (LambdaContext): AWS Lambdaコンテキストオブジェクト
    """
    webhook_url = os.environ['DISCORD_WEBHOOK_URL']
    
    for record in event['Records']:
        # SNSペイロードからメッセージ本文および件名を抽出
        sns_message = record['Sns']['Message']
        sns_subject = record['Sns'].get('Subject', 'Web Check Monitoring Alert')
        
        # DiscordのEmbed形式に則りメッセージを作成
        # color: 3447003 (Soft Blue)
        discord_payload = {
            "embeds": [
                {
                    "title": sns_subject,
                    "description": sns_message,
                    "color": 3447003
                }
            ]
        }
        
        # 外部Webhook URLに対してJSON形式でPOSTリクエストを送信
        try:
            response = http.request(
                'POST',
                webhook_url,
                body=json.dumps(discord_payload),
                headers={'Content-Type': 'application/json'}
            )
            print(f"Notification Sent. Discord HTTP Status: {response.status}")
        except Exception as e:
            print(f"Error sending notification to Discord: {e}")
        
    return {"status": "success", "processed_records": len(event['Records'])}
