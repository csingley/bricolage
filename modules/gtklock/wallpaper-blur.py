"""Pre-render the blurred, dimmed lock-screen wallpaper.

GTK3 CSS can't blur, so gtklock is pointed at an image rendered here. Run by the
home-manager activation hook in default.nix, with Nix's Python and Pillow:

    python3 -I wallpaper-blur.py SRC DST

Does nothing if SRC is missing or DST is already newer than SRC.
"""
import os
import sys

from PIL import Image, ImageEnhance, ImageFilter


def main(src: str, dst: str) -> None:
    if not os.path.isfile(src):
        return
    if os.path.isfile(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    im = Image.open(src).convert("RGB")
    im = im.filter(ImageFilter.GaussianBlur(24))
    im = ImageEnhance.Brightness(im).enhance(0.65)
    im.save(dst, quality=90)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
