# 公式情報取得 — Anytime pilot

**現在は利用条件未確認。ユーザー指示により定期取得は無効。**
Cron、全体設定、取得先の3段階を無効にして配置する。
サイトポリシー確認前に以下の有効化手順を実行しない。

## 構成

- Edge Function: `supabase/functions/gym-official-monitor`
  - fetcher: HTTPS / DNS / robots / redirect / rate / response size
  - parser: ブランド別 registry。現在は Anytime の store / facility のみ。
  - handler: DBが発行した有効期限5分・一回限りのjob tokenを検証。
  - index: Supabase runtimeの既存service credentialで内部RPCを呼ぶ。
- migration030: sources / snapshots / snapshot-candidate link / private jobs /
  rule config / official evidence / 既存判定前のreview gate / admin RLS。
- migration031: Supabase Cron + pg_net。毎分最大1source、sourceごとに最低24時間。
  Flutter起動には依存しない。

HTTPは公式ドメインの登録済みURLだけ。任意URL入力APIではない。
公開サイト取得用の新しいsecretは不要。Edge→DBの既存service credentialは
サーバー環境のみ。ユーザー・管理者クライアントに渡さない。
job tokenはDB内の非公開テーブルとpg_net呼び出しにのみ存在し、
5分以内のclaim後は再利用不可、finishも一回限り。

## データと安全条件

sourcesはURL、chain/store、parser、取得間隔、HTTP状態、ETag、
Last-Modified、成功/変更日時、利用条件確認記録、現在の正規化結果を保持する。
snapshotは取得日時、HTTP、raw/semantic SHA256、抽出JSON（最大200KB）、
metadata（最大20KB）、parser version、差分、エラー、review要否を保持する。
HTML全文はDBに保存しない。snapshot→candidate→evidenceを追跡可能。

正規化結果例（正規マスターを書き換える形式ではない）:

```json
{
  "schema_version": 1,
  "store": {
    "name": "店舗名",
    "status": "unknown",
    "address": null,
    "official_url": "https://www.anytimefitness.co.jp/example/",
    "exists": true,
    "status_basis": ""
  },
  "equipment": [
    {
      "raw_name": "トレッドミル 3台",
      "normalized_name": "トレッドミル",
      "name": "トレッドミル",
      "area": "有酸素エリア",
      "quantity": 3,
      "explicit_removed": false
    }
  ],
  "equipment_listed": true,
  "facility_url": null
}
```

- 名前正規化は既存Anytime importerと同じNFKC・lowercase・空白除去。
- 専用DOM領域のみ読む。他店舗のお知らせ・footer広告から営業状態を推測しない。
  明示がなければ `unknown`。通常の「24時間営業」というサイト説明では
  `active` を確定しない。
- 台数は明記された「N台」だけ。ダンベル重量範囲から台数を推測しない。
- equipment同定は店舗raw_name → reviewed normalized_name → 一意canonical →
  importer保存済みreuse情報 → 明確なalias。一意でない場合はnullでreview。
  同定できても既存needs_reviewは解除しない。新equipmentを作らない。
- 掲載あり→added、明記された台数差→quantity_changed、
  明示的撤去→removed。不掲載だけならremovedを生成しない。
- 一時休業/reopened/closedは既存store Candidate、開業前/矛盾はstore_other。
  永久閉店、新店舗、移転を自動適用しない。
- 初期設定は全change_typeで `official_weight=3`、
  `official_review_only=true`。既存ユーザー報告の閾値は変更しない。
  公式Evidenceは独立ユーザー数として数えない。
- 同一source+candidateは一つのEvidence。意味hashが同じ/304なら
  直近の観測のobserved_atだけ再確認し、票を加算・大量再評価しない。
  observed_atは実際のfetch日時。ページ更新日は推測しない。
- freshな相反する公式観測はreview。過去の観測が保護期間内に残る場合も
  保守的にreviewへ送る（自動で片方を優先しない）。
- parser version変更時は条件付きGETを使わず再解析。
  sourceの `parser_review_required` を永続保持し、以後の差分もreview。
  コード更新だけで自動適用に切り替わらない。
- 404/403/429/5xx/timeout/parse errorはfetch error。
  連続404はsource_broken。設備撤去/店舗閉店にはしない。
- robotsが読めない/拒否/2秒超のcrawl-delay、外部redirect、private DNSなら中止。
  Retry-Afterが24時間より長ければ延期。CAPTCHA回避等はしない。
- snapshotは保持上限サイズあり。長期稼働前に保存期間・アーカイブ方針を決める。

## Dry-run（DBに書き込まない）

```sh
node tool/official_sources/dry_run.mjs /path/to/sources.json /path/to/result.json
```

sources.jsonは配列。登録済みsourceのurl/store_name/source_type/parser_typeを使う。
取得済みレスポンスで確認する場合は `saved_html` をローカルファイルへ向ける。
raw HTMLをGitに入れない。`current_data` があれば前回とのdiffも計算する。

```json
[{
  "url": "https://www.anytimefitness.co.jp/example/facility/",
  "store_name": "対象店",
  "source_type": "facility_page",
  "parser_type": "anytime",
  "saved_html": "/private/path/saved-response.html"
}]
```

オンラインdry-runは `policy_status=approved` が必要。
利用条件未確認なのにフラグだけ変更して実行してはいけない。

## 運用開始前の手順（今回は実行しない）

1. 運営元の許諾/利用条件を確認し、sourceのpolicy_noteとpolicy_checked_atに根拠を記録。
2. 許可範囲の少数store/facilityでオンラインdry-runを再実施。
   新松戸7丁目のfacilityを含む複数設備ページ、明示的な休業/再開ページ、
   parser構造差、HTTPキャッシュとEdge DNSの実通信を確認する。
3. rule configはreview-onlyのまま、既存マスター不変を確認して監視を開始する。
4. 全体設定のendpointをデプロイ先へ設定。承認済みsourceのみenabled=true。
   next_fetch_atをずらす。全体enabled=true、最後に
   `cron.alter_job(..., active := true)` を運用担当が実行する。
5. 管理→報告管理→地球アイコン「公式情報の取得状況」で監視する。
   「再確認対象」はreview状態にするだけで、即時fetchや24時間制限解除をしない。
6. parser更新のreview hold解除は差分を管理者が確認した後に限る。
   official_review_only解除は別の運用判断。既存最低報告人数、
   source protection、cooldown、rollbackは引き続き適用される。
7. 全国追加前にQA指標と監視容量を再評価。チェーン追加時はブランドparser、
   DB URL制約、fetch allowlist、同定テストを追加する。名前の曖昧一致は使わない。

停止はまずCron inactive、全体enabled=false、source enabled=false。
進行中jobの結果もpolicy承認がなければEvidence保存は拒否される。
既存マスター・ユーザー記録は削除しない。

## 検証

```sh
node --test supabase/functions/gym-official-monitor/monitor_test.mjs
supabase db query --linked --file supabase/tests/gym_official_sources.sql
supabase db query --linked --file supabase/tests/gym_official_scheduler.sql
flutter test --no-pub test/official_source_page_test.dart test/report_management_test.dart
flutter analyze --no-pub
git diff --check
```

SQL testsはfixtureをtransaction内で作成してrollbackする。
scheduler testは今回の「全停止」状態を確認するため、
将来の正式運用開始後に無条件で実行しない。

実測結果: [2026-09-29 QA](../../docs/qa/official_sources_2026-09-29/README.md)
