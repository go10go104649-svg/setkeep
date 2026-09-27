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
