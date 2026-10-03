# フレンドMVP検証

実装: ホーム下部カード、友達の詳細と既存3Dヒートマップ、招待コード申請/受信者承認/解除、非公開初期値/友達限定公開、1人1いいね、140字コメントと本人取消。既存記録・同期のテーブルとPremiumゲートは変更していない。スプラッシュ変更なし。

検証:
- `flutter analyze`: 全体解析 No issues found（TRAINER子パッケージpub get後）。
- `flutter test`: 411テスト通過。分離チェックアウトに既存のGit非管理ローカル動画素材をコピーして検証。初回の素材不足による4件失敗は再実行で解消。
- `test/friends_mvp_test.dart`: 詳細遷移、いいね切替、コメント作成削除、アクセス失敗時の表示クリア、非公開初期値、受信申請承認、解除、文字数境界。
- 一時ローカルPostgreSQL 17へ専用migration適用、`supabase/tests/friends_mvp.sql` 通過。未承認/他人/非公開/匿名の拒否、本人限定リアクション、重複いいね拒否、コメント長さ、他人の設定変更拒否、解除即時失効、元記録編集反映・ID/リアクション保持、削除cascade。
- `git diff --check` 通過。

未確認: iOS/Android実機、Supabase実環境で2ユーザー連携、オフライン復帰。ローカルDBはauth.uid/Auth users/anon/authenticatedを模擬した構成。実環境の他migrationやサービス設定を含む検証はリリース前に必要。本番DB変更、merge、deployは実行していない。DB適用/影響/ロールバック方針は `docs/friends_mvp.md`。
