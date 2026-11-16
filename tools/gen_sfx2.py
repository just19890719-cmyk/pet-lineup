"""合成「整欄消除」與「過關」兩個音效（可愛、泡泡、音樂盒／木琴／鐘琴的音色，參考熱門益智遊戲的做法：
明亮的上行琶音 + 柔和的尾音）。全部自己合成，沒有第三方素材，不需要標示作者。
用法：python tools/gen_sfx2.py <輸出資料夾>
輸出：clear_a/b/c.wav、win_a/b/c.wav（44.1kHz、單聲道、16 位元）
"""
import sys, os, wave
import numpy as np

SR = 44100


def hz(name):
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    n = names[name[0]] + 12 * (int(name[1]) + 1)
    return 440.0 * 2 ** ((n - 69) / 12.0)


def tone(f, dur, parts, attack=0.003, tail=0.0):
    """parts：[(頻率倍數, 音量, 衰減秒數)]；回傳一個音"""
    n = int((dur + tail) * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for ratio, amp, dec in parts:
        y += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / dec)
    y *= np.minimum(1.0, t / attack)
    return y


BOX = [(1, 1.0, 0.35), (2, 0.45, 0.22), (3, 0.22, 0.14), (4, 0.10, 0.08)]            # 音樂盒
MARIMBA = [(1, 1.0, 0.28), (3.93, 0.38, 0.07), (9.2, 0.10, 0.03)]                      # 木琴
GLOCK = [(1, 1.0, 0.55), (2.76, 0.40, 0.30), (5.4, 0.18, 0.15), (8.9, 0.06, 0.08)]      # 鐘琴


def mix(events, total):
    y = np.zeros(int(total * SR))
    for start, sig, gain in events:
        i = int(start * SR)
        j = min(len(y), i + len(sig))
        y[i:j] += sig[:j - i] * gain
    return y


def reverb(y, wet=0.22, length=0.35, seed=1):
    rng = np.random.RandomState(seed)
    n = int(length * SR)
    ir = rng.randn(n) * np.exp(-np.arange(n) / SR / 0.09)
    ir[0] = 0
    ir /= np.abs(ir).sum() / 6.0
    w = np.convolve(y, ir)[:len(y) + n]
    out = np.zeros(len(w))
    out[:len(y)] += y
    out += wet * w
    return out


def finish(y, peak, maxdur=None):
    if maxdur is not None:
        y = y[:int(maxdur * SR)].copy()
    y = y / (np.abs(y).max() + 1e-9) * peak
    n = int((0.12 if maxdur is not None else 0.015) * SR)   # 超長的尾音用淡出收掉
    y[-n:] *= np.linspace(1, 0, n)
    return y


def bubble(dur=0.09):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 380 + 900 * (t / dur) ** 0.7          # 泡泡：音高快速往上滑
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / 0.04)


def make():
    out = {}
    # 消除 A：音樂盒向上三音 + 高音閃一下
    ev = [(0.00, tone(hz("G5"), 0.4, BOX), 0.8), (0.07, tone(hz("B5"), 0.4, BOX), 0.8),
          (0.14, tone(hz("D6"), 0.45, BOX), 0.85), (0.22, tone(hz("G6"), 0.6, BOX), 0.9)]
    out["clear_a"] = finish(reverb(mix(ev, 0.9)), 0.6, 0.85)
    # 消除 B：木琴五聲音階上行
    ev = [(0.00, tone(hz("C5"), 0.3, MARIMBA), 0.9), (0.055, tone(hz("E5"), 0.3, MARIMBA), 0.9),
          (0.11, tone(hz("G5"), 0.3, MARIMBA), 0.9), (0.165, tone(hz("C6"), 0.45, MARIMBA), 1.0)]
    out["clear_b"] = finish(reverb(mix(ev, 0.8), 0.15, 0.25), 0.6, 0.75)
    # 消除 C：泡泡「啵」一聲 + 鐘琴雙音
    ev = [(0.00, bubble(), 0.9), (0.06, tone(hz("C6"), 0.5, GLOCK), 0.7), (0.06, tone(hz("E6"), 0.5, GLOCK), 0.55)]
    out["clear_c"] = finish(reverb(mix(ev, 0.9), 0.25, 0.4), 0.6, 0.85)
    # 過關 A：音樂盒琶音一路往上，最後和弦拉長
    notes = ["C5", "E5", "G5", "C6", "E6", "G6"]
    ev = [(i * 0.085, tone(hz(n), 0.5, BOX), 0.75) for i, n in enumerate(notes)]
    t0 = len(notes) * 0.085
    for n in ["C6", "E6", "G6", "C7"]:
        ev.append((t0, tone(hz(n), 1.0, GLOCK), 0.5))
    out["win_a"] = finish(reverb(mix(ev, t0 + 1.4), 0.25, 0.5), 0.62, 1.9)
    # 過關 B：「多—咪—唆—多～」小號般的木琴短旋律 + 結尾和弦
    ev = [(0.00, tone(hz("C5"), 0.3, MARIMBA), 0.9), (0.13, tone(hz("E5"), 0.3, MARIMBA), 0.9),
          (0.26, tone(hz("G5"), 0.3, MARIMBA), 0.9)]
    for n in ["C6", "E6", "G6"]:
        ev.append((0.42, tone(hz(n), 0.9, GLOCK), 0.6))
    ev.append((0.42, tone(hz("C5"), 0.9, MARIMBA), 0.9))
    for k, n in enumerate(["G6", "C7", "E7"]):
        ev.append((0.75 + k * 0.07, tone(hz(n), 0.5, BOX), 0.35))
    out["win_b"] = finish(reverb(mix(ev, 1.9), 0.22, 0.45), 0.62, 1.9)
    # 過關 C：豎琴般快速上滑的五聲音階 + 長和弦
    pent = ["C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6", "G6"]
    ev = [(i * 0.055, tone(hz(n), 0.45, GLOCK), 0.55) for i, n in enumerate(pent)]
    t0 = len(pent) * 0.055
    for n in ["C6", "E6", "G6", "C7"]:
        ev.append((t0, tone(hz(n), 1.1, BOX), 0.5))
    out["win_c"] = finish(reverb(mix(ev, t0 + 1.5), 0.28, 0.55), 0.62, 1.9)
    return out


if __name__ == "__main__":
    dst = sys.argv[1]
    os.makedirs(dst, exist_ok=True)
    for k, y in make().items():
        with wave.open(os.path.join(dst, k + ".wav"), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())
        print(k, "%.2fs peak %.2f" % (len(y) / SR, np.abs(y).max()))
