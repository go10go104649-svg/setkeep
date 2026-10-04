# 普段の開発フォルダへのSNS写真調整統合

ユーザー承認により `/Users/macintosh/Documents/Codex/muscle_memory` へ b625030 のSNS差分だけを統合。ブランチは `fix/sns-photo-position`。フレンド機能、remote main merge、本番DB変更は含めない。

元の未コミット8ファイルとQA文書を `/Users/macintosh/Documents/Codex/2026-10-04/task/backups/sns-integration-2026-10-04` に保護保存。写真差分のみstageし、main.dart内の既存起動/preload修正とスプラッシュ・広告等をunstagedのまま維持。写真差分のcommitへ無関係変更を混ぜない。元の非main変更は全ファイルhash一致、mainの既存WorkoutPage起動ブロックも一致。

検証: `flutter analyze lib test` No issues found、関連115テスト通過、`flutter build apk --debug --dart-define-from-file=supabase.json` 成功、`git diff --check` 通過。ソースはGalaxy実機確認済みのSNS単独導入版と一致。端末再インストールは不要なため行っていない。

VSCodeのlaunch設定は変更していない。同じ普段のフォルダから通常のSETKEEPタスクを起動すれば写真修正を含む。既存の起動・広告変更は未コミットなので、他のブランチへ切り替える前にその作業状態を保護する。リモートmainは更新していない。
