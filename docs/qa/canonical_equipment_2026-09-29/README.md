# 設備共通知識 QA / 本番反映（2026-09-29）

## 基準・適用

- リポジトリ `setkeep/setkeep`、作業開始main `5f9cb7ec88160daa49988236dfee733887ab3e27`。
- mainをfetchし開始時cleanを確認。commit直前にもorigin/mainとの一致を確認。
- CLIのlinked本番DBに025 / 026 / 027を適用済み。
- `202609290025_canonical_equipment.sql`: 共通知識、読取RPC、初回レビュー済み所属。
- `202609290026_canonical_dumbbell_upper_range.sql`: 最終監査で上限重量だけのFIT-EASYダンベル2件を追加。
- `202609290027_canonical_dumbbell_requirements.sql`: 既存ダンベルdirectのベンチ必須種目を、元行を残して必要設備条件へ通す。
  適用済みmigrationは変更せず、追加migrationで反映した。

## 構造とマッピング

- canonical_equipment（共通概念）、canonical_equipment_matchers（レビュー署名）、
  equipment_canonical_mapping（承認）、canonical_equipment_exercise_mapping（単体種目）、
  canonical_equipment_rules / canonical_equipment_rule_items（複合条件）。全6表RLS参照専用。
- 共通概念57、846設備IDに916所属、単体知識80、複合ルール36 / 条件76。
- 完全一致署名は正規化名称・normalized_name・カテゴリ・load_type・メーカー・型番。
  負荷方式の区別が必要な一般名は既存directのレビューも要求する。名前が似ているだけでは承認しない。
- ダンベル単体15種目。肩プレス・ベンチプレス・フライ等はベンチ能力に応じた複合条件。
  可変・メーカー・重量レンジ表記も審査した。重量や出典の元データは維持。
- バーベル＋ラック、さらにフラット/インクライン/デクライン対応ベンチ等を組み合わせる。
  ラックだけからバーベル、普通のアジャスタブルベンチからデクラインを推定しない。
- スミス、EZバー、カール台、チン/ディップ台、明確な脚/股関節/胸/肩/腕/腹部マシン、
  明示的なプレートロード、有酸素も共通知識化。デュアルプーリーと固定クロスは別概念。
- bareプルダウン、負荷方式不明のショルダープレス、ダンベルラック/エリア/混合設備行、
  不明な固有名等は未確定。前脛骨筋マシンは設備特定済み・種目マスター未収録として別理由。
- 直接＋canonical単体＋旧複合＋canonical複合を統合。Evidenceは元設備名。
  同じ種目はUIで重複表示しない。共有店舗とprivate placeは同じ評価器を使用。

## Before / After

設置実績のあるdistinct equipment IDをチェーンごとに計測。同一IDの複数チェーン利用は両方に数える。
directとmultiは重なる。「未設定」は単体も複合知識もない設備数であり、実店舗の利用可能種目数ではない。

| チェーン | 設置equipment | direct | 旧multi | 未設定 Before → After | canonical | 元needs_review |
|---|---:|---:|---:|---:|---:|---:|
| FIT PLACE24 | 219 | 205 | 14 | 4 → 4 | 85 | 12 |
| KANEKIN FITNESS GYM | 37 | 32 | 7 | 1 → 1 | 17 | 0 |
| AUN'S GYM | 62 | 28 | 4 | 33 → 23 | 33 | 6 |
| FASTGYM24 | 94 | 42 | 5 | 50 → 31 | 51 | 5 |
| FIT-EASY | 18 | 10 | 1 | 8 → 5 | 10 | 2 |
| FiT24 | 115 | 30 | 6 | 82 → 69 | 40 | 4 |
| GOLD'S GYM | 53 | 20 | 4 | 31 → 26 | 23 | 2 |
| HYPER FIT24 | 176 | 53 | 6 | 121 → 101 | 52 | 4 |
| JOYFIT24 | 271 | 55 | 6 | 213 → 162 | 89 | 6 |
| JOYFIT24 LITE | 0 | 0 | 0 | 0 → 0 | 0 | 0 |
| SMART FIT100 | 37 | 23 | 0 | 14 → 8 | 26 | 2 |
| WORLD+GYM | 63 | 22 | 3 | 39 → 32 | 28 | 7 |
| エニタイムフィットネス | 662 | 63 | 4 | 597 → 490 | 153 | 537 |

- 設備マスター全2,604件の未設定: **1,183 → 947**（236件改善）。
- 現在設置されているdistinct設備1,682件の未設定残数: **905**。
- 全マスターで単体対応0件: **1049**。うち複合条件部品を含むため、全件「未対応」とは扱わない。
- source由来needs_review: **632件**（設置実績あり587件）。既存フラグは変更していない。
  明確に確認できたcanonical所属と元の要調査フラグは別に管理する。
- 詳細: [Before coverage](before/coverage.csv)、[After coverage](after/coverage.csv)、
  [未解決・複合条件部品一覧](after/unresolved.csv)、[今回の所属レビュー](approved.csv)。
  CSVはメーカー/型番/利用店舗数/raw_name/未対応理由を含み、設置先なしのマスターも含む。

## 本番実データ確認

- 馬橋店: 店舗対応種目**87件**。ダンベル単体15件。
  `flat_dumbbell_press`、`incline_dumbbell_press`、`dumbbell_fly`は
  「ダンベル ＋ アジャスタブルベンチ」の実在設備Evidenceで取得。
- FIT PLACE24、Anytime、GOLD'S GYM、JOYFIT24を含むダンベル設置済み**12チェーン**で
  共通基本15種目が一致。JOYFIT24 LITEは店舗設備登録0件であり、設備を推測して補完していない。
- 馬橋のレビュー済み12マッピングは維持。曖昧なプルダウン・フリーウェイト区分のショルダーは未推定。
- equipment / gym_stores / gym_store_equipment / direct / 旧rules / 旧itemsの
  全行JSONのハッシュが適用前後で一致。ID、原文、出典、数量、旧マッピングを削除・変更していない。
- 現行の店舗詳細RPCに反映済み。既存アプリでも設備情報をオンライン再取得すれば反映される。
  ページ取得経路のRPC統一は今回のFlutter変更を含むアプリ更新で反映される。

## テストと未確認範囲

- Python分類・安全条件・seed再現性: **7件成功**。
- Flutter関連6ファイル＋新規canonicalテスト: **43件成功**。
- `flutter test --no-pub --concurrency=2`: **355件全成功**。
- `flutter analyze --no-pub`: **No issues found**。
- SQL11本成功: canonical_equipment / anytime_mabashi_equipment_mappings /
  gym_multi_equipment_rules / private_place_equipment / gym_chain_store_catalog /
  gym_equipment / gym_places_details / gym_change_candidates / gym_auto_application /
  gym_equipment_state_reports / report_admin。
- SQLは本番linked DBのrollback fixtureで検証。RLSの一般ユーザー参照・更新拒否、
  候補だけでは未承認、カテゴリ/負荷変更で失効、複合条件不足、重複排除、撤去/利用不可を確認。
- UI regression: 店舗検索・登録・設備詳細・一括追加・店舗フィルター・報告・private place。
  Android/iOSのWidgetテーマ、小さい画面でcanonical由来の種目表示と一括追加を確認。
- **今回Galaxy実機/iPhone実機/Simulator操作は未実施**。実データRPC検証とWidget Testを実機確認とは扱わない。
  デバイス上では店舗情報を再読み込みし、ダンベル一覧・フィルター・追加を最終確認する。

## 運用・残課題

新チェーンは既存equipmentをインポート後、候補を生成し、source/raw_name等をレビューして
新規migrationで承認する。[再実行可能な手順](../../../tool/equipment_canonical/README.md)を参照。
曖昧な設備の仕様確認、未収録種目、混合設備原文の分離は今後のレビュー対象。

**通常ダンベルのように明確に同一と確認できた設備が、チェーンの違いだけで
「対応種目は現在準備中です」になる問題は、本番DBの共通知識・読取RPCで解消済み。**

## 変更ファイル

- `docs/current_spec.md`
- `docs/qa/canonical_equipment_2026-09-29/README.md`
- `docs/qa/canonical_equipment_2026-09-29/after/coverage.csv`
- `docs/qa/canonical_equipment_2026-09-29/after/unresolved.csv`
- `docs/qa/canonical_equipment_2026-09-29/approved.csv`
- `docs/qa/canonical_equipment_2026-09-29/before/coverage.csv`
- `lib/gym/gym_repository.dart`
- `supabase/migrations/202609290025_canonical_equipment.sql`
- `supabase/migrations/202609290026_canonical_dumbbell_upper_range.sql`
- `supabase/migrations/202609290027_canonical_dumbbell_requirements.sql`
- `supabase/tests/canonical_equipment.sql`
- `test/canonical_equipment_test.dart`
- `tool/equipment_canonical/README.md`
- `tool/equipment_canonical/audit.py`
- `tool/equipment_canonical/build_seed.py`
- `tool/equipment_canonical/knowledge.py`
- `tool/equipment_canonical/snapshot.sql`
- `tool/equipment_canonical/test_knowledge.py`
- `tool/equipment_canonical/verify.sql`

`git diff --check` / staged diff check成功。commit SHAとpush結果は作業完了報告を参照。
