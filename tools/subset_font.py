"""把思源黑體精簡成只含遊戲用到的字（繁中、簡中、日文、韓文各一套）。
改了遊戲文字或翻譯表（scripts/i18n.gd）之後都要重跑，不然新字會缺字。

用法：python tools/subset_font.py <fonttools 安裝位置> <完整字型資料夾> <專案資料夾>
完整字型資料夾裡要有 Google Fonts 的可變字型：NotoSansTC.ttf、NotoSansSC.ttf、NotoSansJP.ttf、NotoSansKR.ttf
"""
import sys, glob, os
sys.path.insert(0, sys.argv[1])
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset

src_dir, proj = sys.argv[2], sys.argv[3]
chars = set(chr(c) for c in range(0x20, 0x7F))
chars |= set("，。！？、：；（）「」《》…—·％＋－×÷～　０１２３４５６７８９")
for f in glob.glob(os.path.join(proj, "scripts", "*.gd")) + [os.path.join(proj, "project.godot")]:
    chars |= set(open(f, encoding="utf-8").read())
chars = {c for c in chars if c >= " "}
text = "".join(sorted(chars))
for code in ("TC", "SC", "JP", "KR"):
    src = os.path.join(src_dir, "NotoSans%s.ttf" % code)
    dst = os.path.join(proj, "assets", "fonts", "NotoSans%s-SemiBold-subset.ttf" % code)
    f = TTFont(src)
    f = instancer.instantiateVariableFont(f, {"wght": 600})
    opt = subset.Options()
    opt.layout_features = ["*"]
    opt.name_IDs = ["*"]
    opt.notdef_outline = True
    s = subset.Subsetter(opt)
    s.populate(text=text)
    s.subset(f)
    f.save(dst)
    have = sum(1 for c in chars if ord(c) in f.getBestCmap())
    print("%s 要 %d 字、有 %d 字、%d KB" % (code, len(chars), have, os.path.getsize(dst) // 1024))
