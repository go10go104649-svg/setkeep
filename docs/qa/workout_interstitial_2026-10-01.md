# トレーニング完了後Interstitial — 2026-10-01

対象: SETKEEP一般版。既存のHOME Adaptive BannerとTRAINER広告なし方針は維持。

## 動作

- 入力検証通過後に広告ロードを開始するが、新規トレーニング記録の保存、active draft削除、任意の設備確認を先に確定してから表示を試行する。編集と履歴からの画像作成は対象外。
- トレーニング完了時は毎回候補とし、実表示は端末のローカルカレンダー日ごとに最大1回とする。履歴やSupabaseの個人データは広告頻度へ使用しない。旧3回カウンターは参照しない。
- 入力検証通過後の完了処理開始時にGoogle公式テストInterstitialを事前ロードする。表示時にロード中なら最大1秒待ち、未ロード、失敗、バックグラウンド、adFree時は表示をスキップする。
- `onAdShowedFullScreenContent`で実表示を確認できた場合だけ日付を保存する。ロード失敗、未ロード、show失敗では日付を保存せず、同日の次回トレーニングで再挑戦できる。
- 画像保存成功後、または画像を保存せずHOMEへ戻る直前に表示を最大1回だけ試行する。保存失敗時は表示せず、後で画面を閉じる際の1回のみ候補にする。
- 広告callbackが来ない場合にも30秒で待機を終える。広告の成否は記録保存、画像保存、HOME遷移を巻き戻さない。
- 一般版のみ`AdsScope`からInterstitialのSDK境界を取得。TRAINERにはscopeも広告要求もない。`AdsEntitlement.adFree`はBannerとInterstitialの両方を止める。
- App IDとBanner IDは既存の公式テスト値を維持。Interstitial IDもAndroid `ca-app-pub-3940256099942544/1033173712`、iOS `ca-app-pub-3940256099942544/4411468910` の公式テスト値のみ。`SETKEEP_ADS_MODE=production`では引き続き広告要求しない。

## コード監査

- `TODO`/`FIXME`、debug出力、旧ブランド文字列・色、広告ID、リリース設定を確認。`MUSCLEMORY`は旧テンプレート/署名環境との互換読込に限定され、ユーザー表示ではないため維持した。
- TRAINER Androidのreleaseビルドは現状debug鍵設定のまま。ストア提出前に正式署名設定が必要。今回の広告変更と無関係のため修正しない。
- 一般版のrelease署名は外部ファイルを要求する構成。本番広告ID、UMP/ATT・プライバシー申告は未実装で、本番ストア公開前の別工程。
- 機密値の新規ハードコード、店舗・認証・トレーニング履歴データの変更なし。

## 日次仕様への更新後の検証

- 一般版/ TRAINER `flutter analyze --no-pub`: 両方成功、0 issues。
- `test/workout_interstitial_test.dart`にローカル日付制限、実表示時だけの記録、adFree、失敗/未ロード、500ms遅延ロード、二重show、バックグラウンド、保存済み記録後の遷移、SNS画像保存後の遷移、TRAINER隔離のfake SDKテストを追加。
- 一般版 `flutter test --no-pub`: 408件成功。TRAINER `flutter test --no-pub`: 24件成功。
- 一般版 Android debug build: 成功（`build/app/outputs/flutter-apk/app-debug.apk`）。
- `git diff --check`: 成功。
- Galaxy: `flutter devices`で接続を確認できなかったため、日次1回の実表示確認は未実施。

Galaxyで当日最初の完了時のテスト広告、同日2回目の非表示、画像保存後/非保存時の遷移、オフライン時の同日再挑戦を確認すること。

## 旧仕様

初回実装では初回を非表示、完了3回目ごとを候補とし、表示時に未ロードなら即時スキップしていた。この仕様はGalaxyで5回完了しても表示されない結果を受けて廃止した。
