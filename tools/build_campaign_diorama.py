"""Retired diorama generator. Do not overwrite the imported reference landscape."""

import sys

if __name__ == "__main__":
    sys.stderr.reconfigure(encoding="utf-8")
    raise SystemExit(
        "旧战役沙盘生成器已退役，未写入任何文件。\n"
        "请先运行 node tools/import_reference_railway.mjs，"
        "再通过 Godot --headless --path . --script res://tools/bake_reference_railway.gd 烘焙。\n"
        "详见 docs/art/campaign_route_map.md；历史造型可从 Git 历史恢复。"
    )
