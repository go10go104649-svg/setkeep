# Vitalフォームガイド移行照合（2026-09-27）

購入データの3 JSONには計402件、MP4も402本ある。`100gymworkouts.json` の1件はID空欄で、対応動画 `0028.mp4` があるが今回の候補ではない。名称だけでの自動照合は行わず、器具・グリップ・軌道・対象筋・説明文と候補動画のフレームを確認した。

通常公開されていた自作3Dフォームは14種。以下の10種をVitalへ置換し、4種は不一致のため保留した。旧3Dフォームは製品画面では再生しない。

| SETKEEP exercise_id | 種目 | 旧3D asset | Vital ID | 判定 |
|---|---|---|---|---|
| `bench_press` | ベンチプレス | `assets/models/bench_press.glb` | `0042` | flat barbell bench, pronated press |
| `incline_dumbbell_press` | インクラインダンベルプレス | `assets/models/incline_dumbbell_press.glb` | `0048` | incline bench, pair of dumbbells, pronated press |
| `incline_barbell_press` | インクラインベンチプレス | `assets/models/forms/incline_barbell_press.form.json` | `0043` | incline bench and barbell press |
| `flat_dumbbell_press` | ダンベルベンチプレス | `assets/models/forms/flat_dumbbell_press.form.json` | `0046` | flat bench and pair of dumbbells |
| `assisted_chin_up` | アシストチンニング | `assets/models/forms/assisted_chin_up.form.json` | `0102` | assisted machine, overhand pull; matches existing pronated definition |
| `dy_row` | DYロー | `assets/models/forms/dy_row.form.json` | 要確認（候補 `0157`） | DYローは逆手のプレートロード式。0157はニュートラル/順手のウェイトスタック式シーテッドローで、軌道と器具が異なる。 |
| `low_row` | ローロー | `assets/models/forms/low_row.form.json` | 要確認（候補 `0157`） | ローローは低い軌道のプレートロード式。0157は一般的なウェイトスタック式シーテッドローで、負荷方式と軌道が異なる。 |
| `linear_row` | ライナーロウ | `assets/models/forms/linear_row.form.json` | 要確認（候補 `0157`） | ライナーロウは専用のプレートロード式リニア軌道。0157は異なるマシン構造・軌道。 |
| `high_row` | ライナーロウ | `assets/models/forms/high_row.form.json` | 要確認（候補 `0157`） | ハイローは高い位置から引くプレートロード式。0157は水平のシーテッドローで軌道が異なる。 |
| `cable_row` | シーテッドケーブルロー | `assets/models/forms/cable_row.form.json` | `0163` | seated low-cable row with neutral handles and foot platform |
| `dumbbell_shoulder_press` | ダンベルショルダープレス | `assets/models/forms/dumbbell_shoulder_press.form.json` | `0257` | seated overhead dumbbell press with back support |
| `barbell_curl` | バーベルカール | `assets/models/forms/barbell_curl.form.json` | `0009` | standing underhand straight-bar curl |
| `dumbbell_curl` | ダンベルカール | `assets/models/forms/dumbbell_curl.form.json` | `0015` | standing two-dumbbell supinated curl |
| `hammer_curl` | ダンベルハンマーカール | `assets/models/forms/hammer_curl.form.json` | `0016` | standing two-dumbbell neutral-grip curl |

既存のVital試験導入5種（`pec_fly`、`barbell_squat`、`leg_press`、`rope_pushdown`、`machine_lateral_raise`）も購入データへ接続し、試用表示を廃止した。

購入動画・生成サムネイルは `assets/vital_videos/` と `assets/vital_thumbnails/` にローカル配置し、Gitへ含めない。再配置は `python3 tool/vital_media/stage_media.py --source <購入データのgym_dataset>` を使用する。Android/iOSの配布ビルドには、このローカル配置が必要。

自作3Dの元アセットと制作コードは、4種の未照合対象と開発用QAが残るため、この段階では削除しない。フォーム画面からの旧3D呼び出しは除外する。部位タブの3D筋肉マネキンは維持する。

## 全カタログ拡張（同日）

SETKEEP既存212種と購入済みVital 402件を照合し、正式対応を97種へ拡大した。上記15種のVital IDはすべて維持し、新たに82種へ対応付けた。同じローイングエルゴの動画 `0077` は、通常のローイングマシンとHYROXローイングで共有する。フォームガイドに採用した動画は96本である。

全212種の判定は正式対応97種、旧ID互換1種（`triceps_pushdown` → `rope_pushdown`）、要確認94種、該当なし20種。DYロー、ローロー、ライナーロウ、ハイローへの `0157` 適用は引き続き不採用である。種目ID、履歴、3D筋肉マネキン、自作3Dの開発用データは変更しない。

購入JSONの全文・候補一覧・説明文をGitへ載せないため、全件の詳細な照合表は `python3 tool/vital_media/audit_catalog.py` でGit対象外の `build/vital_review/full_audit.md` に生成する。未採用Vital動画の「新規種目候補」は、名称と器具が近い既存種目との機械的比較による**暫定リスト**であり、新しいSETKEEP種目の追加や正式な同一性判定を意味しない。

## 最終照合と一覧画像（2026-09-27）

保留94種について、候補に挙がったVital動画56本の購入JSON（器具・対象筋・手順）と動作フレームを再確認した。器具形式、グリップ、片手／両手、姿勢、動作軌道などの不一致が残るため、今回新たに正式採用した種目は0種。既存97種のID・器具・動作も購入JSONと照合し、明確な誤対応は確認されなかったため変更していない。正式対応97種／採用動画96本、旧ID互換1種、要確認94種、該当なし20種のままとする。

Vital `0157` はウェイトスタック式の水平シーテッドローであり、`seated_row` 以外の `dy_row`・`low_row`・`linear_row`・`high_row` には採用しない。類似名称を根拠に候補から自動採用したり、フォールバックとして表示したりしない。

種目一覧・検索・メニュー選択では、正式対応種目だけ `ExerciseMediaCatalog.thumbnailAssetPath` にあるVital静止画を表示する。非対応の114 ID（保留94・該当なし20）はSETKEEPのグレーのロゴを表示し、旧自作3Dサムネイルへフォールバックしない。旧一覧用PNG 14枚と、そのcatalog参照・製品アセット指定・専用レンダリングツールは撤去した。自作3Dフォームの元データや部位タブの3D筋肉マネキンは保持する。

購入済み動画と生成サムネイルはGit管理外のローカルアセットに置き、正式採用した96本だけを配布ビルドへ含める。VitalからSETKEEPに新規追加する価値がある種目は候補としてのみ報告し、今回の種目マスターには追加しない。

## 2026-09-27 メニュー再選定・重複動画の優先順位

ユーザー指定により、同じ動作・器具の重複動画はグレー服を優先する。
姿勢が異なる動画は服の色だけで置換しない。座位ダンベルプレス0257、
前腕プランク0126、膝つきアブローラー0101は、それぞれ立位／ハイプランク／
立ちコロのグレー動画とは異なるため維持する。

既存IDへの追加接続：

| SETKEEP ID | Vital | 判定 |
|---|---|---|
| skull_crusher | 0024 | 指定されたEZバースカルクラッシャー。記録IDは維持 |
| preacher_curl | 0022 | フリーウェイト版。マシン版0159とは分離 |
| chest_supported_tbar_row | 0041 | 映像は胸当て付きプレートロード。JSONのランドマイン説明とは不一致のため映像で確認。通常Tバーロー0206とは分離 |

新しい選択可能メニュー：

| SETKEEP ID | Vital | 日本語名 |
|---|---|---|
| dumbbell_skull_crusher | 0150 | ダンベルスカルクラッシャー |
| push_up_bar | 0234 | プッシュアップバー腕立て伏せ |
| diamond_push_up | 1128 | ダイヤモンドプッシュアップ |
| incline_push_up | 1151 | インクラインプッシュアップ |
| decline_push_up | 1126 | デクラインプッシュアップ |
| v_bar_pushdown | 0139 | Vバープッシュダウン |
| meadows_row | 0158 | メドウズロー |
| gorilla_row | 0193 | ダンベルゴリラロー |
| bird_dog | 1111 | バードドッグ（体幹トレーニング） |

グレー版へ変更：deadlift→0032、face_pull→0030、military_press→0088、
glute_bridge→1139、cable_crunch→0002。履歴・記録方式は変更しない。

メニュー総数はカタログ221件（非選択の旧IDを含む）、直接マッピング109件、
動画108本。未解決91件、旧ID継承1件、該当なし20件。
ストレッチは追加していない。ユーザー向け写真一覧は今回採用した12種のみとし、
使わない重複動画・ストレッチを候補として再掲しない。
ローカル写真一覧：build/vital_selected_gallery/selected-01.png（Git管理外）。
