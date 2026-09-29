# トレーニング後の任意設備確認（2026-09-29）

開始main: `0762968f6e2f9d8a30dac655a0225125b8b306d6`。commit / pushは行わない。

## 仕様

- 新規トレーニングのローカル保存とactive draft削除の後にだけ確認する。
  DB店舗・有効値を持つ完了セット・既知の標準種目IDが必要。
  予定、未完了セット、名前だけの旧記録、独自種目、手動場所、自宅、TRAINER代理記録は対象外。
- 認証済みユーザーだけ候補を取得。店舗に既存の設備（レビュー済みcanonical同等設備を含む）、
  または本人が有効期間内に確認済みの設備は再質問しない。
  同じ選択肢の組み合わせは一度だけ表示する。
- 選択肢は未選択で開始。1つだけでも本人確認を要求する。
  複数候補は使用設備を選択し、「その他 / 判定しない」も選べる。
  既存設備と新規設備が混在する選択肢では、既存設備を選ぶこともできるが票は送らない。
- **スキップ・Back・シート外タップ・下スワイプで閉じる場合は票を送らない。**
  通常の完了ダイアログへ進み、保存済みトレーニングは維持する。
  通信失敗/候補なし/全候補既知の場合は確認画面そのものを省略。
- 写真/自由記述は要求しない。既存の設備報告・撤去報告・管理画面は補完導線として維持。

## 逆引きと確定条件

`gym_training_equipment_rules`にレビュー済みの逆引きを明示する。
既存の設備→種目many-to-manyを機械的に反転しない。
初期値は78種目ID / 105対応 / 7設備ID。種目カタログの明示器具仕様に基づく。

| 参照設備 | 既存equipment ID |
|---|---|
| スミスマシン | fit-place24:fp_eq_74ae16617af0 |
| ダンベル | hyper-fit24:fp_eq_e2f3c2ba7ec7 |
| バーベル | golds-gym:fp_eq_7b69e5784787 |
| ケーブルクロスオーバー | fit-place24:fp_eq_4740a3f1901c |
| デュアルアジャスタブルプーリー | fit-place24:fp_eq_b333827ebb7e |
| シーテッドラテラルレイズ | fit-place24:fp_eq_df0b02e63072 |
| スタンディングラテラルレイズ | fit-place24:fp_eq_1caec5a7c3b6 |

チェーン接頭辞は既存IDの由来であり、そのチェーンだけで使用するという意味ではない。
メーカー/型番を推測しない汎用設備IDを再利用。設備マスター自体の名前・出典は変更しない。
ダンベル種目からベンチやラックを推定しない。ケーブル種類等は選択式。
曖昧なフリーウェイト種目は複数選択肢か対象外にし、未知の器具を強制しない。

既存`gym_auto_rule_config`のadded設定を再利用:
**30日内・独立ユーザー3人・支持3・反対0、cooldown 7日**。
単独ユーザー/端末内繰り返しは1票。公式review hold、競合、未同定、needs_reviewなどの既存安全条件も維持。
初期閾値は既存の追加設備ルールと一致させ、履歴由来だけを緩く扱わない。
確定時は既存Candidate→判定→適用→監査/rollbackを利用する。
追加設備は「この店舗でできる」の既存canonical/mapping/複合設備ルールで評価される。

## DB・保存・プライバシー

- 新規migration032。既存migrationは編集しない。
- private confirmations: **user × store × equipment**を主キーにUPSERT。
  最新の本人確認exercise_idとローカル記録キー、active、first/last_seenを持つ。
- Evidenceも同じ組み合わせ1行を更新。候補はstore × equipmentで集約。
  `training_confirmation`は公式情報/従来報告と区別する。
- `gym_training_equipment_summary`は管理者専用で有効票数/独立人数/期間/statusを表示。
  evidence_countは有効な本人確認数であり、実施したトレーニング総回数ではない。
- 一般ユーザーは本人の確認行だけSELECT可能。書込みはauth.uid一致を検証するRPCのみ。
  クライアントから候補/status/Masterを直接更新できない。
- ローカルjournalで同意を先に保存。通信失敗は再起動・復帰・認証・履歴変更で再送。
  削除/編集で該当する完了種目がなくなった場合は票を無効化、Undoで同意を復元。
  別端末の古い削除は新しい記録キーの票を無効にしない。
- 確定済み設備は履歴削除や利用実績の経過だけで撤去しない。
- 個人の重量/回数/セット/履歴本体を新テーブルに複製しない。
  ローカル日付キーは重複/撤回照合に使う非公開識別子。公開店舗データには人物・来店情報を含めない。
- Premiumクラウドバックアップは有効化しない。**サーバーは端末内履歴を独立検証できない**。
  正規アプリの保存済み完了記録からの本人確認＋独立ユーザー集約を根拠とし、実来店の証明とは扱わない。

## 既存データの維持

カネキン松戸、FIT PLACE24南柏・市川・新松戸・松戸駅前を含め、既存Masterを移行/削除/出典付替えしない。
既存データはそのまま使い、今回のユーザー確認済み票として取り込み直さない。
全Masterと指定店舗の適用前後の件数/全行hashを照合する。

公式取得基盤（migration030/031、Edge、parser、scheduler）は存在するが、
**全体設定false・enabled source 0・Cron falseのまま**。新規/定期の公式サイトアクセスなし。

## 検証結果

- `flutter analyze --no-pub`: No issues found。
- `flutter test --no-pub`: 全382テスト成功（追加11テストを含む）。
- `git diff --check`: 成功。

- migration032はlinked本番DB適用済み。CLI `db push --dry-run`は一時DBロール認証で失敗。
  認証済み`supabase db query --linked`経由で031が最新であることを検査し、
  DDL＋migration履歴032を同一transactionで適用した。DBパスワード変更/再取得はしていない。
- migrationを一時適用してrollbackする関連SQL14ファイルすべて成功。
  本番適用後も新規SQLテストを再実行して成功（テストデータはrollback）。
  独立3人/同一ユーザー重複/期限切れ/撤回/Undo/匿名・他ユーザー権限/既存設備を検証。
- 全行hash照合: 店舗2,699、設備2,604、店舗設備9,513、direct mapping2,507、
  複合ルール1,117、canonical membership916。全6系統が適用前後一致。
- 指定店舗の設備件数と内容も一致:
  カネキン松戸37、FIT PLACE南柏47・市川52・新松戸33・松戸駅前49。
  松戸六高台0も変更なし。公式取得の全停止を再確認。
- 78種目の逆引きIDが全て現行カタログに存在することを検査。
- Android/iOS TargetPlatformで320×568のシート表示をWidgetテスト。
  実機/Simulatorでの操作・インストールは未実施。
- 件数/hash/適用後設定は[results.json](results.json)に記録。

## 今回の制限・実機確認

- 未登録の逆引き種目は確認対象外。設備種類を推測して広げない。
- 候補取得時にオフラインなら任意確認を省略（本人確認していない票を後から自動作成しない）。
- 撤回後の候補票数は更新するが、過去の確定監査時点の人数はそのまま保持する。
- 管理者が却下/rollbackした組み合わせを新しい履歴だけで再開しない。
- Android/iOS実機では、保存後の任意シート、スキップ/Back/スワイプ、復帰・オフライン再送、
  履歴削除/Undo、確定後の設備詳細/フィルターを確認する。

## 変更ファイル

- `lib/main.dart`: 保存後の任意確認、全保存履歴からの同意照合、復帰/履歴変更時の再送。
- `lib/gym/training_equipment_confirmation.dart`: 共通Repository、同意journal、任意シート。
- `lib/admin/report_management_page.dart`: training confirmationの出典表示。
- `supabase/migrations/202609290032_training_equipment_confirmation.sql`: 非公開確認、逆引き、RPC、既存候補/適用への統合。
- `supabase/tests/training_equipment_confirmation.sql`: 集約・閾値・権限・削除/Undo・期限・canonical既存設備。
- `test/training_equipment_confirmation_test.dart`: 完了条件・任意UI・保存順・全履歴照合・再送・両OS狭幅。
- `docs/current_spec.md`: 現行方針。
- 本QA文書と`results.json`。
