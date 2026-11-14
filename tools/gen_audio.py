"""用程式合成全部音效與背景音樂（不需要任何外部素材）。
用法：python tools/gen_audio.py   → 輸出到 assets/audio/*.wav
"""
import os
import wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def tone(f, dur, shape="soft", f1=None, decay=5.0, vol=1.0, sr=SR):
    n = int(sr * dur)
    t = np.arange(n) / sr
    freq = np.linspace(f, f1 if f1 else f, n)
    ph = 2 * np.pi * np.cumsum(freq) / sr
    if shape == "sine":
        w = np.sin(ph)
    elif shape == "bell":
        w = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.12 * np.sin(3.01 * ph)
    elif shape == "tri":
        w = 2 / np.pi * np.arcsin(np.sin(ph))
    else:  # soft
        w = np.sin(ph) + 0.22 * np.sin(2 * ph)
    e = np.exp(-decay * t / dur)
    a = max(1, int(sr * 0.004))
    e[:a] *= np.linspace(0, 1, a)
    r = max(1, int(sr * 0.008))
    e[-r:] *= np.linspace(1, 0, r)
    return w * e * vol


def noise(dur, smooth=6, decay=5.0, vol=1.0, sr=SR):
    n = int(sr * dur)
    x = rng.uniform(-1, 1, n)
    x = np.convolve(x, np.ones(smooth) / smooth, mode="same")
    t = np.arange(n) / sr
    e = np.exp(-decay * t / dur) * np.minimum(1, t / 0.004)
    return x * e * vol


def mix(parts, sr=SR):
    n = max(int(off * sr) + len(x) for off, x in parts)
    out = np.zeros(n)
    for off, x in parts:
        i = int(off * sr)
        out[i:i + len(x)] += x
    return out


def save(name, x, peak=0.8, sr=SR):
    x = x / max(1e-9, np.max(np.abs(x))) * peak
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data)
    print("%-8s %.2f 秒" % (name, len(x) / sr))


# ── 音效 ──
save("pick", tone(560, 0.09, f1=900, decay=4), 0.7)
save("drop", mix([(0, tone(250, 0.13, "sine", f1=125, decay=5)), (0, noise(0.03, vol=0.25))]), 0.8)
save("deny", mix([(0, tone(196, 0.10, "tri", decay=3)), (0.09, tone(156, 0.15, "tri", decay=3))]), 0.55)
save("flip", mix([(0, noise(0.12, smooth=3, decay=3, vol=0.3)), (0.07, tone(1320, 0.2, "bell", decay=6, vol=0.6))]), 0.7)
save("clear", mix([(i * 0.07, tone(f, 0.38, "bell", decay=5)) for i, f in enumerate([1047, 1319, 1568, 2093])]), 0.8)
save("win", mix([(0, tone(523, 0.5, "bell")), (0.14, tone(659, 0.5, "bell")), (0.28, tone(784, 0.5, "bell")),
                 (0.42, tone(1047, 0.5, "bell")), (0.62, tone(1319, 0.5, "bell")),
                 (0.85, tone(1047, 1.3, "bell", decay=3, vol=0.7)), (0.85, tone(1319, 1.3, "bell", decay=3, vol=0.7)),
                 (0.85, tone(1568, 1.3, "bell", decay=3, vol=0.7)), (0.85, tone(523, 1.3, "soft", decay=3, vol=0.6))]), 0.8)
save("button", tone(720, 0.06, f1=560, decay=5), 0.6)
save("undo", tone(780, 0.17, f1=380, decay=3), 0.6)
save("slot", tone(940, 0.07, "sine", decay=6), 0.55)
save("unlock", mix([(0, noise(0.02, smooth=2, vol=0.5)), (0.06, noise(0.02, smooth=2, vol=0.5)),
                    (0.11, tone(1568, 0.4, "bell")), (0.18, tone(2093, 0.5, "bell"))]), 0.75)
save("stuck", mix([(0, tone(392, 0.26, decay=3)), (0.22, tone(311, 0.42, decay=3))]), 0.6)
save("pop", mix([(0, tone(300, 0.12, "sine", f1=540, decay=4, vol=0.8)), (0, noise(0.05, vol=0.15))]), 0.55)
save("tick", tone(1250, 0.03, "sine", decay=5), 0.4)
save("step", mix([(0, tone(784, 0.1)), (0.09, tone(1175, 0.2))]), 0.6)

# ── 背景音樂：8 小節循環，音符尾巴會繞回開頭所以接縫無聲 ──
MSR = 22050
BEAT = 60.0 / 104.0
N = int(MSR * BEAT * 32)
bgm = np.zeros(N)


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def put(beat, m, beats, shape, vol, decay):
    x = tone(midi(m), BEAT * beats + 0.25, shape, decay=decay, vol=vol, sr=MSR)
    idx = (int(beat * BEAT * MSR) + np.arange(len(x))) % N
    np.add.at(bgm, idx, x)


CHORDS = [(48, [60, 64, 67]), (45, [57, 60, 64]), (41, [53, 57, 60]), (43, [55, 59, 62]),
          (48, [60, 64, 67]), (40, [52, 55, 59]), (41, [53, 57, 60]), (43, [55, 59, 62])]
MELODY = [
    [(0, 76, 1), (1, 79, 1), (2, 84, 2)],
    [(0, 81, 1), (1, 79, 1), (2, 76, 2)],
    [(0, 77, 1), (1, 81, 1), (2, 84, 1), (3, 81, 1)],
    [(0, 79, 2), (2, 74, 2)],
    [(0, 76, 1), (1, 79, 1), (2, 84, 1), (3, 86, 1)],
    [(0, 88, 2), (2, 83, 2)],
    [(0, 81, 1), (1, 84, 1), (2, 81, 1), (3, 77, 1)],
    [(0, 79, 1), (1, 83, 1), (2, 86, 2)],
]
for bar, (root, ch) in enumerate(CHORDS):
    b0 = bar * 4
    put(b0, root, 2, "soft", 0.42, 3.0)
    put(b0 + 2, root + 7, 2, "soft", 0.3, 3.0)
    for k in range(8):
        put(b0 + k * 0.5, ch[[0, 1, 2, 1][k % 4]] + 12, 0.5, "sine", 0.16, 4.0)
    for (bt, m, ln) in MELODY[bar]:
        put(b0 + bt, m, ln, "bell", 0.36, 3.5)
save("bgm", bgm, 0.5, sr=MSR)
