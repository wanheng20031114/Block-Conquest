"""Split the generated transparent icon sheet without synthesizing image pixels.

Keep the model's native RGBA edges; only crop transparent margins, align, and
pad onto equal square canvases. Runtime TextureRects preserve the aspect ratio.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / "assets/ui/medieval/icons/rogue"


def split_sheet(source, names):
    sheet = Image.open(FOLDER / source)
    assert sheet.mode == "RGBA" and sheet.width == sheet.height * len(names)
    assert sheet.getchannel("A").getextrema() == (0, 255), "Native transparency required"
    pieces = []
    for index in range(len(names)):
        cell = sheet.crop((index * sheet.height, 0, (index + 1) * sheet.height, sheet.height))
        bounds = cell.getchannel("A").getbbox()
        assert bounds is not None
        pieces.append(cell.crop(bounds))
    side = max(max(piece.size) for piece in pieces) + 40
    for name, piece in zip(names, pieces):
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(piece, ((side - piece.width) // 2, (side - piece.height) // 2))
        canvas.save(FOLDER / f"{name}.png")
        print(f"{name}: native {piece.width}x{piece.height} crop on {side}px transparent canvas")


def main():
    split_sheet("source/resources.png", ("coin", "bread", "boot"))
    split_sheet("source/recruit_rewards.png", ("recruitment", "experience"))


if __name__ == "__main__":
    main()
