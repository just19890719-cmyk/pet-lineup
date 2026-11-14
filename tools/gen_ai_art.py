# -*- coding: utf-8 -*-
"""用 OpenAI GPT 圖像模型生成萌寵排排站的美術，並直接覆蓋到 assets/。

用法：
  python tools/gen_ai_art.py            # 生成全部
  python tools/gen_ai_art.py cat dog    # 只生成指定項目
金鑰讀取順序：環境變數 OPENAI_API_KEY → tools/openai_key.txt
舊圖會先備份到 assets/_backup_<時間>/。
"""
import base64, io, json, os, shutil, sys, time, urllib.request, urllib.error
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL = "gpt-image-1"
STYLE = ("Cute kawaii chibi sticker illustration, flat vector style with soft cel shading, "
         "thick dark-brown outline (#5A3A28), big round shiny black eyes with white highlights, "
         "small pink blush cheeks, gentle smile, front-facing head only, centered, filling about 90% of the canvas, "
         "clean edges, no text, no watermark, no frame, no shadow on the ground, transparent background.")

ANIMALS = {
    "cat":    "an orange tabby kitten face with pointy ears with pink insides, three small forehead stripes and short whiskers",
    "dog":    "a light-brown puppy face with big floppy dark-brown ears, a cream muzzle, a small black nose and a tiny pink tongue",
    "panda":  "a white baby panda face with round black ears and black eye patches around the eyes",
    "rabbit": "a white bunny face with tall upright ears with pink insides, a tiny pink nose and two small front teeth",
    "bear":   "a brown teddy bear cub face with round ears, a light-tan muzzle and a black nose",
    "pig":    "a pink piglet face with small triangular ears and a big oval pink snout with two nostrils",
    "frog":   "a bright green frog face with big bulging eyes on top of the head and a wide happy smile with a light-green belly-colored lower face",
    "chick":  "a round yellow baby chick face with a small orange triangle beak, tiny wing tips at the sides and a little tuft of feathers on top",
    "fox":    "an orange fox kit face with large pointed ears, white cheeks and a cream lower face",
    "koala":  "a grey koala face with big round fluffy ears with light insides and a large dark oval nose",
    "lion":   "a golden lion cub face with a fluffy scalloped orange mane all around, a cream muzzle",
    "cow":    "a white calf face with black spots, small cream horns, pink ears sticking out sideways and a big pink muzzle with nostrils",
}

JOBS = {}
for k, desc in ANIMALS.items():
    JOBS[k] = dict(out=f"assets/animals/{k}.png", size="1024x1024", bg="transparent", px=(512, 512),
                   prompt=f"{STYLE} Subject: {desc}.")
JOBS["tile_front"] = dict(out="assets/ui/tile_front.png", size="1024x1024", bg="transparent", px=(256, 256),
    prompt="A single cute mobile puzzle game tile, rounded square with large corner radius, soft cream-white face (#FFF6E8) "
           "with a subtle top highlight and a slightly darker warm beige bottom edge for thickness, thin warm-brown outline, "
           "completely empty center with no icon, no text, flat casual game UI style, centered, filling about 92% of the canvas, transparent background.")
JOBS["tile_hidden"] = dict(out="assets/ui/tile_hidden.png", size="1024x1024", bg="transparent", px=(256, 256),
    prompt="A single cute mobile puzzle game mystery tile, rounded square with large corner radius, glossy purple gradient (#9B7BFF to #6A4BE0) "
           "with a darker purple bottom edge for thickness, a big bold white question mark in the center with a soft shadow, "
           "two tiny white sparkles in the corners, flat casual game UI style, centered, filling about 92% of the canvas, transparent background.")
JOBS["background"] = dict(out="assets/ui/background.png", size="1024x1536", bg="opaque", px=(720, 1280),
    prompt="Vertical mobile puzzle game background, soft pastel vertical gradient from light pink at the top to cream in the middle "
           "to pale mint green at the bottom, scattered faint white paw prints and tiny soft dots at low contrast, very calm and uncluttered, "
           "no characters, no text, no UI, no frame, cute kawaii style.")
JOBS["sparkle"] = dict(out="assets/fx/sparkle.png", size="1024x1024", bg="transparent", px=(128, 128),
    prompt="A single cute four-pointed sparkle star game effect, bright white core fading to soft pale-yellow glow at the tips, "
           "clean symmetric shape, centered, filling about 80% of the canvas, no text, transparent background.")


def load_key():
    k = os.environ.get("OPENAI_API_KEY", "").strip()
    if k:
        return k
    p = os.path.join(ROOT, "tools", "openai_key.txt")
    if os.path.exists(p):
        with open(p, encoding="utf-8") as f:
            return f.read().strip()
    return ""


def generate(key, job):
    body = dict(model=MODEL, prompt=job["prompt"], size=job["size"], background=job["bg"],
                quality="medium", n=1, output_format="png")
    req = urllib.request.Request("https://api.openai.com/v1/images/generations",
                                 data=json.dumps(body).encode("utf-8"),
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        data = json.loads(r.read().decode("utf-8"))
    return base64.b64decode(data["data"][0]["b64_json"])


def save(raw, job):
    img = Image.open(io.BytesIO(raw)).convert("RGBA")
    if job["bg"] == "transparent":
        box = img.getbbox()
        if box:
            img = img.crop(box)
        w, h = img.size; s = max(w, h)
        sq = Image.new("RGBA", (s, s), (0, 0, 0, 0)); sq.paste(img, ((s - w) // 2, (s - h) // 2))
        img = sq
    img = img.resize(job["px"], Image.LANCZOS)
    img.save(os.path.join(ROOT, job["out"]))


def main():
    key = load_key()
    if not key:
        print("找不到 OpenAI 金鑰。請把金鑰貼進 tools/openai_key.txt（只放金鑰一行），或設定環境變數 OPENAI_API_KEY。")
        sys.exit(1)
    names = sys.argv[1:] or list(JOBS)
    bad = [n for n in names if n not in JOBS]
    if bad:
        print("不認得的項目：", bad, "可用：", list(JOBS)); sys.exit(1)
    bk = os.path.join(ROOT, "assets", "_backup_" + time.strftime("%Y%m%d_%H%M%S"))
    ok, fail = [], []
    for i, n in enumerate(names, 1):
        job = JOBS[n]; dst = os.path.join(ROOT, job["out"])
        print(f"[{i}/{len(names)}] 生成 {n} ...", flush=True)
        try:
            raw = generate(key, job)
            if os.path.exists(dst):
                os.makedirs(os.path.join(bk, os.path.dirname(job["out"])), exist_ok=True)
                shutil.copy2(dst, os.path.join(bk, job["out"]))
            save(raw, job); ok.append(n); print("   完成 →", job["out"])
        except urllib.error.HTTPError as e:
            msg = e.read().decode("utf-8", "ignore")[:300]
            print("   失敗 HTTP", e.code, msg); fail.append(n)
            if e.code in (401, 403):
                print("金鑰無效或沒有圖像權限，停止。"); break
        except Exception as e:
            print("   失敗：", e); fail.append(n)
    print(f"\n成功 {len(ok)}，失敗 {len(fail)} {fail if fail else ''}")
    if os.path.isdir(bk):
        print("舊圖已備份到：", bk)
    # 讓 Godot 重新匯入
    for n in ok:
        imp = os.path.join(ROOT, JOBS[n]["out"] + ".import")
        if os.path.exists(imp):
            os.remove(imp)


if __name__ == "__main__":
    main()
