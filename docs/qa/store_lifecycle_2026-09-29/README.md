# 店舗営業状態・店舗報告 QA（2026-09-29）

## 基準・適用

- 正式リポジトリ: `setkeep/setkeep`。開始時 main は `0292d4c33a53ffc01b34fdffe12dc18c76c52184`、clean。
- 開始時にfetch・fast-forwardを確認。commit前にもorigin/mainと一致。
- アプリのSupabase URLとCLI linked projectが一致することを、秘密情報を表示せず検証。
- 本番linked DBに以下を適用済み。既存migrationは変更していない。
  - `202609290028_gym_store_lifecycle.sql`: status、店舗報告、既存Candidate/Applicationの一般化、RLS、監査、UI用view。
  - `202609290029_gym_store_candidate_lock_order.sql`: 新店舗報告と管理者操作のロック順を統一。028適用後の改善を追加migrationとして反映。
- commit SHA・push結果は本作業の完了報告と、この文書を追加したGit commitを参照。

## status / active / 既存データ

| operational_status | activeとの関係 | 検索 | 新しい利用場所への選択 |
|---|---|---|---|
| active | true | 表示 | 可 |
| preopening | true | オープン準備中 | 不可 |
| temporarily_closed | true | 一時休業中 | 不可 |
| closed | false | 通常検索から除外、既登録から参照可 | 不可 |
| unknown | 元activeを維持 | activeに従う | 不可 |

- `active`は削除しない。従来のactiveのみの更新にも互換triggerを設けた。
- `source.page_status=preopening_text`を優先して移行。inactiveだけで永久閉店とは推測しない。
- 移行結果: active **2,657**、preopening **39**、unknown/inactive **3**、計 **2,699**。
- 営業状態の出典は `status_source_kind / status_checked_at / status_source_url / status_source_data`。
  既存店舗はimportとして出典を保持し、設備の確認日から「最近の公式営業確認」を推測しない。
- 既存店舗の従来カラム、設備2,604件、店舗設備9,513件、登録店舗4件、workouts12件の全行JSONハッシュが前後で一致。
  ID・名称・住所・設備・登録・過去記録を削除/改変していない。status新規カラムは店舗のハッシュ比較から除外。
- テストはtransaction/rollbackで実施。QA店舗は0件残存。

## Report → Evidence → Candidate

- 新規 `gym_store_reports`: user/store/chain、ブランド原文、kind、提案名称・所在地・公式URL・source ID、コメント、status、管理者メモ・確認者・日時。
- kind: temporarily_closed / reopened / closed / new_store / relocated / wrong_name / wrong_address / other。
- `gym_change_candidates` / `gym_change_evidence` / `gym_auto_rule_config` / `gym_auto_decisions`を再利用。
  設備は `entity_type=store_equipment`、店舗は `entity_type=store`。
- change_typeは `store_` prefixで設備のwrong_name/other等と分離。
  store_id=NULLは新店舗候補だけ、店舗候補のequipment_idはNULL。
- 同一店舗・同種のopen候補へ集約。1人の最新Evidenceのみを投票に使用。
  user_reportの重みはサーバー固定1。クライアントから票数、出典種別、管理者状態は渡せない。
- 5分あたり5件まで。同じユーザー・店舗・kindで未処理または直近5分の重複を拒否。
- Evidenceの投票窓は7日。古いEvidence自体は削除しない。期限切れだけで店舗は営業再開しない。
- 新報告時と既存の再評価関数実行時に判定する。定期巡回・新規cronは追加していない。
  cooldown経過だけで勝手に再開せず、次の評価でも有効なEvidenceを要求する。

## 判定・安全条件

| 変更 | 判定 |
|---|---|
| 一時休業 | active店舗で7日以内の異なる3人、支持3以上、反対なし → 自動反映 |
| 営業再開 | temporarily_closed店舗で7日以内の異なる2人、支持2以上、反対なし → 自動反映 |
| activeへの再開 | supersededで解決、Master更新なし |
| closedへの再開 | 管理者確認、ユーザー票だけでは復活しない |
| 永久閉店 | 人数に関わらずneeds_review、管理者の根拠入力付き手動適用のみ |
| 新店舗 | needs_review、gym_storesへ自動INSERTしない |
| 移転・名称・住所・その他 | needs_review、Master自動変更なし |

- 一時休業と再開の反対方向、永久閉店の最近のEvidenceが競合すれば確認へ送る。
- recent official/admin/gym_staffの状態確認と反対Evidenceを14日保護。
  一般ユーザーが公式URLを入力しただけではofficialに昇格しない。
- 店舗の反映・rollbackから7日間のcooldown。操作種別をまたいだ自動反転も抑制。
- 適用直前に店舗単位のlock内で再評価。古いauto_readyを無条件で適用しない。
- 新店舗はchain＋NFKC正規化名称＋所在地、同じchainの公式URLから候補を集約。
  既存店舗のsource ID/URL/住所/同chainの近似名称は「既存店舗の可能性」として提案に保持する。
  類似名称を根拠に既存Masterへ統合・上書きしない。各報告の原文もEvidenceに残る。

## 適用・監査・rollback

- `gym_auto_applications`を再利用し、店舗の場合だけequipment_id=NULLを許可。
  before/afterは店舗の全行JSON。設備用change_type/制約は維持。
- `gym_store_changes`にMaster更新のbefore/after、candidate/application、操作者・日時を追記。
- 管理者の「確認した店舗状態を反映」は確認ダイアログ＋根拠必須。
  closed/temp/reopenに対応し、admin Evidence・decision・出典メタデータを同一transactionで保存。
- rollbackは管理者・理由必須。現在Masterが適用時afterと一致する場合のみbeforeのstatus/active/出典を正確に復元。
  その後の住所変更等があれば拒否し、新しい情報を上書きしない。rollback自体も監査・decisionを記録。
- 報告の確認開始/反映/却下をreviewing/applied/rejectedへ同期。却下理由はDBとUI双方で必須。

## 一般版UI / 管理者UI

- 店舗詳細に「店舗情報を報告」。一般ユーザー画面へ内部スコア等は出さない。
- 店舗検索のスクロール領域に「掲載されていない店舗を報告」。手動の個人用場所登録とは別導線。
- 検索・登録済み一覧・詳細で営業状態を表示。休業・閉店になっても登録を消さず設備詳細を参照できる。
- 新規登録と新しいトレーニング場所はactiveのみ。DB側も利用不可店舗への新規登録を拒否。
- 「いつもの場所」が休業等なら設定は保持し、その回は自宅へfallbackして警告を表示。
  再開後は同じ設定から復帰。登録解除や存在しないIDの従来のfallbackは維持。
- 通信失敗時は設定を消さない。取得できない旨を警告する。履歴編集・既存WorkoutRecordを変換しない。
- 管理画面に「店舗情報」を追加。候補状態/種別/スコア/人数/現状/提案/first-last seen/Evidence件数を一覧・詳細に表示。
  詳細で競合・保護理由、元報告、重複候補、確認開始、手動適用、理由付き却下、rollbackを扱う。
- 設備用の候補は従来の「変更候補」に分離。元の報告送信・設備判定は維持。

## RLS

- 一般ユーザー: 自分の店舗報告INSERTのみ。入力カラムだけINSERT権限を付与。
  user_id=auth.uid()、status=pending。報告SELECTは管理者限定policy。
- 一般ユーザーからMaster/Candidate/Evidence/Rules/Applications/Decisions/Auditを変更できない。
- 管理者のみ報告/Evidence/監査を参照。状態変更はadminチェック付きRPC。
- private判定/適用関数はPUBLIC/anon/authenticatedからEXECUTE revoke。
  既存設備の判定・適用・rollback実装はそのまま残し、entity別dispatcherを介して再利用。

## 検証

- 本番linked DBのrollbackテスト **11本成功**:
  `gym_store_lifecycle`、`gym_change_candidates`、`gym_auto_application`、
  `gym_equipment_state_reports`、`canonical_equipment`、`gym_equipment`、
  `gym_multi_equipment_rules`、`gym_places_details`、`private_place_equipment`、
  `report_admin`、`gym_search_chain_names`。
- 店舗SQLは3人休業、2人再開、cooldown、永久閉店非自動、管理者閉店/rollback、反対Evidence、
  official保護、同一人10回重複、古い票、preopening検索、無効入力、登録制限、RLS、
  新店舗集約/重複候補/非INSERT、移転非変更、新しいMasterを守るrollback拒否を確認。
- Flutter全体: `flutter test --no-pub --concurrency=2` **363件成功**。
  その後、報告入口をスクロール領域へ配置し、小画面キーボードテスト2件を追加して関連6ファイル **57件成功**。
- Android/iOSのThemeと小画面・viewInsetsで店舗検索/報告/選択制限をWidget test。
  いつもの場所保持、再開後復帰、送信失敗/再試行、新店舗と手動登録の分離、管理者操作を検証。
- `flutter analyze --no-pub`: **No issues found**。`git diff --check`: **成功**。

## 変更ファイル

- `supabase/migrations/202609290028_gym_store_lifecycle.sql`
- `supabase/migrations/202609290029_gym_store_candidate_lock_order.sql`
- `supabase/tests/gym_store_lifecycle.sql`
- `lib/gym/gym_repository.dart`
- `lib/gym/gym_pages.dart`
- `lib/gym/store_report_sheet.dart`
- `lib/gym/training_place_preference.dart`
- `lib/admin/report_repository.dart`
- `lib/admin/report_management_page.dart`
- `lib/main.dart`（新規開始時の場所警告のみ）
- `test/store_lifecycle_test.dart`
- `test/report_management_test.dart`
- `test/training_place_test.dart`
- `docs/current_spec.md`
- 本文書

## 未対応・確認範囲

- 今回のGalaxy/iPhone実機、Simulator/Emulatorでの手操作、アプリ配布・インストールは未実施。
  DBへの適用、SQL権限検証、Flutter Widgetテストと実機確認は区別する。新UIには更新ビルドが必要。
- 公式巡回、Maps/SNS監視、新店舗自動作成、永久閉店のユーザー票自動確定、移転自動変更、ユーザー信頼度計算は対象外。
- 新店舗・移転・名称/住所は確認/却下/根拠閲覧まで。管理画面からMasterを直接作成・書き換える画面は追加していない。
  今回の手動適用対象は店舗営業状態。その他のMaster修正は既存の管理・migration手順で行う。

**店舗の一時休業・営業再開は閾値・競合・出典保護・cooldown付きで自動管理し、永久閉店・新店舗・移転など影響の大きい変更は管理者確認へ送る。**
