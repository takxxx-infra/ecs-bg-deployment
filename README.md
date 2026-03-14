# ecs-bg-deployment

Slack 上の Amazon Q Developer in chat applications と組み合わせて、ECS 組み込み Blue/Green デプロイメントを検証するための Terraform と簡易フロントエンドアプリです。

## ディレクトリ構成

- `terraform/`: 技術記事用の AWS インフラ定義
- `app/frontend/`: ECS にデプロイする単一コンテナの nginx アプリ
- `Makefile`: frontend イメージの build / push 用ターゲット

## 前提条件

- Terraform `1.14.4`
- 対象 AWS アカウントの認証情報が設定された AWS CLI v2
- Docker
- Amazon Q Developer in chat applications で事前に認可済みの Slack ワークスペース

## クイックスタート

ルートの `Makefile` は、`AWS CLI` の認証情報が設定されていれば `aws sts get-caller-identity` で `AWS_ACCOUNT_ID` を自動取得します。
必要に応じて `AWS_PROFILE=your-profile` や `AWS_ACCOUNT_ID=123456789012` を明示指定できます。

1. 変数ファイルのサンプルをコピーし、Slack 関連の値を設定します。

```sh
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

2. Terraform を初期化し、インフラを作成します。デフォルトでは ECS サービスの `desired_count = 0` にしてあるため、ECR にイメージがまだ無い状態でも先に環境を作成できます。

```sh
terraform init
terraform apply
```

3. 最初のフロントエンドイメージを build して push します。

```sh
make release-image IMAGE_TAG=v1
```

4. `terraform/ecs.tf` の `desired_count` を `1` に変更し、ECS サービスを起動します。

```sh
cd terraform
terraform apply
```

5. Slack チャンネルに Amazon Q を招待します。

```text
/invite @Amazon Q
```

6. 新しいイメージタグを push し、Blue/Green デプロイを発生させます。

```sh
make release-image IMAGE_TAG=v2
```

そのあと `terraform/ecs_task_definition.tf` 側でイメージタグを `v2` に更新し、`terraform apply` を実行します。

```sh
cd terraform
terraform apply
```

7. Slack 上でデプロイを承認、またはロールバックします。

## 注意事項

- `chatbot_region` は Amazon Q Developer in chat applications で Slack クライアントを設定したリージョンと一致している必要があります。
- `slack_workspace_id` は、Amazon Q Developer in chat applications で初回の Slack 認可を行ったあとにコンソールから取得してください。
- フロントエンドアプリは `8080` ポートで `/healthcheck` を公開します。

## テスト

Terraform ディレクトリで承認 Lambda のユニットテストを実行できます。

```sh
cd terraform
python3 -m unittest discover -s tests
```
