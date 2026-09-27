"""Stage only reviewed purchased videos for Flutter; never commit staged media.

Run from the repository root. The source defaults to the locally purchased
dataset and can be overridden with --source. --check verifies the source only.
"""

import argparse
import json
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name("mapping.json")


def verify(source, mapping):
    if not source.is_dir():
        raise ValueError(f"Vital source directory is missing: {source}")
    metadata = {}
    for path in source.rglob("*.json"):
        for item in json.loads(path.read_text()):
            if item.get("id"):
                if item["id"] in metadata:
                    raise ValueError(f"Duplicate Vital ID: {item['id']}")
                metadata[item["id"]] = item
    for item in mapping["mappings"]:
        asset_id = item["providerAssetId"]
        video = (source / item["sourceAsset"]).resolve()
        if not video.is_relative_to(source.resolve()) or not video.is_file():
            raise ValueError(f"Missing purchased video: {item['sourceAsset']}")
        if video.stem != asset_id:
            raise ValueError(f"Vital ID and filename differ: {asset_id}")
        record = metadata.get(asset_id)
        if not record or record["name"] != item["vitalName"] or record["equipment"] != item["equipment"]:
            raise ValueError(f"Purchased metadata differs from reviewed mapping: {asset_id}")
    return metadata


def stage(source, mapping, *, thumbnails=True):
    verify(source, mapping)
    video_dir = ROOT / "assets/vital_videos"
    image_dir = ROOT / "assets/vital_thumbnails"
    video_dir.mkdir(parents=True, exist_ok=True)
    image_dir.mkdir(parents=True, exist_ok=True)
    selected_ids = {item["providerAssetId"] for item in mapping["mappings"]}
    for staged in video_dir.glob("*.mp4"):
        if staged.stem not in selected_ids:
            staged.unlink()
    for staged in image_dir.glob("*.png"):
        if staged.stem not in selected_ids:
            staged.unlink()
    for item in mapping["mappings"]:
        original = source / item["sourceAsset"]
        staged = video_dir / f"{item['providerAssetId']}.mp4"
        if not staged.exists() or staged.stat().st_size != original.stat().st_size:
            shutil.copy2(original, staged)
    if thumbnails:
        subprocess.run(
            ["swift", str(Path(__file__).with_name("extract_thumbnails.swift")),
             str(video_dir), str(image_dir)],
            check=True,
            cwd=ROOT,
        )
    return len(mapping["mappings"])


def main():
    mapping = json.loads(MANIFEST.read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / mapping["sourceRoot"])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--skip-thumbnails", action="store_true")
    args = parser.parse_args()
    source = args.source.resolve()
    if args.check:
        verify(source, mapping)
        print(f"Verified {len(mapping['mappings'])} purchased videos")
    else:
        count = stage(source, mapping, thumbnails=not args.skip_thumbnails)
        print(f"Staged {count} videos in ignored Flutter asset directories")


if __name__ == "__main__":
    main()
