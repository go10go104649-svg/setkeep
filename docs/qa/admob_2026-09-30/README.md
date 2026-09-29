# AdMob Banner基盤 — 開発用テスト広告

基準: `setkeep/setkeep` 最新main `c0176c9`。fetchして一致確認、開始時差分なし。
commit / push、課金、ストア登録/提出、本番広告、Supabase変更なし。

## 実装

- `google_mobile_ads` **9.1.0**。既存Flutter3.47.3 / Dart3.13.3 / Xcode27 / iOS15対象を維持。
  Swift Package Manager対応版を選択。既存パッケージをアップグレードせず、SDKとその新規WebView依存のみ追加。
- 一般版`SetkeepApp`だけ`AdsScope`を設置。HOME本体の既存スクロールを保ち、
  bottom navigation上の独立枠に1枚表示する。横SafeAreaと上下8dpで操作領域を分離。
- 現行SDKの`getLargeAnchoredAdaptiveBannerAdSize`を利用。
  幅/向き変更で旧広告を破棄して再ロード。幅・高さはSDKから取得し、画像の引伸ばしはしない。
- 読込中・失敗時は高さ0。初期化/サイズ取得/ロードに時間上限。
  起動awaitへ広告を追加せず、自動再試行ループを持たない。
- `BannerBackend` / `BannerHandle` / `BannerRequest`を境界としてテストで置換可能。
  非同期の遅い成功、画面破棄、adFree切替、バックグラウンドでも解放し、破棄後に表示しない。
- 一般版のホーム以外のタブと別routeでは非表示/解放。復帰すると条件を確認して1度ロードする。
- `AdsEntitlement`は現在無料。将来の購入検証結果を接続する一点で広告をOFFにできる。
  権利確認中に広告を出したくない場合も、その層でadFree=trueにしておく。
  ローカル有料フラグ保存やPremium/Billing/StoreKitは追加しない。

## IDと切替

| OS | App ID（ネイティブ） | Adaptive Banner ID（AdsConfig） |
|---|---|---|
| Android | ca-app-pub-3940256099942544~3347511713 | ca-app-pub-3940256099942544/9214589741 |
| iOS | ca-app-pub-3940256099942544~1458002511 | ca-app-pub-3940256099942544/2435281174 |

すべてGoogle公開のサンプル。`AdsConfig`内のApp IDとネイティブ設定の一致もテストする。
`--dart-define=SETKEEP_ADS_MODE=test`が既定値。`off`で無効。
**`production`を指定しても無効**。本番IDが未設定のまま実広告へフォールバックしない。
本番移行は、同意gate→SDK初期化→広告要求の実装とネイティブApp ID切替をレビューしたうえで、
AdsConfigに検証済みのproduction設定を追加する。画面へのID直書きは不要。

## TRAINER隔離

TRAINERはルートSETKEEP packageをpath依存しているため、SDKバイナリ/プラグイン登録が推移依存に含まれる。
その依存構成を大きく作り直さず、広告scope・初期化・Banner要求のどれもTRAINERから行わない。
Androidでは`MobileAdsInitProvider`をmanifest mergeで除去し、App ID欠如による自動起動を防ぐ。
iOSは測定自動開始を遅延し、プラグイン登録コードが広告initializeを呼ばないことを確認した。
TRAINERにテスト用App IDやバナーUIを追加しない。既存顧客/セッション/メニュー/コメント画面は変更なし。

## プライバシー: 今回と公開前を分離

今回:
- 公式テストIDのみ・非パーソナライズ要求・ミュート。アプリから履歴/店舗/ユーザーIDを広告へ渡さない。
- Android広告ID権限を一般版/TRAINERで除去。iOSはATTを要求せず、利用説明キーも追加しない。
- SDK測定の自動開始を遅延。テスト広告でもSDKとの通信は発生し、無通信/同意不要を保証するものではない。
- 既存利用規約/プライバシーポリシーと同意フローは変更なし。このビルドは広告の社内検証用。

公開前（今回は未実装）:
1. AdMobアカウントの対象地域・Privacy & messagingを確定し、UMP更新→必要時フォーム→
   `canRequestAds()`成功後のみ初期化/要求。必要なprivacy options再表示入口も用意する。
   NPAはGDPR/EEA等の同意の代わりにならない。
2. 実際のデータ利用に基づきATT要否を判断。追跡/IDFA利用をする場合は説明・許可フローを追加する。
   未許可時の動作も検証。テスト目的のためだけに今ATTを要求しない。
3. 年齢対象と子ども向け/同意年齢未満の扱いを確定し、SDKの該当設定を適用する。
   不明な現時点で全ユーザーを成人/子どもと決めつけない。
4. プライバシーポリシー、App Store Privacy、Google Play Data Safety/広告ID申告、
   SKAdNetwork/広告パートナー、SDK privacy manifest、app-ads.txt等を実構成に合わせて確認。
5. 本番ID・リリース設定とテストIDの混在防止、広告削除150円/月の購入/検証/復元は別作業。

## 検証

実行環境: Flutter 3.47.3 / Dart 3.13.3、Xcode 27.0。

| 検証 | 結果 |
|---|---|
| 一般版 `flutter analyze --no-pub` | 成功 / No issues found |
| 一般版 `flutter test --no-pub` | 全390件成功（広告回帰8件を含む） |
| TRAINER `flutter analyze --no-pub` | 成功 / No issues found |
| TRAINER `flutter test --no-pub` | 全24件成功（広告隔離回帰1件を含む） |
| 一般版 `flutter build apk --debug --no-pub` | 成功 |
| 一般版 `flutter build ios --simulator --debug --no-pub` | 成功 |
| TRAINER `flutter build apk --debug --no-pub` | 成功 |
| TRAINER `flutter build ios --simulator --debug --no-pub` | 成功 |
| `git diff --check` | 成功 |

自動テストはSDK境界をfake化し、Android/iOSテーマで狭い画面の表示、adFree時の未生成、
エラー時の高さ0、表示後の更新失敗、遅延成功のキャンセル、HOME以外/バックグラウンドでの破棄を確認。
TRAINERの主要タブにも広告scope/widgetが存在しないことを確認した。
実AdMob通信をFlutterテストでは行っていない。

生成済みAndroid merged manifestとiOS Runner.app/Info.plistも確認:
- 一般版は両OSとも指定した公式サンプルApp ID。
- TRAINERは両OSともApp IDなし。Android MobileAdsInitProviderもなし。
- 両アプリのAndroidにAD_ID権限なし、iOSに測定遅延設定あり。

未実施:
- 実機での実際のテスト広告受信、「Test Ad」ラベル、広告タップ/復帰、オフライン、回転。
- Galaxy/iPhoneでHOMEとナビゲーション間の視覚的な余白・誤タップしない配置の確認。
- iOS Simulatorはビルド確認のみで、起動/広告表示QAは実施していない。
- Release署名/ストア審査/本番配信。今回のビルドはdebug、iOSはSimulator対象。

## 変更ファイル

手書き実装・設定:
- `lib/ads/ads_config.dart` — テストID、モード、広告削除権利の接続点。
- `lib/ads/banner_backend.dart` — SDK境界、初期化・ロード・タイムアウト・破棄。
- `lib/ads/setkeep_banner_ad.dart` — 共通Adaptive Bannerと表示/lifecycle制御。
- `lib/main.dart` — 一般版scopeとHOME枠のみ。
- `android/app/src/main/AndroidManifest.xml` / `ios/Runner/Info.plist` — 一般版テスト設定。
- `apps/setkeep_trainer/android/app/src/main/AndroidManifest.xml` / `apps/setkeep_trainer/ios/Runner/Info.plist` — 共有依存の自動起動/測定対策のみ。
- `pubspec.yaml` — SDK依存。
- `test/ads_test.dart` / `apps/setkeep_trainer/test/ads_isolation_test.dart` — 回帰テスト。
- `docs/current_spec.md` / 本書 — 仕様とQA。

依存解決・ビルドによる生成変更:
- `pubspec.lock` / `apps/setkeep_trainer/pubspec.lock`
- `macos/Flutter/GeneratedPluginRegistrant.swift`（SDKのWebView推移依存）
- `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `apps/setkeep_trainer/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `apps/setkeep_trainer/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`

Vital、店舗DB、Supabase、認証処理、タイマー、トレーニング保存・履歴の実装変更なし。

## 参照した公式資料

- [Flutter SDK導入](https://developers.google.com/admob/flutter/quick-start)
- [Adaptive Bannerと公式テストID](https://developers.google.com/admob/flutter/banner)
- [iOSサンプルApp ID](https://developers.google.com/admob/ios/quick-start)
- [UMPとcanRequestAds](https://developers.google.com/admob/flutter/privacy)
- [SDK変更履歴/SPM対応](https://pub.dev/packages/google_mobile_ads/changelog)
