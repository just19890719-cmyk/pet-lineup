"""合成 App Store 商店截圖（1290×2796，繁中與英文兩套）。

用法：
    python -I tools/make_store_shots.py <原始畫面資料夾> [輸出資料夾]

原始畫面資料夾裡要有 {title,play,hint,win,lang}_{zh_TW,en}.png，
是用 Godot 以 1290×2796 無邊框視窗、加 --store-shot 參數錄下來的乾淨畫面
（--store-shot 會藏起「開發」按鈕）。擷取方式見 CLAUDE_HANDOFF.md。
輸出預設寫到專案的「商店截圖/」。
"""
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1290, 2796
FONT = "C:/Windows/Fonts/NotoSansTC-VF.ttf"  # 完整字型（子集字型缺標語用字）

# 每張圖：原始畫面名稱、大標題、副標題
CAPTIONS = {
    "zh_TW": [
        ("title", "萌寵盲盒排序", "把同款動物排成一欄"),
        ("play", "翻開問號 猜猜是誰", "邊排邊揭曉藏起來的動物"),
        ("hint", "卡關也不怕", "提示幫你找到下一步"),
        ("win", "300 關慢慢玩", "從輕鬆到燒腦，一關一關挑戰"),
        ("lang", "支援 14 種語言", "繁中、English、日本語等一鍵切換"),
    ],
    "en": [
        ("title", "Cute Animal Sort", "Stack matching pets in one column"),
        ("play", "Who's Behind the ?", "Uncover hidden pets as you sort"),
        ("hint", "Stuck? Get a Hint", "Hints show you the next move"),
        ("win", "300 Levels", "From relaxing to brain-teasing"),
        ("lang", "14 Languages", "Switch languages anytime"),
    ],
}

# 每張圖換一組粉嫩底色（上、下）
PALETTES = [
    ((255, 214, 224), (255, 240, 214)),
    ((214, 236, 255), (232, 222, 255)),
    ((255, 233, 205), (255, 214, 224)),
    ((220, 245, 222), (214, 236, 255)),
    ((236, 222, 255), (255, 222, 236)),
]
TITLE_COLOR = (92, 56, 37)
SUB_COLOR = (226, 108, 52)


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_axes([weight])
    return f


def gradient(top, bottom):
    g = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        g.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return g.resize((W, H))


def paw(d, cx, cy, r, fill):
    d.ellipse((cx - r, cy - r * 0.8, cx + r, cy + r * 1.0), fill=fill)
    for dx, dy in ((-1.05, -1.25), (-0.38, -1.75), (0.38, -1.75), (1.05, -1.25)):
        tr = r * 0.42
        x, y = cx + dx * r, cy + dy * r
        d.ellipse((x - tr, y - tr, x + tr, y + tr), fill=fill)


def heart(d, cx, cy, r, fill):
    d.ellipse((cx - r, cy - r, cx, cy), fill=fill)
    d.ellipse((cx, cy - r, cx + r, cy), fill=fill)
    d.polygon([(cx - r * 0.97, cy - r * 0.3), (cx + r * 0.97, cy - r * 0.3), (cx, cy + r * 1.1)], fill=fill)


def background(idx):
    top, bottom = PALETTES[idx % len(PALETTES)]
    bg = gradient(top, bottom).convert("RGBA")
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rnd = random.Random(20261115 + idx)
    # 交錯格子撒腳印、愛心、圓點，看起來可愛又不亂
    step = 215
    for row, y in enumerate(range(-60, H + 120, step)):
        for x in range(-60 + (row % 2) * step // 2, W + 120, step):
            jx, jy = x + rnd.randint(-30, 30), y + rnd.randint(-30, 30)
            kind = rnd.random()
            if kind < 0.5:
                paw(d, jx, jy, rnd.randint(22, 32), (255, 255, 255, 120))
            elif kind < 0.8:
                heart(d, jx, jy, rnd.randint(18, 26), (255, 255, 255, 110))
            else:
                r = rnd.randint(8, 14)
                d.ellipse((jx - r, jy - r, jx + r, jy + r), fill=(255, 255, 255, 140))
    return Image.alpha_composite(bg, layer)


def fit_font(text, max_w, size, weight):
    while True:
        f = font(size, weight)
        if f.getlength(text) <= max_w or size <= 40:
            return f
        size -= 4


def draw_text_center(img, text, y, f, fill, outline, stroke):
    d = ImageDraw.Draw(img)
    w = d.textlength(text, font=f)
    d.text(((W - w) / 2, y), text, font=f, fill=fill, stroke_width=stroke, stroke_fill=outline)


def frame(shot):
    # 遊戲畫面縮到外框內，圓角＋白邊＋陰影
    sw = 1000
    sh = round(shot.height * sw / shot.width)
    shot = shot.convert("RGB").resize((sw, sh), Image.LANCZOS)
    border, radius = 20, 72
    fw, fh = sw + border * 2, sh + border * 2
    card = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    mask_outer = Image.new("L", (fw, fh), 0)
    ImageDraw.Draw(mask_outer).rounded_rectangle((0, 0, fw - 1, fh - 1), radius + border, fill=255)
    card.paste((255, 255, 255, 255), (0, 0), mask_outer)
    mask_in = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask_in).rounded_rectangle((0, 0, sw - 1, sh - 1), radius, fill=255)
    card.paste(shot, (border, border), mask_in)
    return card, mask_outer


def compose(raw_dir, out_dir):
    for lang, items in CAPTIONS.items():
        dest = out_dir / lang
        dest.mkdir(parents=True, exist_ok=True)
        for i, (name, title, sub) in enumerate(items):
            img = background(i)
            tf = fit_font(title, W - 120, 132, 900)
            sf = fit_font(sub, W - 140, 68, 700)
            draw_text_center(img, title, 120, tf, TITLE_COLOR, (255, 255, 255), 10)
            draw_text_center(img, sub, 320, sf, SUB_COLOR, (255, 255, 255), 7)

            card, mask = frame(Image.open(raw_dir / f"{name}_{lang}.png"))
            x = (W - card.width) // 2
            y = 480
            shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            sm = Image.new("L", (W, H), 0)
            sm.paste(mask, (x, y + 24))
            shadow.putalpha(sm.point(lambda v: v * 70 // 255).filter(ImageFilter.GaussianBlur(28)))
            img = Image.alpha_composite(img, shadow)
            img.alpha_composite(card, (x, y))

            out = dest / f"{i + 1:02d}_{name}.png"
            img.convert("RGB").save(out, optimize=True)  # 蘋果不收透明圖
            print(out, img.size)


if __name__ == "__main__":
    raw = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "商店截圖"
    compose(raw, out)
