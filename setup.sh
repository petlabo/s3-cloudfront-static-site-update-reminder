#!/bin/bash

# ==============================================================================
# web-check-alert-discord 環境セットアップスクリプト
# ==============================================================================

set -e

echo "[INFO] 依存関係の確認を開始します..."

# コマンドの正常動作を確認する関数
check_cmd_works() {
    if command -v "$1" >/dev/null 2>&1; then
        if "$1" --version >/dev/null 2>&1; then
            echo "[OK] $1 は正常に動作しています: $($1 --version | head -n 1)"
            return 0
        else
            echo "[ERROR] $1 は見つかりましたが、正常に動作していません（インストールが不完全な可能性があります）。"
            return 1
        fi
    else
        echo "[ERROR] $1 がインストールされていません。"
        return 1
    fi
}

# AWS CLI の確認とインストール/修正
if ! check_cmd_works aws; then
    echo "[INFO] AWS CLI (Official v2 Standalone) のインストールまたは修正を試みます..."
    
    # 既存のインストーラー等をクリーンアップ
    rm -f awscliv2.zip
    rm -rf aws

    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q -o awscliv2.zip
    
    if [ -x "/usr/local/bin/aws" ]; then
        echo "[INFO] 既存の AWS CLI を更新します..."
        sudo ./aws/install --update
    else
        echo "[INFO] 新規インストールを実行します..."
        sudo ./aws/install
    fi
    
    rm -rf aws awscliv2.zip
    
    # 再度確認
    if /usr/local/bin/aws --version >/dev/null 2>&1; then
        echo "[OK] AWS CLI のインストールと検証が完了しました (/usr/local/bin/aws)"
    else
        echo "[ERROR] AWS CLI のインストール検証に失敗しました。"
    fi
fi

# Terraform の確認とインストール
if ! check_cmd_works terraform; then
    echo "[INFO] Terraform のインストールを開始します..."
    sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt-get update && sudo apt-get install -y terraform
    echo "[OK] Terraform のインストールが完了しました。"
fi

echo ""
echo "[INFO] セットアップが完了しました。"
echo "[NOTICE] 引き続きエラーが発生する場合は 'rm ~/.local/bin/aws' を実行し、ターミナルを再起動してください。"
