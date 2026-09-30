# 登録済み店舗設備の公開方針・本番確認

基準: `setkeep/setkeep` main `a5489b11bd6655864f86edd110af4a007c3dcbf0`。
origin/mainをfetchして一致確認。開始時の作業ツリーはclean。
前タスクの広告基盤はこのmainに含まれており変更していない。commit / pushなし。

## 結論と変更範囲

**一覧の公開停止はコード・本番DBとも実装されていなかった。復旧用のアプリ変更・migration・データ再投入は不要。**

- コミット`0762968`の公式取得停止はCron/取得先の停止。表示用RPCを停止する変更ではない。
- `c0176c9`の任意設備確認は既存Masterを保持する設計。公式由来を利用者確認へ付け替える変更なし。
- `gym_store_detail` / `gym_store_equipment_page`は`presence_status=present`のみを条件にする。
  `source_kind`や報告の有無を表示条件に使わない。RLSの参照権限にも出典フィルターなし。
- `gym_store_exercise_evidence`はpresent・available・利用可能台数を判定し、共通の
  `equipment_exercise_evidence`を呼ぶ。direct/canonical/複合ルールを維持。
- `GymStoreEquipmentPage`、`GymEquipmentExercisesPage`、種目ピッカーの店舗フィルターは
  現行RPC結果を利用。未知メーカー・型番・台数を推測しない。
- 未取得/一部取得の既存文言、撤去・一時利用不可の扱いを維持。
- 最新マスターを入場ごとに取得し、通信失敗時のみ既存キャッシュを使う。
  オフラインでは最新撤去情報を取得できない制限がある（既存UIは前回情報であることを表示）。

今回の変更は現行仕様の明確化、公開方針の回帰テスト、QA記録のみ。
過去QAは履歴として保持。検索で見つかった「公開停止」は旧3D制作の記録であり、設備公開とは別のため変更しない。

## 接続先・本番データ

既存linked project `meyrtimwibqonozsewbt`、最新適用migration `202609290032`。
`supabase db query --linked`で参照し、未適用migrationの一括pushはしていない。
マスター・履歴・認証・設定の永続更新なし。テスト用データは各SQLのtransaction内で作成しrollback。

13チェーン、2,699店舗、設備マスター2,604件、店舗設備9,513件。
設備行を持つのは352店舗であり、全2,699店舗の設備を取得済みとは扱わない。
店舗設備9,513件は現在すべて`source_kind=official / presence_status=present`。
ユーザー現地確認済みという過去メッセージを理由に出典や確認日を書き換えていない。

| チェーン | 店舗数 | 設備登録がある店舗 | 店舗設備行数 |
|---|---:|---:|---:|
| AUN'S GYM | 19 | 3 | 90 |
| FASTGYM24 | 91 | 88 | 1,954 |
| FIT-EASY | 322 | 13 | 31 |
| FiT24 | 122 | 18 | 683 |
| FIT PLACE24 | 244 | 35 | 1,582 |
| GOLD'S GYM | 114 | 39 | 250 |
| HYPER FIT24 | 46 | 24 | 923 |
| JOYFIT24 | 195 | 47 | 1,116 |
| JOYFIT24 LITE | 1 | 0 | 0 |
| KANEKIN FITNESS GYM | 1 | 1 | 37 |
| SMART FIT100 | 57 | 4 | 73 |
| WORLD+GYM | 160 | 20 | 385 |
| エニタイムフィットネス | 1,327 | 60 | 2,389 |

## 設備→種目の実測

管理者のSELECTだけでなく`set local role authenticated`で実際の公開RPCを取得。
取得レスポンスを現行Flutterの`GymStoreDetail.fromJson`、`availableForms`、キャッシュ用codecに通して確認。
RPCの種目集合とdetail.evidenceの集合が一致することも検査。

| 店舗 | 表示設備 | RPC種目数 | 現行カタログで選択可能 | 対応種目を表示できる設備 |
|---|---:|---:|---:|---:|
| エニタイム松戸馬橋 | 45 | 87 | 87 | 30 |
| FIT PLACE24 南柏 | 47 | 101 | 101 | 47 |
| FIT PLACE24 市川 | 52 | 106 | 106 | 52 |
| FIT PLACE24 新松戸 | 33 | 88 | 88 | 32 |
| FIT PLACE24 松戸駅前 | 49 | 98 | 98 | 49 |
| KANEKIN FITNESS GYM 松戸 | 37 | 83 | 81 | 34 |

馬橋のダンベル・ラック・スミス・ケーブルとレビュー済み各種マシンは反映済み。
バーベル単体およびラック＋ベンチ＋バーベルの成立/不足はcanonical SQLテストで確認。
名称だけから設備を追加する修正はしない。

### 準備中表示が残る理由

出典による非公開ではなく、未登録マッピング・成立するルールがない設備はそのまま表示する。
馬橋は15設備（SYNRGY360、別区分インクラインプレス/ショルダープレス、プルダウン、
ウエイトツリー等）。器具・動作を推測して対応種目を追加していない。
全対象ID・名称は[results.json](results.json)の`unmapped_display_equipment`に保存。

カネキンのRPC83件と画面81件の差は、旧汎用`leg_curl`/`calf_raise`が新規選択対象外であるため。
履歴互換のため残されているIDであり、具体的な姿勢/器具を推測して別種目へ変換しない。
ユーティリティーベンチの未対応も維持。今回は種目マスター整理や追加マッピングを行わない。

## 取得停止と利用者報告

- `gym_official_monitor_config.enabled=false`、enabled source 0、Cron `setkeep-official-pilot.active=false`。
  新規取得・定期巡回・外部サイトへのアクセスなし。公式取得コード/設定の変更なし。
- 修正・撤去報告、候補/証拠、競合、審査、監査、rollbackを削除していない。
- トレーニング後確認は任意・スキップ可能のまま。既知設備には再質問しない。
- 個人の登録店舗/報告/トレーニングを公開テーブルへ複製していない。

## 検証

- 新規`gym_equipment_publication.sql`: 未報告の公式設備の公開、メーカー/型番/未知台数/出典/日時保持、
  未取得店舗、撤去/利用不可の除外、複合条件、一般ユーザー書込み不可。rollback成功。
- 本番DB関連11ファイルすべて成功。一覧はresults.jsonの`db_tests`。
  canonical、馬橋、複合条件、RLS、設備報告、候補・適用・rollback、店舗営業状態、任意確認を含む。
- テスト前後で店舗・設備・店舗設備・direct mapping・複合ルール・rule items・canonical membershipの
  **全7系統の件数/全行hashが一致**。出典/確認日を含む既存マスターを変更していない。
- 新規Flutter回帰3件成功: Android/iOS狭幅の一覧→設備詳細、報告ボタン維持、
  メタデータ、未知台数、永続キャッシュ再読込/撤去後更新。
- 本番RPCレスポンスのFlutterモデル/カタログ照合1件成功（ローカル一時probe、データは再登録していない）。
- `flutter analyze --no-pub`: No issues found。
- `flutter test --no-pub`: 全393件成功（新規3件を含む）。
- `git diff --check`: 成功。

マイページの利用場所→店舗詳細、トレーニングの店舗検索→店舗詳細、
選択済み店舗→設備/対応種目は既存共通画面を維持。既存Widgetテストとコードを確認。
**Galaxy/iPhone実機・Simulator操作・実機へインストールは未実施**。
Android/iOSはTargetPlatformを切り替えたWidget検証であり、実機確認ではない。
アプリ/ネイティブ実装変更がないため再ビルドは行わない。

## 変更ファイル

- `docs/current_spec.md`
- `supabase/tests/gym_equipment_publication.sql`
- `test/gym_publication_test.dart`
- 本書、`results.json`


## 追加確認: エニタイム正式Excelとの全件突合

ユーザーの「全て反映」の依頼を受け、過去依頼で指定されたGoogle Drive正本
`SETKEEP/data/import/SETKEEP_エニタイムフィットネス_全国店舗設備マスター_v1.0.xlsx`
を読み取り専用で開いた。旧v0.1は使っていない。
SHA-256: `697751fb84ef6a9895dda8e17dfc4c341af44b70ad3f198ddfafe3d30bac4bdc`。
処理前後のhash一致。Excel・ローカルSQL生成物をGitへ追加していない。

| 正本の対象 | 正本件数 | 本番DBとの一致 | 欠落 |
|---|---:|---:|---:|
| 店舗ID | 1,327 | 1,327 | 0 |
| 設備元ID | 665 | 665 | 0 |
| 店舗ID × 対応設備ID | 2,389 | 2,389 | 0 |

既存の承認済み`anytime_equipment_reuse.json`とインポーターを用いてIDを解決した。
665設備元IDは662共通設備IDへ対応する（128元IDが125既存IDを再利用、537固有ID）。
店舗設備の組合せ重複は0、マスター外の追加組合せも0。件数だけでなく全キーを照合。
店舗名/住所/取得状態/元出典JSON、設備の台数/元名称/出典/確認日時/元JSONも差分0。
既存の表示名・レビュー済み共通マッピングは古いExcelで上書きしない。
元Excelにはメーカー・型番専用列はなく、不明値を追加していない。

全60設備登録店舗に対し、authenticatedロールで`gym_store_detail`と
`gym_store_exercise_ids`を実行し、全2,389設備が表示対象、全店舗の種目集合が
詳細画面とフィルターで一致、60店舗すべてに対応種目があることを確認。
未マッピングの個別設備まで対応済みという意味ではない。
既存AnytimeインポーターのPython単体テスト5件も成功。

**正本のデータはすべて本番に反映済み。追加・復旧対象が0件のため、DBの再書込みは行っていない。**
設備未取得1,250店舗・元サイト設備未掲載17店舗には正本にも設備行が存在しない。
その1,267店舗の設備を取得済みに変更したり、他店舗からコピーしたりしていない。
全国1,327店舗すべての設備情報を揃える作業は、今回の既存マスター反映とは区別する。
公式サイトの新規取得/定期取得は再開していない。
