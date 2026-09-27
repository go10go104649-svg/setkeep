"""Audit every SETKEEP exercise and every purchased Vital metadata/video record.

The detailed report is written only under build/ because purchased metadata and
candidate descriptions must not be committed to the repository.
"""

import argparse
import difflib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "tool/exercise_forms/catalog.json"
MAPPING = Path(__file__).with_name("mapping.json")

NO_MATCH_REASONS = {
    "hip_adduction": "股関節内転マシンの同動作・同設備動画なし",
    "wall_sit": "壁にもたれる静的保持動作の動画なし",
    "decline_barbell_press": "デクライン角度のバーベルプレス動画なし",
    "decline_dumbbell_fly": "デクライン角度のダンベルフライ動画なし",
    "low_cable_fly": "下方から引くケーブルフライの同軌道動画なし",
    "single_arm_cable_fly": "片手ケーブルフライの同動作動画なし",
    "dumbbell_pullover": "ダンベルを使うプルオーバー動画なし",
    "machine_pullover": "専用プルオーバーマシンの動画なし",
    "nordic_hamstring_curl": "ノルディック式の自重ハムストリングカール動画なし",
    "cable_pull_through": "ケーブルプルスルーの同動作動画なし",
    "glute_kickback_machine": "専用キックバックマシンの同設備動画なし",
    "pallof_press": "抗回旋を保つパロフプレス動画なし",
    "hyrox_ski_erg": "スキーエルゴの同設備動画なし",
    "hyrox_sled_push": "スレッドを押す同動作動画なし",
    "hyrox_sled_pull": "スレッドを引く同動作動画なし",
    "hyrox_farmers_carry": "両手で運搬するファーマーズキャリー動画なし",
    "hyrox_wall_ball": "壁の標的へ投げるウォールボール動画なし",
    "rotary_torso": "専用回旋マシンの同設備動画なし",
    "recumbent_bike": "背もたれ付きリカンベントバイク動画なし",
    "viking_press": "バイキングプレス器具の同設備動画なし",
}


def tokens(value):
    value = value.lower().replace("'s", "s")
    for old, new in {
        "pushups": "push up", "pullup": "pull up", "flys": "fly",
        "raises": "raise", "rows": "row", "curls": "curl",
        "presses": "press", "squats": "squat", "lunges": "lunge",
    }.items():
        value = value.replace(old, new)
    return set(re.findall(r"[a-z]+", value)) - {"standard", "version", "workout"}


def equipment_group(value):
    value = value.lower()
    if "dumbbell" in value:
        return "dumbbell"
    if value in {"barbell", "ez_bar", "landmine"}:
        return "barbell"
    if "cable" in value:
        return "cable"
    if "machine" in value or value in {"treadmill", "exercise_bike", "cross_trainer", "stair_climber", "rowing_machine"}:
        return "machine"
    if value in {"bodyweight", "body weight", "floor", "pullup_bar", "parallel_bars"}:
        return "body weight"
    return value


def similar(exercise, vital):
    a = tokens(exercise.get("englishName", ""))
    b = tokens(vital["name"])
    overlap = len(a & b) / len(a | b) if a | b else 0
    sequence = difflib.SequenceMatcher(None, exercise.get("englishName", "").lower(), vital["name"].lower()).ratio()
    return max(overlap, sequence * 0.7)


JP_TERMS = {
    "ab wheel": "アブローラー", "ab roll": "アブローラー",
    "sit-ups": "シットアップ", "sit ups": "シットアップ",
    "pushups": "プッシュアップ", "face pull": "フェイスプル",
    "bird dog": "バードドッグ", "bulgarian": "ブルガリアン",
    "russian": "ロシアン", "burpee": "バーピー",
    "stepmill": "ステップミル", "sprint": "スプリント",
    "hinge": "ヒンジ", "swing": "スイング", "flys": "フライ",
    "resistance band": "レジスタンスバンド", "body weight": "自重",
    "single arm": "片手", "single leg": "片脚", "one arm": "片手",
    "close grip": "ナローグリップ", "wide grip": "ワイドグリップ",
    "overhead": "オーバーヘッド", "chest supported": "チェストサポート",
    "bent over": "ベントオーバー", "pull apart": "プルアパート",
    "push up": "プッシュアップ", "pull up": "プルアップ",
    "barbell": "バーベル", "dumbbell": "ダンベル", "kettlebell": "ケトルベル",
    "cable": "ケーブル", "machine": "マシン", "banded": "バンド",
    "band": "バンド", "assisted": "アシスト", "weighted": "加重",
    "alternating": "オルタネイト", "reverse": "リバース",
    "incline": "インクライン", "decline": "デクライン",
    "seated": "シーテッド", "standing": "スタンディング",
    "kneeling": "ニーリング", "lying": "ライイング",
    "front": "フロント", "rear": "リア", "lateral": "サイド",
    "shoulder": "ショルダー", "chest": "チェスト", "triceps": "トライセプス",
    "biceps": "バイセプス", "hamstring": "ハムストリング",
    "glute": "グルート", "hip": "ヒップ", "leg": "レッグ",
    "arm": "アーム", "calf": "カーフ", "wrist": "リスト",
    "curl": "カール", "press": "プレス", "squat": "スクワット",
    "lunge": "ランジ", "row": "ロー", "fly": "フライ",
    "raise": "レイズ", "extension": "エクステンション",
    "crunch": "クランチ", "plank": "プランク", "deadlift": "デッドリフト",
    "pulldown": "プルダウン", "pushdown": "プッシュダウン",
    "pull": "プル", "push": "プッシュ", "stretch": "ストレッチ",
    "jump": "ジャンプ", "hold": "ホールド", "twist": "ツイスト",
    "bridge": "ブリッジ", "march": "マーチ", "run": "ラン",
    "running": "ランニング", "bike": "バイク", "cycling": "サイクリング",
    "step": "ステップ", "side": "サイド", "high": "ハイ", "low": "ロー",
}


def provisional_japanese(name):
    text = name.lower().replace("'s", "s")
    for english, japanese in sorted(JP_TERMS.items(), key=lambda item: -len(item[0])):
        text = re.sub(r"\b" + re.escape(english) + r"\b", japanese, text)
    return "仮称：" + text.replace("(", "（").replace(")", "）")


def audit(source, output):
    catalog = json.loads(CATALOG.read_text())["exercises"]
    mapping = json.loads(MAPPING.read_text())
    metadata = []
    for path in sorted(source.rglob("*.json")):
        metadata.extend(json.loads(path.read_text()))
    videos = list(source.rglob("*.mp4"))
    by_id = {item["id"]: item for item in metadata if item.get("id")}
    video_ids = {path.stem for path in videos}
    assert len(catalog) == len({item["exerciseId"] for item in catalog})
    assert len(metadata) == len(videos) == 402
    assert len(by_id) == 401
    assert len(video_ids) == len(videos)
    assert set(by_id) <= video_ids
    assert video_ids - set(by_id) == {"0028"}
    assert len([item for item in metadata if not item.get("id")]) == 1
    assert (source / "100 Gym Workouts/100gymworkouts/0028.mp4").is_file()
    assert all(item.get("instructions") and item.get("name") and item.get("equipment") and item.get("target") for item in metadata)
    assert all((source / item["sourceAsset"]).is_file() for item in mapping["mappings"])
    assert all(item["providerAssetId"] in by_id for item in mapping["mappings"])
    mapped = {item["exerciseId"]: item for item in mapping["mappings"]}
    review = {item["exerciseId"]: item for item in mapping["reviewRequired"]}
    assert not set(mapped) & set(review)
    assert set(mapped) | set(review) <= {item["exerciseId"] for item in catalog}
    used_video_ids = {item["providerAssetId"] for item in mapping["mappings"]}
    review_video_ids = {candidate for item in review.values() for candidate in item["candidateVitalIds"]}
    catalog_by_id = {item["exerciseId"]: item for item in catalog}
    inherited = {
        item["exerciseId"]: item["canonicalExerciseId"]
        for item in catalog
        if item.get("canonicalExerciseId") in mapped
        and item["exerciseId"] not in mapped
    }
    unused_vital = [item for item in metadata if item.get("id") and item["id"] not in used_video_ids]
    new_candidates = []
    variants_or_review = []
    for item in unused_vital:
        nearest = max(catalog, key=lambda exercise: similar(exercise, item))
        score = similar(nearest, item)
        same_equipment = equipment_group(nearest.get("equipmentId", "")) == equipment_group(item["equipment"])
        # This is a candidate-list classification, never an adoption decision.
        if item["id"] in {"0001", "1107"} or item["id"] in review_video_ids or (score >= .45 and same_equipment):
            variants_or_review.append((item, nearest, score))
        else:
            new_candidates.append((item, nearest, score))
    lines = [
        "# Vital購入データ全件照合（ローカルQA用・Git管理外）", "",
        f"SETKEEP {len(catalog)}種 / Vital JSON {len(metadata)}件 / MP4 {len(videos)}本。",
        f"正式マッピング {len(mapped)}種（Vital動画 {len(used_video_ids)}本）、旧ID互換 {len(inherited)}種、要確認 {len(review)}種、該当なし {len(catalog)-len(mapped)-len(inherited)-len(review)}種。",
        f"Vital未採用素材 {len(unused_vital)}件のうち、暫定新規・別動作候補 {len(new_candidates)}件、既存近似・重複/レビュー候補 {len(variants_or_review)}件。",
        "ID空欄のJSON 1件と0028.mp4は内容を確認したが、IDを補完せずマッピング対象外。",
        "", "## SETKEEP全212種の判定", "",
        "元カタログに独立した種目説明欄はないため、器具・グリップ・動作variant・parametersと筋肉情報を照合に使用。", "",
        "| exercise_id | 日本語名 | 英語名 | 部位 | 器具 | グリップ | 動作variant | parameters | 主働筋 | 補助筋 | 3D状態 | Vital ID / 判定 | サムネイル |", "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for item in catalog:
        eid = item["exerciseId"]
        decision = (mapped[eid]["providerAssetId"] if eid in mapped else
                    "旧ID互換→" + inherited[eid] if eid in inherited else
                    "要確認 " + ",".join(review[eid]["candidateVitalIds"]) if eid in review else "該当なし")
        thumb = ("assets/vital_thumbnails/" + mapped[eid]["providerAssetId"] + ".png" if eid in mapped else item.get("thumbnailAssetPath") or "—")
        lines.append("| " + " | ".join(str(value).replace("|", "/") for value in [eid,item["exerciseName"],item.get("englishName") or "—",item["category"],item.get("equipmentId") or "—",item.get("gripType") or "—",item.get("movementVariant") or "—",json.dumps(item.get("parameters") or {},ensure_ascii=False,sort_keys=True), ",".join(item.get("primaryMuscles", [])) or "—", ",".join(item.get("secondaryMuscles", [])) or "—", item.get("status") or "—",decision,thumb]) + " |")
    lines += ["", "## 新規マッピング", "", "| exercise_id | SETKEEP名 | Vital ID | Vital name | equipment | target | 判定理由 |", "|---|---|---|---|---|---|---|"]
    for entry in mapping["mappings"][15:]:
        item = by_id[entry["providerAssetId"]]
        lines.append(f"| {entry['exerciseId']} | {catalog_by_id[entry['exerciseId']]['exerciseName']} | {entry['providerAssetId']} | {item['name']} | {item['equipment']} | {item['target']} | {entry['reason']} |")
    lines += ["", "## 要確認", "", "| exercise_id | SETKEEP名 | 候補Vital ID | 不一致点 |", "|---|---|---|---|"]
    for eid,item in review.items():
        lines.append(f"| {eid} | {catalog_by_id[eid]['exerciseName']} | {','.join(item['candidateVitalIds'])} | {item['reason']} |")
    lines += ["", "## 該当なし", "", "| exercise_id | SETKEEP名 | 理由 |", "|---|---|---|"]
    for item in catalog:
        eid=item["exerciseId"]
        if eid not in mapped and eid not in review and eid not in inherited:
            lines.append(f"| {eid} | {item['exerciseName']} | {NO_MATCH_REASONS[eid]} |")
    lines += ["", "## SETKEEP未登録の暫定新規・別動作候補", "", "名称は仮訳。近い既存種目は比較用であり、自動紐付けを意味しない。", "", "| Vital ID | Vital name | 日本語候補名 | equipment | bodyPart | target | secondaryMuscles | 動作概要 | 類似SETKEEP exercise_id | 重複・バリエーション可能性 |", "|---|---|---|---|---|---|---|---|---|---|"]
    for item,nearest,score in new_candidates:
        summary = item["instructions"][0].split(".")[0].replace("|","/")
        lines.append(f"| {item['id']} | {item['name']} | {provisional_japanese(item['name'])} | {item['equipment']} | {item['bodyPart']} | {item['target']} | {','.join(item['secondaryMuscles'])} | {summary} | {nearest['exerciseId']} | {'要比較' if score >= .45 else '低'} ({score:.2f}) |")
    lines += ["", "## 既存近似・重複/レビュー素材（新規追加候補に数えない）", "", "| Vital ID | Vital name | equipment | target | 類似SETKEEP exercise_id | 理由 |", "|---|---|---|---|---|---|"]
    for item,nearest,score in variants_or_review:
        label = "採用見送り候補" if item["id"] in review_video_ids else "名称・器具が近い別動画。重複/差異の審査が必要"
        lines.append(f"| {item['id']} | {item['name']} | {item['equipment']} | {item['target']} | {nearest['exerciseId']} | {label} |")
    lines += ["", "## ID空欄の購入データ", "", "0028.mp4に対応する位置のJSONは `barbell bent over row`、器具barbell、対象lats、補助rhomboids/biceps/lower back等。ID欄が空欄のため未採用。", ""]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines))
    return len(new_candidates), len(variants_or_review)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "local_assets/vital_animations/gym_dataset")
    parser.add_argument("--output", type=Path, default=ROOT / "build/vital_review/full_audit.md")
    args=parser.parse_args()
    new, variants=audit(args.source.resolve(),args.output.resolve())
    print(f"Audited 212 SETKEEP exercises and 402 Vital records; {new} provisional new candidates, {variants} review/variant videos")

if __name__ == "__main__":
    main()
