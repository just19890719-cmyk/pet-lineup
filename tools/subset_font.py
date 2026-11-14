import sys, glob, os
sys.path.insert(0, sys.argv[1])
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset
src, proj, dst = sys.argv[2], sys.argv[3], sys.argv[4]
chars = set(chr(c) for c in range(0x20, 0x7F))
chars |= set("，。！？、：；（）「」《》…—·％＋－×÷～　０１２３４５６７８９")
for f in glob.glob(os.path.join(proj, "scripts", "*.gd")) + [os.path.join(proj, "project.godot")]:
    chars |= set(open(f, encoding="utf-8").read())
chars = {c for c in chars if c >= " "}
f = TTFont(src)
f = instancer.instantiateVariableFont(f, {"wght": 600})
opt = subset.Options(); opt.layout_features = ["*"]; opt.name_IDs = ["*"]; opt.notdef_outline = True
s = subset.Subsetter(opt); s.populate(text="".join(sorted(chars))); s.subset(f)
f.save(dst)
print("chars", len(chars), "size", os.path.getsize(dst))
