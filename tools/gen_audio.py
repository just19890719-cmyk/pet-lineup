"""用程式合成全部音效與背景音樂（不需要任何外部素材）。第二版：
  - 音色用「模態合成」模擬木琴、鐵琴、卡林巴這類敲擊樂器的泛音結構，另有撥弦與柔和的合成鋪底
  - 所有聲音都加殘響；背景音樂的殘響是環狀計算，循環接縫無聲
  - 音量以平均響度統一
用法：python tools/gen_audio.py [soundfile 安裝位置]
  有裝 soundfile 時背景音樂輸出成立體聲 bgm.ogg，否則輸出單聲道 bgm.wav
輸出到 assets/audio/
"""
import os
import sys
import wave
import numpy as np

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv[1])
try:
    import soundfile as sf
except Exception:
    sf = None

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(11)


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def fade(x, a=0.003, r=0.02):
    n = len(x)
    na, nr = max(1, int(SR * a)), max(1, min(n, int(SR * r)))
    x = x.copy()
    x[:na] *= np.linspace(0, 1, na)
    x[-nr:] *= np.linspace(1, 0, nr)
    return x


def lowpass(x, cutoff):
    """簡單的一階低通，連做兩次讓高頻收得更乾淨"""
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    for _ in range(2):
        acc = 0.0
        for i in range(len(x)):
            acc = (1 - a) * x[i] + a * acc
            y[i] = acc
        x = y.copy()
    return x


def lp_fft(x, cutoff, slope=4.0):
    """用頻域做低通（快，適合長的聲音）"""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1.0 / (1.0 + (f / cutoff) ** slope)
    return np.fft.irfft(X, len(x))


def hp_fft(x, cutoff, slope=4.0):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1.0 - 1.0 / (1.0 + (f / cutoff) ** slope)
    return np.fft.irfft(X, len(x))


# ───────── 樂器 ─────────
def modal(freq, dur, partials, strike=0.5, bright=1.0):
    """模態合成：每個泛音各自的頻率比、音量、衰減時間。敲擊樂器的音色就是這樣來的。"""
    n = int(SR * dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, amp, decay in partials:
        f = freq * ratio
        if f > 16000:
            continue
        out += amp * bright ** (ratio - 1) * np.sin(2 * np.pi * f * t) * np.exp(-t / decay)
    # 敲下去那一瞬間的「喀」聲
    nc = int(SR * 0.012)
    click = rng.uniform(-1, 1, nc) * np.exp(-np.arange(nc) / (SR * 0.003))
    out[:nc] += strike * 0.25 * lp_fft(np.pad(click, (0, 256)), 3500 + freq * 2)[:nc]
    return fade(out, 0.001, 0.03)


def marimba(m, dur=0.9, vol=1.0):
    f = midi(m)
    d = 0.55 * (220.0 / f) ** 0.35
    return vol * modal(f, dur, [(1, 1.0, d), (4.0, 0.28, d * 0.22), (9.2, 0.08, d * 0.08)], strike=0.7)


def kalimba(m, dur=1.1, vol=1.0):
    f = midi(m)
    d = 0.8 * (330.0 / f) ** 0.3
    return vol * modal(f, dur, [(1, 1.0, d), (2.0, 0.12, d * 0.5), (5.4, 0.22, d * 0.12), (8.3, 0.06, d * 0.06)], strike=0.5)


def glock(m, dur=1.4, vol=1.0):
    f = midi(m)
    d = 1.1 * (880.0 / f) ** 0.3
    return vol * modal(f, dur, [(1, 1.0, d), (2.76, 0.35, d * 0.45), (5.4, 0.16, d * 0.25), (8.93, 0.06, d * 0.12)], strike=0.35)


def pluck(m, dur=0.8, vol=1.0):
    """撥弦（Karplus-Strong）"""
    f = midi(m)
    n = int(SR * dur)
    p = max(2, int(SR / f))
    buf = lp_fft(np.pad(rng.uniform(-1, 1, p), (0, 512)), 4000)[:p]
    out = np.empty(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = 0.996 * 0.5 * (buf[i % p] + buf[(i + 1) % p])
    return vol * fade(out, 0.001, 0.05)


def pad(notes, dur, vol=1.0):
    """柔和的鋪底和弦：每個音疊三個微微走音的聲部，慢慢進來、慢慢出去"""
    n = int(SR * dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for m in notes:
        for cents in (-7, 0, 6):
            f = midi(m) * 2 ** (cents / 1200.0)
            ph = rng.uniform(0, 2 * np.pi)
            for h, a in ((1, 1.0), (2, 0.35), (3, 0.14), (4, 0.06)):
                out += a * np.sin(2 * np.pi * f * h * t + ph * h)
    env = np.minimum(1, t / 0.5) * np.minimum(1, (dur - t) / 0.7)
    return vol * out * np.clip(env, 0, 1) / (len(notes) * 3)


def bass(m, dur=0.9, vol=1.0):
    f = midi(m)
    n = int(SR * dur)
    t = np.arange(n) / SR
    out = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)) * np.exp(-t / 0.45)
    return vol * fade(out, 0.006, 0.05)


def shaker(vol=1.0, dur=0.07):
    n = int(SR * dur)
    x = hp_fft(np.pad(rng.uniform(-1, 1, n), (0, 512)), 5000)[:n]
    return vol * x * np.exp(-np.arange(n) / (SR * 0.018))


def kick(vol=1.0):
    n = int(SR * 0.22)
    t = np.arange(n) / SR
    f = 46 + 70 * np.exp(-t / 0.03)
    return vol * fade(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09), 0.001, 0.03)


def whoosh(dur, f0, f1, vol=1.0):
    """濾過的氣音，中心頻率從 f0 滑到 f1"""
    n = int(SR * dur)
    x = rng.uniform(-1, 1, n)
    t = np.arange(n) / SR
    out = np.zeros(n)
    blocks = 24
    for b in range(blocks):
        i0, i1 = n * b // blocks, n * (b + 1) // blocks
        fc = f0 * (f1 / f0) ** (b / (blocks - 1))
        seg = np.zeros(n)
        seg[i0:i1] = x[i0:i1]
        out += hp_fft(lp_fft(seg, fc * 1.6), fc * 0.6)
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    return vol * out * env


def blip(f0, f1, dur, vol=1.0, decay=0.05):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = f0 * (f1 / f0) ** np.clip(t / dur, 0, 1)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return vol * fade((np.sin(ph) + 0.18 * np.sin(2 * ph)) * np.exp(-t / decay), 0.002, 0.01)


# ───────── 混音 ─────────
def mix(parts, tail=0.0):
    n = max(int(off * SR) + len(x) for off, x in parts) + int(tail * SR)
    out = np.zeros(n)
    for off, x in parts:
        i = int(off * SR)
        out[i:i + len(x)] += x
    return out


def make_ir(seconds, seed, damp=3500.0):
    """合成一段殘響的脈衝響應：指數衰減的雜訊，高頻衰減得快"""
    r = np.random.default_rng(seed)
    n = int(SR * seconds)
    t = np.arange(n) / SR
    ir = lp_fft(r.normal(0, 1, n), damp) * np.exp(-t / (seconds / 5.5))
    ir[:int(SR * 0.012)] *= np.linspace(0, 1, int(SR * 0.012))   # 一點點預延遲
    return ir / np.sqrt(np.sum(ir ** 2))


def reverb(x, wet=0.2, seconds=1.1, seed=3, circular=False):
    ir = make_ir(seconds, seed)
    if circular:
        n = len(x)
        y = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ir, n), n)
    else:
        n = len(x) + len(ir)
        y = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
        x = np.pad(x, (0, n - len(x)))
    return x + wet * y


def soft_clip(x):
    return np.tanh(x * 1.2) / np.tanh(1.2)


def loudness(x, target):
    """以最大聲那 0.1 秒的平均能量當響度，統一到 target；峰值超過就再壓回來"""
    w = max(1, int(SR * 0.1))
    e = np.convolve(x ** 2 if x.ndim == 1 else np.mean(x ** 2, axis=1), np.ones(w) / w, mode="same")
    x = x * (target / max(1e-9, np.sqrt(e.max())))
    peak = np.max(np.abs(x))
    return x * min(1.0, 0.92 / peak)


def save_wav(name, x):
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def sfx(name, x, level, wet=0.16, rv=0.9):
    x = reverb(x, wet, rv)
    # 尾巴小到聽不見的地方切掉，並做淡出
    env = np.abs(x)
    last = np.nonzero(env > env.max() * 0.004)[0]
    x = fade(x[:last[-1] + 1], 0.001, 0.06)
    x = loudness(soft_clip(x), level)
    save_wav(name, x)
    print("%-7s %.2f 秒  峰值 %.2f" % (name, len(x) / SR, np.max(np.abs(x))))


# ───────── 音效 ─────────
sfx("pick", mix([(0, blip(420, 760, 0.09, 0.9, 0.04)), (0, kalimba(79, 0.25, 0.35))]), 0.17, 0.10, 0.5)
sfx("drop", mix([(0, marimba(55, 0.35, 1.0)), (0, blip(150, 90, 0.08, 0.5, 0.03))]), 0.20, 0.12, 0.5)
sfx("deny", mix([(0, marimba(50, 0.22, 0.9)), (0.10, marimba(46, 0.3, 0.9))]), 0.16, 0.10, 0.5)
sfx("flip", mix([(0, whoosh(0.16, 900, 3800, 0.5)), (0.08, glock(88, 0.6, 0.55))]), 0.15, 0.20, 0.9)
sfx("clear", mix([(i * 0.075, glock(m, 1.1, 0.8)) for i, m in enumerate([84, 88, 91, 96])]
               + [(0.0, kalimba(72, 0.8, 0.5)), (0.22, whoosh(0.5, 3000, 9000, 0.12))]), 0.20, 0.28, 1.4)
sfx("win", mix([(0.00, marimba(65, 0.7)), (0.12, marimba(69, 0.7)), (0.24, marimba(72, 0.7)),
                (0.36, glock(77, 1.2, 0.9)), (0.48, glock(81, 1.2, 0.9)), (0.60, glock(84, 1.2, 0.9)),
                (0.84, glock(89, 2.2, 1.0)), (0.84, glock(84, 2.2, 0.7)), (0.84, glock(81, 2.2, 0.7)),
                (0.84, pad([65, 69, 72], 2.2, 0.9)), (0.84, bass(41, 1.6, 0.8)),
                (0.95, whoosh(0.9, 3000, 10000, 0.14))]), 0.20, 0.30, 1.8)
sfx("button", mix([(0, marimba(76, 0.14, 0.9)), (0, blip(900, 700, 0.03, 0.25, 0.012))]), 0.14, 0.08, 0.4)
sfx("undo", mix([(0, whoosh(0.2, 2600, 700, 0.5)), (0.05, pluck(67, 0.3, 0.5)), (0.13, pluck(62, 0.35, 0.5))]), 0.15, 0.14, 0.6)
sfx("slot", mix([(0, kalimba(84, 0.4, 0.9))]), 0.14, 0.12, 0.6)
sfx("unlock", mix([(0, blip(2200, 1500, 0.025, 0.5, 0.01)), (0.07, blip(2600, 1800, 0.025, 0.5, 0.01)),
                   (0.15, glock(84, 0.9, 0.8)), (0.24, glock(91, 1.2, 0.9)), (0.26, whoosh(0.5, 4000, 10000, 0.1))]), 0.18, 0.26, 1.2)
sfx("stuck", mix([(0, marimba(64, 0.5, 0.9)), (0.2, marimba(60, 0.5, 0.9)), (0.42, marimba(57, 0.8, 0.9)),
                  (0.0, pad([57, 60], 1.1, 0.5))]), 0.16, 0.24, 1.2)
sfx("pop", mix([(0, blip(300, 620, 0.07, 1.0, 0.03)), (0.02, whoosh(0.1, 1500, 3000, 0.15))]), 0.14, 0.10, 0.5)
sfx("tick", mix([(0, marimba(84, 0.06, 0.8))]), 0.09, 0.05, 0.3)
sfx("step", mix([(0, kalimba(79, 0.35, 0.9)), (0.1, kalimba(84, 0.6, 0.9))]), 0.15, 0.18, 0.8)

# ───────── 背景音樂：24 小節（約 60 秒），三段，F 大調，每分鐘 96 拍 ─────────
BEAT = 60.0 / 96.0
N = int(round(SR * BEAT * 4 * 24))
tracks = {k: np.zeros(N) for k in ("pad", "bass", "arp", "mel", "perc")}


def put(track, beat, x, vol=1.0):
    """把一個音放進軌道；超出尾端的部分繞回開頭，循環才接得起來"""
    i0 = int(round(beat * BEAT * SR))
    idx = (i0 + np.arange(len(x))) % N
    np.add.at(tracks[track], idx, x * vol)


F, C, Dm, Bb, Am, Gm = [53, 57, 60], [48, 52, 55], [50, 53, 57], [46, 50, 53], [45, 48, 52], [43, 46, 50]
# (和弦, 低音)
CHORDS = [(F, 41), (C, 40), (Dm, 38), (Bb, 34), (F, 41), (C, 36), (Bb, 34), (C, 36),
          (F, 41), (Am, 33), (Dm, 38), (Bb, 34), (Gm, 31), (C, 36), (F, 41), (F, 41),
          (Bb, 34), (C, 36), (Am, 33), (Dm, 38), (Bb, 34), (C, 36), (F, 41), (C, 36)]
MELODY = [
    [(0, 81, 1.5), (1.5, 84, .5), (2, 81, 1), (3, 77, 1)], [(0, 79, 2), (2, 76, 1), (3, 79, 1)],
    [(0, 81, 1.5), (1.5, 77, .5), (2, 74, 2)], [(0, 77, 1), (1, 74, 1), (2, 77, 2)],
    [(0, 81, 1.5), (1.5, 84, .5), (2, 86, 1), (3, 84, 1)], [(0, 79, 2), (2, 84, 1), (3, 79, 1)],
    [(0, 77, 1), (1, 79, 1), (2, 81, 1), (3, 77, 1)], [(0, 79, 3), (3, 76, 1)],
    [(0, 84, 1), (1, 81, 1), (2, 84, 1), (3, 86, 1)], [(0, 88, 2), (2, 84, 2)],
    [(0, 86, 1), (1, 84, 1), (2, 81, 2)], [(0, 77, 1), (1, 81, 1), (2, 82, 2)],
    [(0, 82, 1), (1, 79, 1), (2, 74, 2)], [(0, 76, 1), (1, 79, 1), (2, 84, 2)],
    [(0, 81, 1), (1, 79, 1), (2, 77, 2)], [(0, 77, 4)],
    [(0, 74, 1), (1, 77, 1), (2, 82, 2)], [(0, 79, 1), (1, 84, 1), (2, 88, 2)],
    [(0, 84, 1.5), (1.5, 81, .5), (2, 76, 2)], [(0, 77, 1), (1, 81, 1), (2, 86, 2)],
    [(0, 82, 1), (1, 81, 1), (2, 77, 1), (3, 74, 1)], [(0, 76, 1), (1, 79, 1), (2, 84, 1), (3, 88, 1)],
    [(0, 89, 2), (2, 84, 2)], [(0, 79, 2), (2, 76, 1), (3, 79, 1)],
]
for bar, (ch, root) in enumerate(CHORDS):
    b0 = bar * 4
    section = bar // 8            # 0 = 第一段、1 = 第二段、2 = 第三段
    put("pad", b0, pad([m + 12 for m in ch], BEAT * 4 + 0.6), 0.9)
    put("bass", b0, bass(root, BEAT * 1.8), 1.0)
    put("bass", b0 + 2, bass(root + 7 if root + 7 < 46 else root, BEAT * 1.6), 0.8)
    pattern = [0, 1, 2, 1, 0, 2, 1, 2] if section != 1 else [0, 2, 1, 2, 0, 1, 2, 1]
    for k in range(8):
        if section == 0 and bar < 2 and k % 2 == 1:
            continue                          # 開頭兩小節稀疏一點，慢慢進來
        put("arp", b0 + k * 0.5, kalimba(ch[pattern[k]] + 12, 0.7), 0.5 + 0.12 * (k % 4 == 0))
    for (bt, m, ln) in MELODY[bar]:
        inst = glock(m, max(0.9, BEAT * ln + 0.5)) if section == 1 else marimba(m, max(0.7, BEAT * ln + 0.3))
        put("mel", b0 + bt, inst, 1.0)
        if section == 2 and ln >= 2:
            put("mel", b0 + bt, glock(m + 12, 1.2), 0.3)     # 第三段長音加一層高八度的亮色
    if section >= 1:
        for k in range(4):
            put("perc", b0 + k + 0.5, shaker(0.5))
            put("perc", b0 + k, shaker(0.22))
        put("perc", b0, kick(0.9))
        put("perc", b0 + 2.5, kick(0.6))
    else:
        for k in range(4):
            put("perc", b0 + k + 0.5, shaker(0.3))

# 各軌音量、左右位置（0 = 左、1 = 右）、殘響量
MIXER = {"pad": (0.55, 0.5, 0.35), "bass": (0.75, 0.5, 0.05), "arp": (0.55, 0.3, 0.30),
         "mel": (0.80, 0.62, 0.32), "perc": (0.40, 0.55, 0.12)}
left, right = np.zeros(N), np.zeros(N)
for name, (vol, pan, wet) in MIXER.items():
    dry = tracks[name] * vol
    wl = np.fft.irfft(np.fft.rfft(dry) * np.fft.rfft(make_ir(1.8, 21), N), N)
    wr = np.fft.irfft(np.fft.rfft(dry) * np.fft.rfft(make_ir(1.8, 22), N), N)
    left += dry * np.sqrt(1 - pan) * 1.2 + wet * wl
    right += dry * np.sqrt(pan) * 1.2 + wet * wr
stereo = np.stack([left, right], axis=1)
stereo = lp_fft(stereo[:, 0], 11000)[:, None] * [1, 0] + lp_fft(stereo[:, 1], 11000)[:, None] * [0, 1]
stereo = soft_clip(stereo / np.max(np.abs(stereo)) * 0.9)
stereo = loudness(stereo, 0.16)
for old in ("bgm.wav", "bgm.ogg"):
    p = os.path.join(OUT, old)
    if os.path.exists(p):
        os.remove(p)
if sf is not None:
    # 一次寫整首會讓編碼器當掉，所以分小段寫
    with sf.SoundFile(os.path.join(OUT, "bgm.ogg"), "w", SR, 2, format="OGG", subtype="VORBIS") as f:
        for i in range(0, N, 8192):
            f.write(stereo[i:i + 8192])
    print("bgm     %.1f 秒  立體聲 ogg  %d KB" % (N / SR, os.path.getsize(os.path.join(OUT, "bgm.ogg")) // 1024))
else:
    save_wav("bgm", stereo.mean(axis=1))
    print("bgm     %.1f 秒  單聲道 wav（沒有 soundfile，檔案會比較大）" % (N / SR))
