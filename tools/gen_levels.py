"""產生 300 關的關卡資料：隨機發牌 → 用解題程式確認解得開並算難度分數 → 每關挑最貼近目標直線的盤面 → 寫成 scripts/level_data.gd
用法：python tools/gen_levels.py 1 100（分段計算，可同時開幾段）→ 全部算完後 python tools/gen_levels.py merge
每關格式："每欄格數,開放暫存格數;欄1|欄2|..."，字母代表動物種類，大寫 = 開局就翻開。
"""
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ───────── 難度表（純直線） ─────────
TOTAL = 300            # 總關卡數
SCORE_FIRST = 25.0     # 第 1 關的目標難度分數
SCORE_LAST = 200.0     # 最後一關的目標難度分數


def progress(L):
    """這一關在整條難度線上的位置，0 = 第 1 關，1 = 最後一關"""
    return (L - 1) / float(TOTAL - 1)


def target(L):
    """每一關的目標難度分數：從第 1 關到最後一關是一條直線"""
    return SCORE_FIRST + (SCORE_LAST - SCORE_FIRST) * progress(L)


def score(steps, nodes):
    """難度分數 = 解法步數 ×（1 + 走錯路的程度）。照直覺走就能解開時，分數等於步數。"""
    import math
    return steps * (1.0 + 0.5 * math.log10(max(1.0, nodes / float(steps))))


def nominal(L):
    """這一關大概的盤面大小：(動物種類, 每欄格數, 開放暫存格, 開局翻開比例)"""
    p = progress(L)
    T = 4 if p <= 0.035 else 5 if p <= 0.175 else 6 if p <= 0.495 else 7
    cap = 6 + round(6 * p ** 0.75)
    slots = 2 if p <= 0.85 else 1            # 2026-11-17：拿掉 3 格暫存格那一段（使用者實測第 1 關太容易）
    return T, cap, slots, 0.40 - 0.32 * p


# ───────── 發牌與解題 ─────────
def deal(T, n, cap, rng):
    bag = [t for t in range(T) for _ in range(cap)]
    rng.shuffle(bag)
    total = len(bag)
    cols, idx = [], 0
    for i in range(n):
        h = total // n + (1 if i < total % n else 0)
        cols.append(tuple(bag[idx:idx + h]))
        idx += h
    return tuple(cols)


def toprun(c):
    r = 1
    while r < len(c) and c[-1 - r] == c[-1]:
        r += 1
    return r


def moves(cols, slots, cap, nslots):
    out = []
    n = len(cols)

    def done(nc, j):
        if len(nc[j]) == cap and len(set(nc[j])) == 1:
            nc[j] = ()

    for i in range(n):                       # 欄 → 欄（一次搬整串同款，放不下就搬放得下的數量）
        A = cols[i]
        if not A:
            continue
        x, r = A[-1], toprun(A)
        seen_empty = False
        for j in range(n):
            if j == i:
                continue
            B = cols[j]
            if len(B) >= cap:
                continue
            if B:
                if B[-1] != x:
                    continue
                pri = 0
            else:
                if r == len(A) or seen_empty:
                    continue
                seen_empty, pri = True, 3
            m = min(r, cap - len(B))
            nc = list(cols)
            nc[i], nc[j] = A[:-m], B + (x,) * m
            done(nc, j)
            out.append((pri, tuple(nc), slots))
    for s in set(slots):                     # 暫存格 → 欄
        seen_empty = False
        for j in range(n):
            B = cols[j]
            if len(B) >= cap:
                continue
            if B:
                if B[-1] != s:
                    continue
                pri = 1
            else:
                if seen_empty:
                    continue
                seen_empty, pri = True, 4
            nc = list(cols)
            nc[j] = B + (s,)
            done(nc, j)
            ns = list(slots)
            ns.remove(s)
            out.append((pri, tuple(nc), tuple(sorted(ns))))
    if len(slots) < nslots:                  # 欄 → 暫存格
        for i in range(n):
            A = cols[i]
            if not A:
                continue
            nc = list(cols)
            nc[i] = A[:-1]
            good = len(A) > 1 and any(cols[j] and cols[j][-1] == A[-2] for j in range(n) if j != i)
            out.append((5 if good else 6, tuple(nc), tuple(sorted(slots + (A[-1],)))))
    out.sort(key=lambda m: m[0])
    return out


def solve(cols, cap, nslots, limit=40000):
    """回傳 (解法步數, 搜尋節點數)；解不開或超過上限時步數為 -1"""
    seen, count = set(), 0
    stack = [(cols, (), 0)]
    while stack:
        c, s, d = stack.pop()
        if not any(c) and not s:
            return d, count
        key = (tuple(sorted(c)), s)
        if key in seen:
            continue
        seen.add(key)
        count += 1
        if count > limit:
            return -1, count
        for m in reversed(moves(c, s, cap, nslots)):
            stack.append((m[1], m[2], d + 1))
    return -1, count


# ───────── 主程式 ─────────
def main():
    """python gen_levels.py 起 迄 → 算這一段並存成分段檔；python gen_levels.py merge → 合併成 level_data.gd"""
    import json
    import sys
    parts_dir = os.path.join(ROOT, "tools", "level_parts")
    os.makedirs(parts_dir, exist_ok=True)
    if len(sys.argv) >= 2 and sys.argv[1] == "merge":
        merge(parts_dir)
        return
    first = int(sys.argv[1]) if len(sys.argv) >= 3 else 1
    last = int(sys.argv[2]) if len(sys.argv) >= 3 else TOTAL
    lines, report = [], []
    for L in range(first, last + 1):
        T0, cap0, slots, reveal = nominal(L)
        want = target(L)
        rng = random.Random(L * 1000003)
        best = None
        tested = 0
        for T in sorted({max(4, T0 - 1), T0}):
            for cap in sorted({max(5, cap0 - 1), cap0, min(12, cap0 + 1)}):
                for spare in (1, 2):
                    n = T + spare
                    if n > 8:
                        continue
                    for _ in range(int(os.environ.get("CANDS", "6"))):
                        board = deal(T, n, cap, rng)
                        if any(len(set(c)) == 1 and len(c) >= cap - 1 for c in board):
                            continue                 # 開局就幾乎排好一欄的不要
                        steps, nodes = solve(board, cap, slots, 30000)
                        if steps < 0:
                            continue
                        tested += 1
                        sc = score(steps, nodes)
                        # 最貼近目標直線的優先；差不多時選盤面大小接近預定值的
                        cost = abs(sc - want) + 0.6 * (abs(T - T0) * 3 + abs(cap - cap0) + (spare - 1))
                        if best is None or cost < best[0]:
                            best = (cost, sc, steps, nodes, board, T, n, cap)
        assert best, "第 %d 關找不到解得開的盤面" % L
        _, sc, steps, nodes, board, T, n, cap = best
        text = []
        for c in board:
            text.append("".join(chr(97 + t).upper() if rng.random() < reveal else chr(97 + t) for t in c))
        lines.append('\t"%d,%d;%s",' % (cap, slots, "|".join(text)))
        report.append([L, T, n, cap, slots, round(want, 1), round(sc, 1), steps, nodes, tested])
        print("第 %3d 關  目標 %5.1f  實際 %5.1f  (%d 種 %d 欄 %d 格 暫存 %d，步數 %d，搜尋 %d，候選 %d)"
              % (L, want, sc, T, n, cap, slots, steps, nodes, tested), flush=True)
    with open(os.path.join(parts_dir, "part_%03d_%03d.json" % (first, last)), "w", encoding="utf-8") as f:
        json.dump({"lines": lines, "report": report}, f)
    print("第 %d–%d 關完成" % (first, last))


def merge(parts_dir):
    import json
    lines, report = [], []
    for name in sorted(os.listdir(parts_dir)):
        if name.startswith("part_") and name.endswith(".json"):
            d = json.load(open(os.path.join(parts_dir, name), encoding="utf-8"))
            lines += d["lines"]
            report += d["report"]
    assert [r[0] for r in report] == list(range(1, TOTAL + 1)), "分段檔沒有湊齊 1–%d 關" % TOTAL
    boards = [l.split(";")[1].lower() for l in lines]
    assert len(set(boards)) == len(boards), "有重複的盤面"
    out = os.path.join(ROOT, "scripts", "level_data.gd")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("extends RefCounted\n")
        f.write("## %d 關的關卡資料，由 tools/gen_levels.py 產生（每一關都經解題程式確認解得開、盤面互不重複），請勿手改。\n" % TOTAL)
        f.write('## 格式："每欄格數,開放暫存格數;欄1|欄2|..."，字母 = 動物種類，大寫 = 開局就翻開，每欄由下往上。\n\n')
        f.write("const DATA: Array[String] = [\n")
        f.write("\n".join(lines))
        f.write("\n]\n")
    with open(os.path.join(ROOT, "tools", "level_report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, separators=(",", ":"))
    dev = [abs(r[6] - r[5]) for r in report]
    print("最大偏差 %.1f 分，平均偏差 %.1f 分" % (max(dev), sum(dev) / len(dev)))


if __name__ == "__main__":
    main()
