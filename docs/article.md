# ECSネイティブBlue/Greenをもっとイケてる運用に。Slackから再ルーティング/ロールバックする仕組みを解説

皆さんは、昨年2025年 7月登場したAmazon ECSネイティブ Blue/Green デプロイをすでに利用したことがありますでしょうか？

https://aws.amazon.com/jp/blogs/news/accelerate-safe-software-releases-with-new-built-in-blue-green-deployments-in-amazon-ecs/

従来まではBlue/Greenデプロイを実現するためにCodeDeployが必要だったりと、何やら難しそう〜、複雑そう〜という印象がありましたが、ECSネイティブ Blue/Green デプロイが登場したことで、簡単な設定追加で実現が可能となりました。とても嬉しいアップデートですね！

ただ、従来のCodeDeployを使うBlue/Greenであれば、本番トラフィックの再ルーティングタイミングをある程度コントロールできますが、ECSネイティブ Blue/Green デプロイメントでは、現時点の標準機能で実現することができません。

そこで今回は、その課題を埋めるためにECSサービスのlifecycle hookと Amazon Q Developer in chat applicationsを使って、Slackからデプロイを制御できる運用フローを組み立てていきます！

この記事では、Terraformで作成した最小構成の検証環境を使って、次の流れを再現します。

- ECSネイティブ Blue/Green デプロイを開始する
- テスト用リスナーで新しいリビジョンを確認する
- Slackに届いた通知から 再ルーティング/ロールバック を実行する

また、この記事は下記を参考に実装しました。
https://dev.classmethod.jp/articles/ecs-native-blue-green-deployment-lifecycle-hooks-amazon-q-developer-slack/


## この記事で扱うこと
- ECS ネイティブ Blue/Green デプロイメント（ALB）
- `POST_TEST_TRAFFIC_SHIFT` で動かす lifecycle hook
- Amazon Q Developer in chat applications の Slack 連携とカスタムアクション
- Terraform で再現できる最小構成

## この記事で扱わないこと

- Service ConnectでのBlue/Green デプロイメント
- VPC、ALB、ECS、ECR の基礎的な作り方
- Terraform の文法そのものの説明
- 動作確認用フロントエンドアプリの実装詳細

今回はあくまで、ECSネイティブの Blue/Green に「人が判断する承認ポイント」をどう差し込むか、というところに焦点に解説をしていきます。

## まず全体像

今回の構成では、ECSサービスを本番リスナーとテストリスナーを持つALBの後ろに置いています。
Blue/Green デプロイが始まると、新しいリビジョンはグリーン側に起動し、まずはテストリスナー経由で確認できます。
![構成](https://storage.googleapis.com/zenn-user-upload/c161b4f76ba2-20260312.png)

ここから先、lifecycle hookのライフサイクルステージについて扱うため、先にライフサイクルステージについて、ざっくり見ておきます。

ライフサイクルステージについては以下のとおりです。
>ブルー/グリーンデプロイプロセスは、個別のライフサイクルステージ (「本番トラフィックの移行後」など、デプロイオペレーションの一連のイベント) を経て進行していき、それぞれのステージに特定の役割および検証チェックポイントがあります。
参考：[デプロイのライフサイクルステージ](https://docs.aws.amazon.com/ja_jp/AmazonECS/latest/developerguide/blue-green-deployment-how-it-works.html#blue-green-deployment-stages)

lifecycle hookが使用可能なステージについて、簡単に整理すると以下のとおりとなります。
- `PRE_SCALE_UP`: Green タスクを起動する前
- `POST_SCALE_UP`: Green タスクが起動してヘルシーになったあと
- `TEST_TRAFFIC_SHIFT`: テスト用リスナーのトラフィックを Green に切り替えるタイミング
- `POST_TEST_TRAFFIC_SHIFT`: テスト用リスナーの切り替えが終わり、本番切り替えの直前　← ここでlifecycle hookでLambdaを実行
- `PRODUCTION_TRAFFIC_SHIFT`: 本番トラフィックを Green に切り替えるタイミング
- `POST_PRODUCTION_TRAFFIC_SHIFT`: 本番切り替えが終わったあと

![](https://storage.googleapis.com/zenn-user-upload/43be7c2fd031-20260312.png)
参考：[Extending deployment pipelines with Amazon ECS blue green deployments and lifecycle hooks](https://aws.amazon.com/jp/blogs/containers/extending-deployment-pipelines-with-amazon-ecs-blue-green-deployments-and-lifecycle-hooks/)

今回は「テスト用リスナーでは確認できた。では本番に進めるか、ここで戻すか」を人が判断したいので、`POST_TEST_TRAFFIC_SHIFT`を使います。

 `POST_TEST_TRAFFIC_SHIFT` のlifecycle hookでLambdaを呼び出し、LambdaからSNSに通知を送ります。
SlackにはAmazon Q Developer in chat applicationsのカスタムアクションボタン付きで通知が届き、`再ルーティング`か`ロールバック`を押すとSSM Parameter Storeにパラメータが書き込まれます。
Lambdaはその値を見て、ECSサービスに対して`SUCCEEDED`または`FAILED`を返す、という流れです。

ここで大事なのは、SlackからECSサービスを直接操作していないことです。
Slack側でやっているのはSSM Parameter Storeにパラメータを書き込むところまでで、デプロイの進行自体はlifecycle hookのLambdaが判断します。
この分け方にしておくと、どこが何を担当しているのかがかなり見通しよくなります。

## ECSネイティブ Blue/Green のどこが少し惜しいのか

ECSネイティブ Blue/Green は、新しいリビジョンを別ターゲットグループに起動して、ヘルスチェックで問題なければテスト用リスナーへトラフィックを切り替えられるので、かなり実践的です。
CodeDeployを使わなくても、ECSサービスの定義だけでここまでできるのは正直かなり便利です。

ただし、CodeDeployベースのBlue/Greenでは再ルーティングまでの猶予時間を持たせたり、任意のタイミングで本番切り替えを進めたりできたのに対して、ECSネイティブ Blue/Green ではそのタイミングを直接コントロールできません。

テスト用リスナーで確認できることと、そのあと本番に切り替えてよいかを誰かが判断することは別なので、この「最後のひと押し」をどこで受けるかは標準機能だけでは埋まりません。

## Blue/Green デプロイの流れ

今回の構成では、Blue/Green デプロイはざっくり次の順番で進みます。

1. 既存のBlueタスクが本番リスナーの後ろで動いている
2. 新しいリビジョンでGreenタスクが起動する
3. テスト用リスナーからGreenタスクにアクセスして疎通確認する
4. lifecycle hook で Lambdaが呼ばれ、Slackに通知する
5. Slackから`再ルーティング`なら本番切り替え、`ロールバック`ならデプロイ失敗として戻す

![](https://storage.googleapis.com/zenn-user-upload/9b56220fe853-20260314.png)
参考：[Amazon ECS の新しい組み込みブルー/グリーンデプロイを使用して、安全なソフトウェアリリースを加速](https://aws.amazon.com/jp/blogs/news/accelerate-safe-software-releases-with-new-built-in-blue-green-deployments-in-amazon-ecs/)

文章にするとシンプルですが、実際に試してみると「どこで待つのか」「誰がデプロイを進めるのか」を先に整理しておくのがかなり大事でした。
今回はECSの状態遷移そのものはECSに任せて、判断材料の提示と承認待ちだけを周辺サービスで補う形にしています。

## lifecycle hook の役割

今回の本題はライフサイクルステージの`POST_TEST_TRAFFIC_SHIFT` です。
つまり、Greenタスクにテストトラフィックが流れたあと、本番切り替えの直前にLambdaにて処理を差し込んでいます。


Lambdaがやっていることは、ざっくり 4 つです。

1. ECSから渡されたイベントからどのデプロイかを特定する
2. 承認済み・ロールバック済みを表すSSMパラメータ名を組み立てる
3. 初回通知ならSNSにpublishし、slackに通知が送られる
4. SSMにセットされたパラメータの状態に応じて `IN_PROGRESS`、`SUCCEEDED`、`FAILED` を返す

この形にしているので、Lambda自身が状態を持つ必要はありません。承認状態はデプロイごとの SSMパラメータとして管理し、何度呼ばれても同じ判断ができるようにしています。

それと、初回デプロイでは比較対象の旧リビジョンがないため、そのケースだけは承認待ちにせず、そのまま `SUCCEEDED` を返し、先のステージへ進めています。
最初の環境構築で毎回承認作業が必要になると、ちょっとイケてないな〜と思いました！

![lifecycle-hook](https://storage.googleapis.com/zenn-user-upload/75fc3157fcfc-20260312.png)

## Slack 側では何をしているのか

Slack側ではAmazon Q Developer in chat applicationsのSlackチャネルを作成し、そこにカスタムアクションを関連付けています。
カスタムアクションは2つだけで、approve用（再ルーティング）とrollback用です。

やっていること自体はシンプルで、`approve`はSSM Parameter Storeに「承認済み」を表す値を書き込み、`rollback`は「ロールバック要求」を表す値を書き込みます。
Slack側からECSのAPIを直接呼ぶわけではありません。

この構成にしておくと、Slack側に持たせる権限も小さくできます。
今回の環境では、チャネルロールに `ssm:PutParameter` だけを許可し、必要なパラメータだけ書き込めるようにしています。カスタムアクションにできることを狭くしておくと、運用上も説明上もかなり扱いやすいです。

Slack通知にボタンがそのまま出てくるので、体験としてもいい感じです。テスト用リスナーで新しいリビジョンの動作を確認し、問題なければそのままSlackから再ルーティングを行う、という流れがちゃんとひと続きになります。

## やってみよう

今回の検証環境はTerraformでまとめて作れるようにしてあるので、記事の手順は最小限としています。各リソースの定義の仕方などは説明しないので、適宜、生成AIに質問するなどして対応をお願いします！
事前準備として、各々Slackワークスペースと、チャンネルの作成を済ませておいてください。
:::message
TerraformコードにSlackワークスペースIDなどを変数として渡す必要があります
:::


流れとしては次のとおりです。

1. Amazon Q Developer in chat applications 側でSlackワークスペースを事前連携する
1. SlackチャンネルにAmazon Qを招待する
1. Terraformでインフラ一括作成する
1. 動作確認用フロントエンドアプリの`v1` イメージをECRにpushする
1. ECSサービスの `desired_count` を `1` にしてタスクを起動する
1. 動作確認用フロントエンドアプリの`v2` イメージをpushし、Blue/Green デプロイを開始する
1. テスト用リスナーで`v2`の動作を確認する
1. Slackから`再ルーティング`または`ロールバック`を実行する

### Amazon Q Developer in chat applications 側でSlackワークスペースを事前連携する

AWSコンソールから、`Amazon Q Developer in chat applications`を検索し、設定画面に遷移します。
`チャットクライアント`をSlackに合わせて、`クライアントを設定`を選択してください。
![](https://storage.googleapis.com/zenn-user-upload/9e2623efdf45-20260314.png)

各々、今回使用するワークスペースを選択して進めてください。
![](https://storage.googleapis.com/zenn-user-upload/b56db9640ce6-20260314.png)

キャプチャの通りになれば連携は完了です。
![](https://storage.googleapis.com/zenn-user-upload/6b57efd3d49a-20260314.png)

### SlackチャンネルにAmazon Qを招待する
使用するSlackチャンネルの詳細画面から`インテグレーション`タブに遷移し、`アプリを追加する`を選択し、`Amazon Q Developer`を追加してください。
![](https://storage.googleapis.com/zenn-user-upload/afd953e6e69d-20260314.png)


### Terraformでインフラ一括作成する
::: message
- SlackワークスペースIDとチャンネルIDを変数として渡すので、控えておいてください
- tfstate用のS3バケットを各々作成し、`backend.tf`内のバケット名に変更してください
:::

今回使用するソースコードはこちらです。
https://github.com/takxxx-infra/ecs-bg-deployment/tree/main


まずはインフラリソースをapplyしてください。
大体4~5分程度で完了するかと思います。

今回のECSネイティブBlue/Greenデプロイで重要となるポイントをさらっと見ていきます！

まずは、ECSサービスの`デプロイオプション`から見ていきましょう。
`デプロイ戦略`が`ブルー/グリーン`となっていることがわかります。
`ベイク時間`については以下のとおりです。
>本番トラフィックがグリーンにシフトした後、ブルーへの即時ロールバックが可能になるまでの時間です。ベイク時間が経過すると、ブルータスクは削除されます。
参考：[Amazon ECS の新しい組み込みブルー/グリーンデプロイを使用して、安全なソフトウェアリリースを加速](https://arc.net/l/quote/fyetluuk)

今回は`10分`で設定していますので、再ルーティング後10分間はロールバックが可能となります。
![](https://storage.googleapis.com/zenn-user-upload/d1615800bd75-20260314.png)

続いて、`Amazon Q Developer in chat applications`を見ていきましょう。
Terraformにて正しくリソースが作成されていれば、以下のように有効な設定済みチャネルがあるかと思うので、それを選択してください。
![](https://storage.googleapis.com/zenn-user-upload/53957ebc4a6b-20260314.png)

Slackチャンネルとの連携に問題がないことを確認するために、`テストメッセージを送信`にてSlackチャンネルにメッセージが届くことを確認してみましょう。
届かない場合は、変数として私たチャンネルIDなどに不備がないか確認してください。
![](https://storage.googleapis.com/zenn-user-upload/803e899161a2-20260314.png)

このようなメッセージが届くと思います。
![](https://storage.googleapis.com/zenn-user-upload/8b413078877f-20260314.png)

### 動作確認用フロントエンドアプリの`v1` イメージをECRにpushする
いよいよ、実際にECSタスクを起動し動きを順番に見ていきます！
>ここまで説明が長くてつまんね〜と思った方、わかります。
>安心してください。ここからめっちゃくちゃ楽しいです。

プロジェクトルートから下記コマンドを実行し、`v1`イメージをビルド&プッシュしてください。
```sh
make release-image IMAGE_TAG=v1
```
`v1`タグが付与されたイメージがプッシュされていることが確認できます。
![](https://storage.googleapis.com/zenn-user-upload/ef4f553847ac-20260314.png)

### ECSタスクを起動する
ECSサービスの `desired_count` を `1` にしてタスクを起動しましょう。
Terraformからでもコンソールからでもお好きな方法で構いません。

```diff hcl:ecs.tf
+ desired_count = 1
- desired_count = 0
```
それではECSタスクが起動しているか確認してみましょう！
問題なくタスクが実行されており、現在はGreen側ターゲットグループに関連付けされ起動しているようですね。
![](https://storage.googleapis.com/zenn-user-upload/4bdbc6f4137d-20260314.png)

ALBリスナーを確認すると、本番用リスナー（Port80)、テスト用リスナー（Port20080)ともに、ECSタスクが起動しているGreen側ターゲットグループに100%比重が向いていることがわかります。

- 本番用リスナー
![](https://storage.googleapis.com/zenn-user-upload/a286aa7fddbd-20260314.png)

- テスト用リスナー
![](https://storage.googleapis.com/zenn-user-upload/d5f2ecb5a1bc-20260314.png)

それでは、ALBのDNS名を確認し、それぞれのリスナーに向けてアクセスし、画面を確認してみましょう。

- 本番用リスナー
    - `http://{ALB DNS名}/`
- テスト用リスナー
    - `http://{ALB DNS名}:20080/`

まずは、本番用リスナーに接続してみます。
問題なく接続ができ、現在の`Version`は`v1`、`Deployment Color`は`Blue`であることが確認できます。
![](https://storage.googleapis.com/zenn-user-upload/9812ff0e1a88-20260314.png)

続いて、テスト用リスナーに接続してみます。
こちらも同様に`Version`は`v1`、`Deployment Color`は`Blue`となっており、現在はどちらのリスナーも本番リビジョンに接続できている状態となります。
![](https://storage.googleapis.com/zenn-user-upload/817c42885cb8-20260314.png)

### 動作確認用フロントエンドアプリの`v2` イメージをpushし、Blue/Green デプロイを開始する
ここからが本記事のメイン所になります！
新しいリビジョンをデプロイし、テストトラフィックへの移行 → Slack通知 → 再ルーティング の流れを一気に見ていきます！

プロジェクトルートから下記コマンドを実行し、`v2`イメージをビルド&プッシュしてください。
```sh
make release-image IMAGE_TAG=v2
```
タスク定義が参照するイメージURIを`v2`に変更します。こちらもTerraformからでもコンソールからでも、どちらでも構いません。

```diff hcl:ecs_task_definition.tf
+ frontend_app = "v2"
- frontend_app = "v1"
```

新しいリビジョンのタスクが実行さてたことが確認できます。
![](https://storage.googleapis.com/zenn-user-upload/f2c9ee33ab50-20260314.png)

デプロイのステータスが`進行中...`となり、Blue/Greenデプロイが動作していることがわかります。
また、ライフサイクルステージが`テストトラフィック移行後`、つまり`POST_TEST_TRAFFIC_SHIFT`に遷移したので、lifecycle hookによりLambda関数が実行され、Slackに通知が届いているはずです！
![](https://storage.googleapis.com/zenn-user-upload/0834c34c804b-20260314.png)

以下のように、Slackチャンネルに通知が届いていることが確認できました。
>最低限必要なメタデータを通知に載せていますが、運用に合わせて必要な情報を記載し、通知内容をカスタマイズするといい感じかと思います。

![](https://storage.googleapis.com/zenn-user-upload/5127b2dd4a7d-20260314.png)

Lambda関数の実行ログについても、見ておきましょう。
![](https://storage.googleapis.com/zenn-user-upload/b270e235e8bb-20260314.png)

ログの出力を見てみると、30秒おきに実行されていることがわかります。
デフォルトではECSによって30秒毎にLambda関数が実行されるためです。
>IN_PROGRESS – Amazon ECS により、短期間の後に関数が再度実行されます。デフォルトではこれは 30 秒間隔ですが、この値は callBackDelay とともに hookStatus を返すことでカスタマイズできます。
参考：[Amazon ECS サービスデプロイのライフサイクルフック](https://arc.net/l/quote/plbkysqe)

この実行感覚はSSMパラメータのポーリング間隔に直結します。
つまり、`再ルーティング`や`ロールバック`の実行速度に直結するため、あまり間隔を長くしてしまうと即時ロールバックを実施したい場合に次回のLambda実行まで待つ必要が発生するため、この間隔は運用に合わせ訂正値を定めるのが良さそうですね。
>今回使用したLambda関数では、環境変数から実行間隔を設定できます。

### テスト用リスナーでv2の動作を確認する
それでは、テスト用リスナーに接続してみましょう。
![](https://storage.googleapis.com/zenn-user-upload/6fab7819d520-20260315.png)

`Version`は`v2`に、`Deployment Color`は`Green`となっていることが確認できます！
テスト用リスナー側は新しいリビジョン側に向いていることがわかりますね。

続いて、本番用リスナーに接続してみましょう。
![](https://storage.googleapis.com/zenn-user-upload/b700b686fb31-20260315.png)

こちらは、`Version`は`v1`に、`Deployment Color`は`Blue`となっています。
つまり、本番用ではまだ更新前のリビジョンで接続されていることがわかります。

本番用リスナー → `v1`
テスト用リスナー → `v2`

このことから、現在`再ルーティング`は保留状態となっていることがわかります。
ALBリスナーもそれぞれ見ておきましょう。

- 本番用リスナー
`v1`が起動している、Green側ターゲットグループに向いていることがわかります。
![](https://storage.googleapis.com/zenn-user-upload/72a71a3bbb59-20260315.png)

- テスト用リスナ-
`v2`が起動している、Blue側ターゲットグループを向いていることがわかります。
![](https://storage.googleapis.com/zenn-user-upload/f647977461ae-20260315.png)

ECSサービスによって、ALBリスナーの`重み付け`をコントロールすることで、Blue/Greenデプロイが動作しています。

### Slackから`再ルーティング`または`ロールバック`を実行する
ようやくここまできました！
もはや、ここが本記事の本番と言いますか脳汁ポイントです。
さっそく、Slack通知に届いたメッセージから、`再ルーティング`を実行してみましょう。

`再ルーティング`ボタンを選択すると、以下のように実行確認画面が表示されます。
問題なければ`Run`を選択してください。
![](https://storage.googleapis.com/zenn-user-upload/d70c3a6d5e71-20260315.png)

実行結果は実行したSlackユーザーにメンションされる形で、スレッドに書き込まれます。
![](https://storage.googleapis.com/zenn-user-upload/ee3c1641313c-20260315.png)

ECSのライフサイクルステージをみると、`本番トラフィックへ移行`となり、ステージが進んでいることがわかります。
30秒毎に実行されるLambdaがSSMパラメータをポーリングし、`再ルーティング`のフラグを確認したためです。
![](https://storage.googleapis.com/zenn-user-upload/993e5a04d6f9-20260315.png)

それでは、本番用リスナーに接続し、`v2`に再ルーティングされているか確認をしましょう！
無事、`v2`の画面が表示されていることが確認できました。
![](https://storage.googleapis.com/zenn-user-upload/3474c752fcb9-20260315.png)

一応、テスト用リスナーも確認しておきます。
こちらはそのまま、`v2`となっていますね。
![](https://storage.googleapis.com/zenn-user-upload/5eb42d11b0ed-20260315.png)

改めて、ECSのライフサイクルステージを確認すると、`ベイク時間`となっています。
前途で説明したとおり、ベイク時間に設定した時間の経過後、古いリビジョンのタスクが削除されます。
![](https://storage.googleapis.com/zenn-user-upload/529ff209f636-20260315.png)

ベイク時間の経過後は、タスクが削除され、デプロイのステータスも`成功`となりました。
![](https://storage.googleapis.com/zenn-user-upload/de200225ce25-20260315.png)

### ロールバック編
現在、バージョンは`v2`にのため、タスク定義の参照イメージURIを再び`v1`に変更します。
そうすると、`v2` → `v1`へのBlue/Greenデプロイが動作します。
ただし、今回はロールバックを実施するため、本番用リスナーが`v2`となっているとを確認するのがゴールになります。

再ルーティングと確認する点は一緒なので、さらっとみていきます。

参照イメージURIを`v1`に変更後の、テスト用リスナーを確認します。
`v1`となっていますね。
![](https://storage.googleapis.com/zenn-user-upload/53c707cc3639-20260315.png)

Slack通知から、`ロールバック`を実行します。
ECSのデプロイ状態を確認すると、ロールバックが動作していることがわかります。
![](https://storage.googleapis.com/zenn-user-upload/4285a31acd86-20260315.png)

再び、テスト用リスナーに接続し確認すると、`v2`となっており正常にロールバックされたことが確認できました。
![](https://storage.googleapis.com/zenn-user-upload/3ab3f1b19d78-20260315.png)

ECS側でも`ロールバックが成功`となっていますね。
![](https://storage.googleapis.com/zenn-user-upload/b57dd2f26cf9-20260315.png)

もちろん、本番用リスナーは`v2`となっています。
![](https://storage.googleapis.com/zenn-user-upload/cffbaf32d5d1-20260315.png)

以上で動作検証は完了となります！

## 後片付け
無駄なコストを発生させないため。Terraformを使ってまとめて削除しましょう！


## まとめ

ECS 組み込み Blue/Green デプロイは、それ単体でもかなり便利です。ただ、実運用では「確認した結果、進めるか戻すかを人が決める」という最後の一歩がほしくなる場面があります。

今回はその一歩を、lifecycle hook、SNS、SSM Parameter Store、Amazon Q Developer in chat applications のカスタムアクションを組み合わせて補いました。やっていることはそこまで複雑ではありませんが、ECS に余計な責務を持たせず、Slack 側にも最小限の権限しか渡さないので、構成としてはかなり素直です。

CodeDeploy を使わずに ECS native の Blue/Green を活かしたいとき、こういう承認フローの足し方はかなり現実的な選択肢だと思います。CodeDeploy では持てていた再ルーティングのコントロールポイントを、ECS native でも運用上ほしい形で取り戻したい、という文脈には特に相性がよいはずです。

また、本構成はまだまだ改善の余地はあると考えています。
例えば、デプロイの状態をSSM Parameter StoreではなくDynamoDBを使うことで、より多くの情報を記録することができ、監査目的でも残すことが可能です。
実際の要件や運用に合わせ、より良い選択をしていければ良いのではないでしょうか。

