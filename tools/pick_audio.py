"""把外部素材包裡挑好的音效整理成遊戲用的檔案（去頭尾空白、統一音量），輸出到 assets/audio/。
素材來源（全部是 CC0，可商用、不用標示作者）：
  - Kenney（kenney.nl）：Interface Sounds、Casino Audio、Music Jingles
  - OpenGameArt：kurt 的「Feel good island」（背景音樂，CC0 與 OGA-BY 3.0 雙授權，這裡採用 CC0）
用法：python tools/pick_audio.py <soundfile 安裝位置> <Kenney 解壓縮資料夾> <背景音樂 ogg>
想換某個動作的聲音：改下面 PICKS 的檔名再重跑。
"""
import os
import shutil
import sys
import wave

sys.path.insert(0, sys.argv[1])
import numpy as np
import soundfile as sf

KENNEY, BGM = sys.argv[2], sys.argv[3]
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")

# 遊戲裡的動作 → (素材包, 檔名, 最大音量 0~1)
PICKS = {
    "pick":   ("interface-sounds", "select_005", 0.50),        # 拿起動物
    "drop":   ("interface-sounds", "drop_002", 0.55),          # 放下
    "deny":   ("interface-sounds", "error_008", 0.40),         # 不能放
    "flip":   ("casino-audio", "card-slide-1", 0.50),          # 問號翻開（翻牌聲）
    "clear":  ("interface-sounds", "confirmation_002", 0.60),  # 整欄消除
    "win":    ("music-jingles", "jingles_STEEL02", 0.60),      # 過關（鋼鼓，音一路往上）
    "button": ("interface-sounds", "click_001", 0.40),         # 按鈕
    "undo":   ("interface-sounds", "back_002", 0.45),          # 撤回
    "slot":   ("interface-sounds", "glass_006", 0.40),         # 放進暫存格
    "unlock": ("interface-sounds", "maximize_004", 0.55),      # 解鎖
    "stuck":  ("music-jingles", "jingles_PIZZI01", 0.50),      # 卡住（撥弦，音往下）
    "pop":    ("casino-audio", "card-slide-1", 0.45),          # 對話框彈出（使用者指定；原本的 maximize_007 不喜歡）
    "tick":   ("interface-sounds", "tick_004", 0.22),          # 開局方塊掉落
    "step":   ("interface-sounds", "toggle_002", 0.45),        # 教學確認
}


def find(pack, name):
    for root, _, files in os.walk(os.path.join(KENNEY, pack)):
        if name + ".ogg" in files:
            return os.path.join(root, name + ".ogg")
    raise FileNotFoundError("%s/%s" % (pack, name))


os.makedirs(OUT, exist_ok=True)
for key, (pack, name, peak) in PICKS.items():
    x, sr = sf.read(find(pack, name))
    if x.ndim > 1:
        x = x.mean(axis=1)
    loud = np.nonzero(np.abs(x) > np.abs(x).max() * 0.01)[0]
    x = x[loud[0]:loud[-1] + 1]
    n_out = max(1, int(sr * 0.012))
    x[-n_out:] *= np.linspace(1, 0, n_out)
    x = x / np.abs(x).max() * peak
    with wave.open(os.path.join(OUT, key + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    print("%-7s ← %-18s %.2f 秒" % (key, name, len(x) / sr))
shutil.copyfile(BGM, os.path.join(OUT, "bgm.ogg"))
print("bgm     ← %s  %d KB" % (os.path.basename(BGM), os.path.getsize(BGM) // 1024))
with open(os.path.join(OUT, "CREDITS.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write("Audio credits\n=============\n\n")
    f.write("Sound effects: Kenney (https://kenney.nl) - Interface Sounds, Casino Audio, Music Jingles\n")
    f.write("License: Creative Commons Zero (CC0) https://creativecommons.org/publicdomain/zero/1.0/\n\n")
    f.write("Music: \"Feel good island\" by kurt (https://opengameart.org/content/feel-good-island)\n")
    f.write("License: CC0 (dual-licensed CC0 / OGA-BY 3.0; used here under CC0)\n\n")
    f.write("Files:\n")
    for key, (pack, name, _) in PICKS.items():
        f.write("  %s.wav <- %s/%s.ogg\n" % (key, pack, name))
    f.write("  bgm.ogg <- island_0.ogg\n")
