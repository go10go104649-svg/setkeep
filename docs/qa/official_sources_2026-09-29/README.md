# 公式情報取得基盤 / Anytime pilot QA — 2026-09-29

## 結論

コード・DB基盤・管理UI・Edge Functionを実装。本番migration030/031適用済み。
**利用条件未確認というユーザー回答に従い、Cron / 全体設定 / 取得先は無効。**
定期監視を開始していない。全国Anytimeを有効化できると判断する段階ではない。

開始main: `bb23c0cb9537848242d4680f8c2a83d0cc4cc90a`。
最新main取得・clean確認から開始。実装commitは
`git log --oneline --grep='official source monitoring'` で追跡可能。
秘密情報、取得ページHTML、ローカル一時生成物はGitに含めない。

## 実装

| 項目 | 内容 |
|---|---|
| Registry | 4店舗・5sourceを登録。URL/店舗/chain/parser/取得間隔/HTTP cache/各日時/利用条件/現在結果 |
| Snapshot | fetched_at、HTTP、content/semantic hash、抽出結果、diff、parser version、error、review |
| Fetcher | 明示UA、robots、HTTPSドメインallowlist、DNS/private IP拒否、redirect再検証、timeout、サイズ上限、Retry-After |
| Parser | Anytime店舗/設備の専用DOMを抽出。NFKC正規化、明示台数のみ、営業不明はunknown |
| Evidence | Official source→snapshot→既存Candidate→既存評価器。直接Master変更なし |
| Weight | change_type別official_weight=3、初期official_review_only=true。ユーザー数を水増ししない |
| Dedup | source+candidate一意。意味hash同一/304は再確認日時だけ更新。再評価なし |
| 掲載消失 | 差分のmissing_ignored。removed Evidenceは生成しない |
| 状態 | 一時休業/reopened/closedは既存店舗候補へ。閉店はreview、開業前/矛盾もreview |
| Version | 更新直後はcache条件を外して再解析。sourceの継続reviewフラグで適用抑止 |
| 同定 | raw_name→reviewed normalized→一意canonical→既存reuse情報→明確alias。曖昧なら未同定 |
| 管理 | 報告管理の地球アイコン→取得状態/URL/日時/エラー/正規化結果/直近10snapshot |
| 権限 | sources/snapshotsはadminのみ参照、クライアントから編集不可。再確認markはadmin RPC |
| 定期処理 | pg_cron+pg_net+Edge、毎分最大1source、個別最低24h。全停止状態 |
| Worker認証 | DB発行一回限り・5分期限token。一般ユーザーがjob作成/参照/実行する権限なし |

定期稼働を前提とするEdge JWT検証の代わりに、非公開のDB job capabilityで認証する。
任意URLを受け付けず、無効tokenはHTTPアクセス前に401。
runtimeのservice credentialは既存環境だけで利用。公開サイト用の新secretなし。

## 保存済みレスポンスによるdry-run

利用条件の確認待ちになった後は追加のサイト取得をせず、
確認時点ですでに取得していたレスポンスをローカル解析した。
**DBのEvidence/Candidate/Snapshotは作成していない。**

| 店舗 / ページ | Parser | 抽出設備 | 営業状態 |
|---|---|---:|---|
| 松戸馬橋 / 店舗 | 成功 | 0（設備列挙ページではない） | unknown |
| 松戸馬橋 / facility | 成功 | 45 | unknown |
| 新松戸7丁目 / 店舗 | 成功 | 0（facility未取得） | unknown |
| いわき小名浜 / 店舗 | 成功 | 0（既存DBでも設備非公開） | unknown |
| イオンタウン蕨 / 店舗 | 成功 | 0 | preopening |

- 4店舗5ページ、parser成功 **5/5（100%）**。
- この5レスポンスのHTTP404 **0**、parse error **0**。
  全国/長期間の成功率を示すものではない。
- 同じ5レスポンスへコメント/広告ノイズを追加した対照試験:
  semantic false diff **0/5**。自然な日次変化によるfalse diff率は未計測。
- 松戸馬橋設備同定 **43/45（95.6%）**、未同定 **2件**。
  同名「ショルダープレス」が別エリアにあり、既存raw_nameが複数IDに該当する。
  器具を推測して選ばない。既存設備/mappingは維持。
- 同定43件のうち既存needs_review=trueは **24件**。同定は承認ではなく、
  reviewを解除したり新mappingを作ったりしていない。
- 実際の公式Evidence / Candidate生成件数 **0**（dry-run + 定期無効）。
  合成fixtureによる生成/同定/競合/重複テストはtransaction rollbackで検証済み。
- 新松戸7丁目は既存DBの設備51件を持つ「豊富な店舗」枠だが、
  今回解析したのは店舗ページのみ。facilityのparser確認は未実施。
- 通常店舗は専用状態欄に明示がないためunknown。
  ページの存在やブランドの「24時間営業」文言だけから営業中を推測しない。

機械可読の集計・hash: [results.json](results.json)。
取得済みHTMLはローカル一時ファイルのみで、Git/DBには保存しない。

## 本番配置・データ不変

- migration `202609290030_gym_official_sources.sql` /
  `202609290031_gym_official_scheduler.sql`: linked本番DBへ適用成功。
- `gym-official-monitor`: API deploy成功。
- 無効capabilityで実際のEdge endpointへPOST: **401 Unauthorized**。
  任意URLを送っても公式ページ/送信URLへのfetchは行われない。
- sources **5**、enabled sources **0**、snapshots **0**、jobs **0**、
  global enabled **false**、Cron active **false**。
- 以下6系統の全行JSON集約hashが適用前後で一致:

| 対象 | 件数 |
|---|---:|
| gym_stores | 2,699 |
| equipment | 2,604 |
| gym_store_equipment | 9,513 |
| equipment_exercise_mapping | 2,507 |
| exercise_equipment_rules | 1,117 |
| equipment_canonical_memberships | 916 |

## テスト

- Backend Node **16/16成功**:
  quantity/weight区別、ノイズ/順序のsemantic hash、掲載消失と明示撤去、
  店舗状態/競合、構造変化、URL/DNS/redirect/robots/Retry-After、
  ETag/Last-Modified/304、失敗応答、利用条件未承認、
  parser更新時full fetch、サイズ上限、job認証、正常handler保存。
- 新規SQL **2ファイル成功**:
  `gym_official_sources.sql`、
  `gym_official_scheduler.sql`。
  同一内容の票数/再評価抑止、取得日時、追加/明示撤去/未掲載、
  閉店/休業/再開/公式競合、404/parse failure、未知設備、
  既知設備のversion hold、権限差、token一回性/期限、
  全停止時dispatchゼロをlinked DBで検証（rollback）。
- 既存SQL **11ファイル成功**:
  gym_change_candidates、gym_auto_application、gym_equipment_state_reports、
  gym_store_lifecycle、canonical_equipment、anytime_mabashi_equipment_mappings、
  gym_multi_equipment_rules、report_admin、gym_equipment、
  private_place_equipment、gym_places_details。
  公式oppositionは従来のconflicting_evidence判定を維持。
- 関連Flutter **57テスト成功**（9ファイル、追加の両OS狭幅確認を含む）:
  official_source_page、report_management、gym_integration、gym_details、
  gym_chain_filter、canonical_equipment、store_lifecycle、
  workout_gym、workout_draft_store。
- `flutter analyze --no-pub`: No issues found。
- `git diff --check`: 成功。
- Android/iOSはWidgetのTargetPlatform両方で320×568の管理画面を確認。
  実機/Simulator操作確認・アプリ配布は今回未実施。

## 残条件・運用判断

1. Anytime運営元の許諾/利用条件を確認する。未確認のまま有効化しない。
   [公式サイトポリシー](https://www.anytimefitness.co.jp/site/)、
   [robots](https://www.anytimefitness.co.jp/robots.txt)を別々に扱う。
   robotsの許可だけで情報利用が承認されたとはみなさない。
2. 許可後、豊富な設備ページを含めた追加サンプル・実際の状態表記・
   Edge→公式サイトの実通信を確認する。
3. 43件の同定にはreview対象も含む。曖昧設備の解消は今回行っていない。
4. 長期snapshot保存期間、運用アラート、source一覧拡大時の監視容量を決める。
5. parser変更hold解除やautomatic rule緩和は管理者の別判断。
   今回は全official observationをreviewに送る保守的な初期運用。
6. 全国追加、他チェーン展開、実機QAは未実施。
   [運用手順](../../../tool/official_sources/README.md)に再開条件を記載。

**公式サイト情報を直接Masterへ書かずEvidenceとして取り込む基盤は配置済み。
ただし、利用条件未確認のためAnytimeの定期監視は無効。全国監視開始可能・稼働済みとはしない。**

## 変更ファイル

- `docs/current_spec.md`
- `docs/qa/official_sources_2026-09-29/README.md`
- `docs/qa/official_sources_2026-09-29/results.json`
- `lib/admin/official_source_page.dart`
- `lib/admin/official_source_repository.dart`
- `lib/admin/report_management_page.dart`
- `supabase/config.toml`
- `supabase/functions/gym-official-monitor/fetcher.mjs`
- `supabase/functions/gym-official-monitor/handler.mjs`
- `supabase/functions/gym-official-monitor/index.ts`
- `supabase/functions/gym-official-monitor/monitor_test.mjs`
- `supabase/functions/gym-official-monitor/parser.mjs`
- `supabase/migrations/202609290030_gym_official_sources.sql`
- `supabase/migrations/202609290031_gym_official_scheduler.sql`
- `supabase/tests/gym_official_scheduler.sql`
- `supabase/tests/gym_official_sources.sql`
- `test/official_source_page_test.dart`
- `test/report_management_test.dart`
- `tool/official_sources/README.md`
- `tool/official_sources/dry_run.mjs`
