"""產生 100 關的關卡資料：隨機發牌 → 用解題程式確認解得開 → 寫成 scripts/level_data.gd
用法：python tools/gen_levels.py
每關格式："每欄格數,開放暫存格數;欄1|欄2|..."，字母代表動物種類，大寫 = 開局就翻開。
"""
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ───────── 難度表 ─────────
def cfg(L):
    """回傳 (動物種類, 欄數, 每欄格數, 開放暫存格, 開局翻開比例, 挑選方式)"""
    p = (L - 1) / 99.0
    T = 4 if L <= 4 else 5 if L <= 18 else 6 if L <= 50 else 7
    cap = 6 + round(6 * p ** 0.75)
    breather = L > 1 and L % 5 == 1          # 每 5 關後一關喘口氣
    boss = L % 10 == 0                        # 每 10 關一個魔王關
    spare = 2 if breather else 1
    if T + spare > 8:
        T = 8 - spare
    n = T + spare
    slots = 3 if L <= 60 else 2 if L <= 85 else 1
    reveal = 0.40 - 0.32 * p
    pick = "hard" if boss else "easy" if (breather or L in (61, 62, 86, 87)) else "mid"
    return T, n, cap, slots, reveal, pick


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
    lines, report = [], []
    for L in range(1, 101):
        T, n, cap, slots, reveal, pick = cfg(L)
        rng = random.Random(L * 1000003)
        cands = []
        tries = 0
        while len(cands) < 14 and tries < 200:
            tries += 1
            board = deal(T, n, cap, rng)
            if any(len(set(c)) == 1 and len(c) >= cap - 1 for c in board):
                continue                     # 開局就幾乎排好一欄的不要
            steps, nodes = solve(board, cap, slots)
            if steps >= 0:
                cands.append((nodes, steps, board))
        assert cands, "第 %d 關找不到解得開的盤面" % L
        cands.sort(key=lambda c: c[0])
        if pick == "hard":
            nodes, steps, board = cands[-1]
        elif pick == "easy":
            nodes, steps, board = cands[0]
        else:
            nodes, steps, board = cands[len(cands) // 2]
        text = []
        for c in board:
            text.append("".join(chr(97 + t).upper() if rng.random() < reveal else chr(97 + t) for t in c))
        lines.append('\t"%d,%d;%s",' % (cap, slots, "|".join(text)))
        report.append((L, T, n, cap, slots, round(reveal, 2), pick, steps, nodes, tries))
    out = os.path.join(ROOT, "scripts", "level_data.gd")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("extends RefCounted\n")
        f.write("## 100 關的關卡資料，由 tools/gen_levels.py 產生（每一關都經解題程式確認解得開），請勿手改。\n")
        f.write('## 格式："每欄格數,開放暫存格數;欄1|欄2|..."，字母 = 動物種類，大寫 = 開局就翻開，每欄由下往上。\n\n')
        f.write("const DATA: Array[String] = [\n")
        f.write("\n".join(lines))
        f.write("\n]\n")
    print("關  種類 欄 格數 暫存 翻開 挑選  解法步數 搜尋量 嘗試")
    for r in report:
        if r[0] <= 10 or r[0] % 5 == 0 or r[0] in (61, 86):
            print("%3d   %d   %d  %2d    %d   %.2f %-5s  %4d  %6d  %3d" % r)


if __name__ == "__main__":
    main()
