"""新規則（問號沒翻開不能消除）下，換掉解題搜尋量太大的盤面。
用法：python tools/replace_heavy.py [上限，預設 30000] [先前算好的結果 json（可省，格式 [版本, 關卡, 步數, 節點數]）]
做法：用 solver2 重新算 scripts/level_data.gd 與 scripts/level_variants.gd 裡每個盤面；
搜尋節點超過上限（或解不開）的，用同一關的盤面大小重新發牌，挑解得開、搜尋量在上限內、
難度分數最貼近 gen_levels.target(L) 的新盤面，直接改寫那兩個檔案。盤面互不重複。
"""
import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_levels as G  # noqa: E402
import solver2  # noqa: E402

LIMIT = int(sys.argv[1]) if len(sys.argv) > 1 else 30000
BOARD = re.compile(r'"(\d+,\d+;[^"]+)"')


def load(path):
    return open(path, encoding="utf-8", newline="").read()


def key(text):
    return text.split(";")[1].lower()


def main():
    data_p = os.path.join(ROOT, "scripts", "level_data.gd")
    var_p = os.path.join(ROOT, "scripts", "level_variants.gd")
    data, var = load(data_p), load(var_p)
    base = BOARD.findall(data)
    blocks = var.split("\n\t[\n")
    ex = [BOARD.findall(b) for b in blocks[1:]]
    sets = [base] + ex
    used = {key(b) for s in sets for b in s}
    todo = []
    if len(sys.argv) > 2:
        import json
        for k, L, steps, nodes in json.load(open(sys.argv[2])):
            if steps < 0 or nodes > LIMIT:
                todo.append((k, L, sets[k][L - 1]))
    else:
        for k, s in enumerate(sets):
            assert len(s) == G.TOTAL
            for i, b in enumerate(s):
                cap, ns, cols = solver2.parse(b)
                steps, nodes = solver2.solve(cols, cap, ns, LIMIT)
                if steps < 0:
                    todo.append((k, i + 1, b))
    print("搜尋量超過 %d 或解不開的盤面：%d 個" % (LIMIT, len(todo)), flush=True)
    repl = {}
    for k, L, old in todo:
        head, body = old.split(";")
        cap, ns = [int(x) for x in head.split(",")]
        parts = body.split("|")
        n = len(parts)
        total = sum(len(p) for p in parts)
        T = total // cap
        reveal = G.nominal(L)[3]
        want = G.target(L)
        rng = random.Random(L * 7919 + k * 104729 + 17)
        best = None
        for _ in range(30):
            board = G.deal(T, n, cap, rng)
            if any(len(set(c)) == 1 and len(c) >= cap - 1 for c in board):
                continue
            text = "|".join("".join(chr(97 + t).upper() if rng.random() < reveal else chr(97 + t) for t in c) for c in board)
            full = "%d,%d;%s" % (cap, ns, text)
            if key(full) in used:
                continue
            c_cap, c_ns, cols = solver2.parse(full)
            steps, nodes = solver2.solve(cols, c_cap, c_ns, LIMIT)
            if steps < 0:
                continue
            cost = abs(G.score(steps, nodes) - want)
            if best is None or cost < best[0]:
                best = (cost, full, steps, nodes)
            if best[0] < 12:
                break
        assert best, "第 %d 關（版本 %d）找不到替代盤面" % (L, k)
        used.add(key(best[1]))
        repl[(k, L)] = (old, best[1])
        print("第 %3d 關 版本 %d：步數 %d 搜尋 %d" % (L, k, best[2], best[3]), flush=True)
    for (k, L), (old, new) in repl.items():
        if k == 0:
            assert data.count('"%s"' % old) == 1
            data = data.replace('"%s"' % old, '"%s"' % new)
        else:
            assert var.count('"%s"' % old) == 1
            var = var.replace('"%s"' % old, '"%s"' % new)
    open(data_p, "w", encoding="utf-8", newline="").write(data)
    open(var_p, "w", encoding="utf-8", newline="").write(var)
    print("已改寫 %d 個盤面" % len(repl))


if __name__ == "__main__":
    main()
