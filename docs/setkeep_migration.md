# SETKEEP ブランド・識別子移行（2026-09-25）

## 変更と識別子

|用途|旧|新|
|---|---|---|
|表示名|MUSCLEMORY|SETKEEP|
|Dart package|muscle_memory|setkeep|
|Android applicationId / namespace / Kotlin package|com.musclememory.muscle_memory|com.setkeep.app|
|iOS / macOS bundle|com.musclememory.muscleMemory|com.setkeep.app|
|iOS Widget|com.musclememory.muscleMemory.RestTimerWidget|com.setkeep.app.RestTimerWidget|
|テストbundle|com.musclememory.muscleMemory.RunnerTests|com.setkeep.app.RunnerTests|
|OAuth callback|musclemory://login-callback/|setkeep://login-callback/|
|Flutter/native channel|com.musclememory/rest_timer、workout_image|com.setkeep.app/rest_timer、workout_image|
|新規画像保存先 / ファイル名|MUSCLEMORY|SETKEEP|

App Group、Keychain group、Associated Domains、Push entitlement は現在使用していない。
Live Activity はActivityKitのContentStateを使用し、WidgetとのApp Group共有ストレージはない。
不要なApp Group追加はしていない。将来追加する場合は `group.com.setkeep.app` を使用する。
Runner / RestTimerWidget target・scheme名はブランド由来でないため維持。

## データと互換性

- 新applicationId / bundleは別アプリ。旧アプリのOSサンドボックスを新アプリから読み取ることはできない。
- 旧アプリをアンインストールする前に既存バックアップ機能で書き出し、SETKEEPで復元する。
- バックアップの `app` は新規出力SETKEEP、読込はSETKEEP / MUSCLEMORY / MuscleMemoryのv1〜v3を受理。内容・形式は変更しない。
- トレーニング・体重・テンプレート等は既存バックアップで移行する。既存バックアップが含まないローカル専用データ（手動場所の設備、途中draft等）は自動移行しない。旧アプリとデータを保持したまま必要に応じて移し、確認まで旧アプリを削除しない。
- 新アプリでは通知・カメラ等のOS権限も再許可が必要。旧通知タイマーを終了してから切り替える。
- 新アプリでは再ログインが必要。Supabaseの同じプロジェクト・同じアカウントを利用する。登録店舗、管理者、店舗設備、報告、クラウドデータは既存DBを維持。
- SharedPreferencesキー、通知deadline、WorkoutDraft、Supabaseセッションキーは変更しない。ブランド名だけを理由としたDB再構築やデータ一括書換えは行わない。
- 旧招待QRを受理。OAuth旧schemeは移行期間のみ受理し、新規callbackはsetkeep。新旧アプリ併存時、旧schemeのリンクはOSが旧アプリに渡す可能性があるため、新しい認証はsetkeepを使用。
- 過去のQA記録・生成物・Blender作業領域・プレビュー安全マーカーを保持。3D再生成は行わない。

## ユーザー側の外部設定

### Supabase（新callbackの許可は必須）

Dashboard → Authentication → URL Configuration → Redirect URLs に `setkeep://login-callback/` を追加する。
旧 `musclemory://login-callback/` は旧アプリ利用中は残す。Site URLは他クライアントにも影響するので一括上書きしない。
ローカル `supabase/config.toml` は両callbackを許可するが、remoteへのconfig一括pushは行っていない。
Authentication → Email Templates等に旧ブランドがある場合はSETKEEPへ。URLやキーを架空の値へ置換しない。
既存Auth / RLS / app_admins / Edge Functions / Storageをリセットしない。

### Google Cloud

現行実装はSupabase `signInWithOAuth` と外部ブラウザ。ネイティブGoogle SDKは使用しない。
Google Auth Platform → Branding のApp nameをSETKEEPへ変更。実在するサポート・公開URLは維持する。
Clients → Supabaseで使用中のWeb OAuthクライアントの承認済みredirect URIは、同じプロジェクトの `https://<project-ref>.supabase.co/auth/v1/callback` のまま。
`setkeep://login-callback/` はGoogle Web clientでなくSupabase側の許可URLへ設定する。
既存Android/iOSネイティブOAuthクライアントを別途使っている場合に限り、Android package `com.setkeep.app` と実際の署名SHA-1/SHA-256、iOS bundle `com.setkeep.app` のクライアントを作る。現在のブラウザOAuthのためにSDKや秘密鍵を追加する必要はない。

### Apple Developer / Xcode

Certificates, Identifiers & Profiles → Identifiers → + → App IDs → Explicitにて `com.setkeep.app` と `com.setkeep.app.RestTimerWidget` を登録。
Xcode → Runner / RestTimerWidget → Signing & Capabilitiesで既存Teamを選択し、新ID用のDevelopment/Distribution Profileを生成・選択する。証明書・秘密鍵そのものは作り直していない。
App Store Connect → My Apps → + → New AppではSETKEEPと新Bundle IDを選ぶ。旧IDのストアアプリの単なる更新として扱わない。
Appleログインは現行アプリに未実装。今回は追加していない。将来導入時は新App IDのSign in with Apple capability、対応Services ID、Supabase Apple Providerのclient IDとcallbackを同時設定する。未使用のcapabilityを今回有効化しない。
Live Activitiesは `NSSupportsLiveActivities` とWidget extensionの構成を維持。App Group登録は現在不要。

### GitHub

リポジトリはSETKEEP用Organizationへ移管済み。Macの開発用remoteは次を使用する：

```
git remote set-url origin https://github.com/setkeep/setkeep.git
```

移管後も既存commit履歴と `main` を維持。新規cloneやCodex連携ではこのURLを使用する。

### ビルド環境・ストア・アイコン

- signing環境変数は `SETKEEP_SIGNING_PROPERTIES`（旧変数も互換読込）。署名ファイル・鍵は変更しない。
- Supabase設定ファイル指定は `SETKEEP_SUPABASE_CONFIG`（旧変数も互換読込）。`supabase.json` はGit管理外を維持。
- Play Consoleは新packageのアプリとして登録。旧packageの更新版にはならない。実在しないストアURLは追加しない。
- アイコンは現状Flutter標準。新アセット差し替え待ち：`android/app/src/main/res/mipmap-*/ic_launcher.png`、`ios/Runner/Assets.xcassets/AppIcon.appiconset/`、`macos/Runner/Assets.xcassets/AppIcon.appiconset/`、`web/icons/`、`web/favicon.png`、`windows/runner/resources/app_icon.ico`。
- SplashのLaunchImageは既存の無地アセットを維持。共有画像のブランド文字はFlutter描画でSETKEEPへ変更済み。
- `.github` / fastlaneの既存CIはなし。`.vscode`、ビルドスクリプト、QA用scriptとpackage importsは更新。

## 公式資料

- [Supabase Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
- [Supabase Google OAuth](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Apple App ID登録](https://developer.apple.com/help/account/identifiers/register-an-app-id)
- [GitHub repository rename](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository)

## 残存名称

[旧名称の全件監査](setkeep_legacy_references.tsv) にファイル・行・理由を記録。生成済み・無視対象のbuildキャッシュはソース監査対象外。workspaceディレクトリとGit remoteは実在パスとして維持。

## 実行結果

- `flutter pub get`: 成功。依存バージョンの追加更新なし。
- `flutter analyze --no-pub`: No issues found。
- `flutter test --no-pub --concurrency=2`: 全263件成功。
- `flutter test --no-pub test/setkeep_brand_test.dart`: 旧backup v1〜v3、native識別子・channel、旧/新QRの3件成功。
- `python3 -m unittest tool.test_build_android_beta tool.exercise_forms.tests.test_qa_mode_wrapper`: 12件成功。
- 変更したPython生成ツール: `py_compile` 成功。3D再生成は行っていない。
- `flutter build apk --debug --dart-define-from-file=supabase.json`: 成功。エミュレーターへcom.setkeep.appとしてインストール・起動し、SETKEEP画面とcallback解決先を確認。
- `flutter test --no-pub integration_test/rest_set_action_test.dart -d emulator-5554`: 7件成功。初回は新アプリの通知権限未許可で3件失敗し、QA端末で許可後に全件成功。ホスト連動オプションなしのため、そのオプション専用ケースの物理ロック操作は実行対象外。
- `flutter build ios --simulator --debug --dart-define-from-file=supabase.json`: 本体・RestTimerWidgetとも成功。bundle IDをビルド済みInfo.plistでも検証。
- `flutter test --no-pub integration_test/rest_lock_screen_test.dart -d 0B986FD3-05C1-4ECF-8CA8-035433154498`: 2件成功。新アプリの通知許可をQA端末で承認。Live Activity件数、停止・再開、期限終了・通知処理を確認。
- iOS simulatorへcom.setkeep.appをインストール・起動しSETKEEP画面と新scheme起動を確認。
- `plutil -lint`: Runner / Widget Info.plist、Xcode projectすべて成功。
- `git diff --check`: 成功。

### 未確認・外部残件

- 実Galaxy/iPhoneへのインストールと物理ロック画面、Dynamic Islandの実機目視は未実施。
- 実機用Apple署名・Provisioning Profileは新IDの登録が必要。simulatorビルド成功を実機署名成功とは扱わない。
- 実プロジェクトのSupabase configをread-onlyで比較し、現在remoteのcallback許可リストは旧schemeのみであることを確認。SETKEEPでGoogleログインを完結する前に新callbackを追加する必要がある。remoteへのconfig全体の上書きは未実施。
- Googleへの実ログイン、Googleブランド表示、Apple Developer登録、ストア登録、GitHub renameは未実施。
- 新ロゴ・アイコンは確定デザイン待ち。旧ブランド入りロゴではなく現状のFlutter標準アイコンを維持。
- 新IDは別アプリ。旧アプリを削除する前のデータ書き出し・復元と再ログインが必要。
- 旧名称残存の99行はすべて理由を付して別TSVへ記録。新アプリのユーザー向け表示に旧ブランド文字は残していない。
- commit / pushなし。旧アプリ・旧データ・旧3D成果物を削除していない。
