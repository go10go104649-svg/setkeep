# チェーン横断の設備知識

既存の設備ID・直接マッピング・複数設備ルール・店舗在庫は変更しない。
共通概念は「実在する設備が提供する能力」であり、アジャスタブルベンチは
flat/inclineの2能力、ラックはrackだけを持つ。バーベルやデクラインを推定しない。

## 判定・読み取り

`equipment_canonical_mapping` のレビュー済み所属と `equipment_canonical_matchers` の
現在の設備署名が一致するものだけを `equipment_canonical_memberships` で有効にする。
名称/normalized_nameはNFKC・小文字・空白/中点除去、カテゴリ/負荷方式/メーカー/型番は完全一致。
負荷方式が重要な一般名は既存レビュー済みdirectの存在も要求する。元のneeds_reviewは書き換えない。
メーカー・重量表記の明確なダンベルは通常ダンベルに分類するが、ラック・エリア・混合レコードは除外。
source / raw_name / aliases /数量の元情報は保持し、監査CSVで確認する。

`equipment_resolved_exercise_mapping` はdirect + canonical単体のUNION。
`equipment_exercise_evidence` はそれと既存複合条件 + canonical複合条件を統合する。
共有店舗と本人専用設備はこの評価器を共用。種目IDは既存カタログのみ。
店舗の撤去/利用不可/全台使用不可の除外は既存wrapperを維持する。
Evidenceには元設備ID/名称を返す。Flutter側の既存SetとavailableFormsで表示の重複を防ぐ。
店舗詳細、設備ページ、設備検索が同じreference解決を利用する。

## 新チェーン追加時

1. 従来のインポートで元equipment/店舗設備を登録する。
2. `equipment_canonical_candidates` を照会する。これは候補であり自動確定しない。
3. 以下でreference snapshotと候補SQL/CSVを出す（ユーザーデータ・secretは取得しない）。

```sh
supabase db query --linked --file tool/equipment_canonical/snapshot.sql --output-format json > /tmp/equipment_snapshot.json
python3 tool/equipment_canonical/build_seed.py --inventory /tmp/equipment_snapshot.json --sql /tmp/proposed.sql --review /tmp/proposed.csv
python3 tool/equipment_canonical/audit.py --snapshot /tmp/equipment_snapshot.json --output /tmp/equipment_audit
```

4. 新規所属候補のカテゴリ・負荷方式・メーカー/型番・店舗raw_name/sourceをレビュー。
   不確実な名前をaliasesに追加して無条件承認しない。新しい仕様はknowledge.pyとテストで明示。
5. レビューした差分だけを**新規additive migration**で登録する。
   生成SQLは実行候補であり、レビュー前の一括本番投入は禁止。
   同じSQLの再実行はON CONFLICT DO NOTHINGで重複しないが、既存署名の修正/承認変更は別migrationで扱う。
6. `supabase/tests/canonical_equipment.sql`、既存multi・private place・state reports等で確認。
7. 下記read-only検証とauditを再実行し、before/afterを比較する。

```sh
supabase db query --linked --file tool/equipment_canonical/verify.sql --output-format json
python3 -m unittest discover -s tool/equipment_canonical -p 'test_*.py'
```

## 監査の読み方

チェーンcoverageは**設置実績のあるdistinct equipment ID数**。同じequipmentを複数チェーンが参照すると
両チェーンに数える。directとmultiは重複するため足し合わせない。
no_mappingは単体・複合のいずれにも知識がない数で、店舗で条件成立する種目数ではない。
`unresolved.csv` は単体種目がない設備に加え、設置先がないマスター行も収録する。

- equipment_mapping_missing: 知識未設定
- equipment_ambiguous: 元データで要調査（未確定）
- exercise_not_in_catalog: 設備は特定済みだが種目未収録（前脛骨筋マシン）
- requires_other_equipment: 複合条件の部品。単体0件でも店舗内で条件が成立すれば表示される

ソース由来needs_reviewと今回のcanonical審査結果は別。既存directの挙動も残しているため、
FIT PLACEの旧ダンベルdirectに含まれるベンチ利用種目を今回削除はしていない。
新しいcanonical知識ではベンチ条件へ分離し、旧ダンベルdirectも解決時に同じ条件へ通す。
旧direct行そのものは残るが、ベンチ必須種目を単体リストへ返さず、必要設備が揃った場合にEvidenceへ返す。
