"""新規則解題程式：問號（沒翻開的牌）要翻開後整欄才算排好。
規則（跟遊戲 scripts/main.gd 一樣）：
  - 一次只能搬「最上面連續、已翻開、同款」的一串；搬走後新的最上面一格自動翻開。
  - 一欄裝滿同一種動物，而且每一格都翻開了，才會消除；底下還有問號的，要先把上面搬走讓問號翻開，再疊回去。
牌的編碼：2 * 種類 + 已翻開(1) / 沒翻開(0)。
搜尋順序（moves 的排序）必須跟 scripts/main.gd 的 _sim_moves 完全一樣，這樣提示才跟關卡驗證走同一條路。
"""


def parse(text):
    """'6,3;accDd|cCabb' → (cap, 暫存格數, 各欄)；每欄最上面一格一定翻開"""
    head, body = text.split(";")
    cap, nslots = [int(x) for x in head.split(",")]
    cols = []
    for part in body.split("|"):
        c = [2 * (ord(ch.lower()) - 97) + (1 if ch.isupper() else 0) for ch in part]
        if c:
            c[-1] |= 1
        cols.append(tuple(c))
    return cap, nslots, tuple(cols)


def _top_up(c):
    return c[:-1] + (c[-1] | 1,) if c else c


def _toprun(c):
    r = 1
    x = c[-1] >> 1
    while r < len(c) and (c[-1 - r] & 1) and (c[-1 - r] >> 1) == x:
        r += 1
    return r


def _full_clear(c, cap):
    if len(c) != cap:
        return False
    x = c[0]
    if not x & 1:
        return False
    return all(t == x for t in c)


def moves(cols, slots, cap, nslots):
    out = []
    n = len(cols)
    for i in range(n):                       # 欄 → 欄
        A = cols[i]
        if not A:
            continue
        x = A[-1] >> 1
        r = _toprun(A)
        seen_empty = False
        for j in range(n):
            if j == i:
                continue
            B = cols[j]
            if len(B) >= cap:
                continue
            if B:
                if B[-1] >> 1 != x:
                    continue
                pri = 0
            else:
                if r == len(A) or seen_empty:
                    continue
                seen_empty, pri = True, 3
            m = min(r, cap - len(B))
            nc = list(cols)
            nc[i] = _top_up(A[:-m])
            nb = B + (2 * x + 1,) * m
            nc[j] = () if _full_clear(nb, cap) else nb
            out.append((pri, tuple(nc), slots))
    for s in sorted(set(slots)):             # 暫存格 → 欄（暫存格裡的牌都是翻開的，存種類）
        seen_empty = False
        for j in range(n):
            B = cols[j]
            if len(B) >= cap:
                continue
            if B:
                if B[-1] >> 1 != s:
                    continue
                pri = 1
            else:
                if seen_empty:
                    continue
                seen_empty, pri = True, 4
            nc = list(cols)
            nb = B + (2 * s + 1,)
            nc[j] = () if _full_clear(nb, cap) else nb
            ns = list(slots)
            ns.remove(s)
            out.append((pri, tuple(nc), tuple(sorted(ns))))
    if len(slots) < nslots:                  # 欄 → 暫存格
        for i in range(n):
            A = cols[i]
            if not A:
                continue
            nc = list(cols)
            nc[i] = _top_up(A[:-1])
            good = len(A) > 1 and any(cols[j] and (cols[j][-1] >> 1) == (A[-2] >> 1) for j in range(n) if j != i)
            out.append((5 if good else 6, tuple(nc), tuple(sorted(slots + (A[-1] >> 1,)))))
    out.sort(key=lambda m: m[0])
    return out


def solve(cols, cap, nslots, limit=60000):
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
