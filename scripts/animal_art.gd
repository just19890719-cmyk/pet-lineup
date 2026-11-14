extends RefCounted
## 動物圖庫：優先讀 AI 生成圖片（assets/），沒有圖時用臨時佔位圖。
## 用法：const Art := preload("res://scripts/animal_art.gd")

const KEYS := ["cat", "dog", "panda", "rabbit", "bear", "pig", "frog", "chick", "fox", "koala", "lion", "cow"]
const NAMES := ["貓咪", "狗狗", "熊貓", "兔兔", "熊熊", "小豬", "青蛙", "小雞", "狐狸", "無尾熊", "獅子", "乳牛"]
const FACE_HEX := ["f6b26b", "c8a27a", "ffffff", "fbe3ec", "a8744f", "ffb6c8", "8fd16a", "ffe066", "ff9a4d", "b9c2cc", "ffd27a", "ffffff"]

static var textures: Dictionary = {}
static var hidden_tex: Texture2D = null
static var tile_tex: Texture2D = null
static var bg_tex: Texture2D = null
static var star_tex: Texture2D = null
static var ui: Dictionary = {}   # 介面圖：logo hero btn_orange btn_green btn_grey hand slot slot_lock ribbon panel
static var _loaded: bool = false


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	# 1) 整張 4x3 動物圖（依 KEYS 順序，左到右、上到下）
	var sheet: Image = _load_image("res://assets/animals/animals_sheet.png")
	if sheet != null:
		_downscale(sheet, 1024)
		_key(sheet)
		var cw: int = sheet.get_width() / 4
		var ch: int = sheet.get_height() / 3
		for i in KEYS.size():
			var cell: Image = sheet.get_region(Rect2i((i % 4) * cw, (i / 4) * ch, cw, ch))
			var used: Rect2i = cell.get_used_rect()
			if used.size.x > 4 and used.size.y > 4:
				textures[KEYS[i]] = _to_tex(cell.get_region(used))
	# 2) 單張動物圖（有的話覆蓋整張圖的那一格）
	for k in KEYS:
		var img: Image = _load_image("res://assets/animals/%s.png" % k)
		if img != null:
			_downscale(img, 384)
			_key(img)
			var used2: Rect2i = img.get_used_rect()
			if used2.size.x > 4 and used2.size.y > 4:
				img = img.get_region(used2)
			textures[k] = _to_tex(img)
	# 3) UI 與特效
	hidden_tex = _load_keyed("res://assets/ui/tile_hidden.png", 256)
	tile_tex = _load_keyed("res://assets/ui/tile_front.png", 256)
	star_tex = _load_keyed("res://assets/fx/sparkle.png", 128)
	var bg: Image = _load_image("res://assets/ui/background.png")
	if bg != null:
		_downscale(bg, 1080)
		bg_tex = _to_tex(bg)
	# 4) 介面圖（已是透明底，缺圖時主程式會退回程式繪製）
	for n in ["logo", "hero", "btn_orange", "btn_green", "btn_grey", "hand", "slot", "slot_lock", "ribbon", "panel"]:
		var t: Texture2D = _load_keyed("res://assets/ui/%s.png" % n, 900)
		if t != null:
			ui[n] = t


static func _load_keyed(path: String, maxw: int) -> Texture2D:
	var img: Image = _load_image(path)
	if img == null:
		return null
	_downscale(img, maxw)
	_key(img)
	var used: Rect2i = img.get_used_rect()
	if used.size.x > 4 and used.size.y > 4:
		img = img.get_region(used)
	return _to_tex(img)


static func _load_image(path: String) -> Image:
	var img: Image = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			img = res.get_image()
	if img == null and FileAccess.file_exists(path):
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _downscale(img: Image, maxw: int) -> void:
	var w: int = img.get_width()
	if w > maxw:
		var h: int = int(round(float(img.get_height()) * maxw / w))
		img.resize(maxw, maxi(1, h), Image.INTERPOLATE_BILINEAR)


## 去背：讀左上角顏色，是純綠或洋紅才去背（青蛙是綠色，動物整張圖請用洋紅底）
static func _key(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var data: PackedByteArray = img.get_data()
	if data.size() < 4 or data[3] < 128:
		return
	var kr: float = data[0] / 255.0
	var kg: float = data[1] / 255.0
	var kb: float = data[2] / 255.0
	var green: bool = kg > 0.6 and kr < 0.45 and kb < 0.45
	var mag: bool = kr > 0.6 and kb > 0.6 and kg < 0.45
	if not (green or mag):
		return
	var i: int = 0
	var n: int = data.size()
	while i < n:
		var dr: float = data[i] / 255.0 - kr
		var dg: float = data[i + 1] / 255.0 - kg
		var db: float = data[i + 2] / 255.0 - kb
		var d: float = sqrt(dr * dr + dg * dg + db * db)
		if d < 0.28:
			data[i + 3] = 0
		elif d < 0.45:
			data[i + 3] = int(data[i + 3] * (d - 0.28) / 0.17)
		i += 4
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)


static func _to_tex(img: Image) -> Texture2D:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func display_name(key: String) -> String:
	var i: int = KEYS.find(key)
	return NAMES[i] if i >= 0 else key


## 在 ci 的 _draw() 裡呼叫：把動物畫在 center，限制在 size x size 範圍內
static func draw_animal(ci: CanvasItem, key: String, center: Vector2, size: float, modulate: Color = Color.WHITE) -> void:
	var tex: Texture2D = textures.get(key, null)
	if tex != null:
		var ts: Vector2 = tex.get_size()
		var s: float = minf(size / ts.x, size / ts.y)
		var ds: Vector2 = ts * s
		ci.draw_texture_rect(tex, Rect2(center - ds * 0.5, ds), false, modulate)
		return
	_draw_placeholder(ci, key, center, size)


# ---------- 臨時佔位圖（AI 圖片放進 assets 後就不會用到） ----------

static func _ell(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, ol: Color, width: float = 2.0) -> void:
	var pts := PackedVector2Array()
	for k in 28:
		var a: float = TAU * k / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)
	if width > 0.0:
		var line := pts.duplicate()
		line.append(pts[0])
		ci.draw_polyline(line, ol, width, true)


static func _tri(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, col: Color, ol: Color, width: float = 2.0) -> void:
	var pts := PackedVector2Array([a, b, c])
	ci.draw_colored_polygon(pts, col)
	if width > 0.0:
		ci.draw_polyline(PackedVector2Array([a, b, c, a]), ol, width, true)


static func _draw_placeholder(ci: CanvasItem, key: String, c: Vector2, size: float) -> void:
	var r: float = size * 0.34
	var idx: int = KEYS.find(key)
	var face: Color = Color(FACE_HEX[idx]) if idx >= 0 else Color.WHITE
	var ol := Color("5a3b2a")
	var pink := Color("ff9fb8")
	var dark: Color = face.darkened(0.3)
	var black := Color("2b2b2b")
	var lw: float = maxf(1.5, size * 0.03)
	c.y += r * 0.12
	var has_snout := false
	var mouth_y: float = 0.22

	# --- 頭後面的部件 ---
	match key:
		"cat":
			for s in [-1.0, 1.0]:
				_tri(ci, c + Vector2(s * 0.9 * r, -0.35 * r), c + Vector2(s * 0.8 * r, -1.25 * r), c + Vector2(s * 0.2 * r, -0.85 * r), face, ol, lw)
				_tri(ci, c + Vector2(s * 0.75 * r, -0.55 * r), c + Vector2(s * 0.72 * r, -1.0 * r), c + Vector2(s * 0.4 * r, -0.8 * r), pink, ol, 0.0)
		"dog":
			for s in [-1.0, 1.0]:
				_ell(ci, c + Vector2(s * 0.95 * r, -0.1 * r), 0.32 * r, 0.62 * r, dark, ol, lw)
		"panda":
			for s in [-1.0, 1.0]:
				_ell(ci, c + Vector2(s * 0.75 * r, -0.78 * r), 0.3 * r, 0.3 * r, black, ol, lw)
		"rabbit":
			for s in [-1.0, 1.0]:
				_ell(ci, c + Vector2(s * 0.4 * r, -1.25 * r), 0.22 * r, 0.62 * r, face, ol, lw)
				_ell(ci, c + Vector2(s * 0.4 * r, -1.2 * r), 0.11 * r, 0.45 * r, pink, ol, 0.0)
		"bear":
			for s in [-1.0, 1.0]:
				_ell(ci, c + Vector2(s * 0.75 * r, -0.78 * r), 0.3 * r, 0.3 * r, face, ol, lw)
				_ell(ci, c + Vector2(s * 0.75 * r, -0.78 * r), 0.16 * r, 0.16 * r, dark, ol, 0.0)
		"pig":
			for s in [-1.0, 1.0]:
				_tri(ci, c + Vector2(s * 0.85 * r, -0.45 * r), c + Vector2(s * 0.85 * r, -1.05 * r), c + Vector2(s * 0.35 * r, -0.85 * r), dark, ol, lw)
		"frog":
			for s in [-1.0, 1.0]:
				_ell(ci, c + Vector2(s * 0.48 * r, -0.8 * r), 0.34 * r, 0.32 * r, face, ol, lw)
		"chick":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.1 * r, -0.95 * r), c + Vector2(0.0, -1.3 * r), c + Vector2(0.12 * r, -0.95 * r)]), ol, lw, true)
		"fox":
			for s in [-1.0, 1.0]:
				_tri(ci, c + Vector2(s * 0.95 * r, -0.3 * r), c + Vector2(s * 0.85 * r, -1.3 * r), c + Vector2(s * 0.2 * r, -0.85 * r), face, ol, lw)
				_tri(ci, c + Vector2(s * 0.9 * r, -1.0 * r), c + Vector2(s * 0.85 * r, -1.3 * r), c + Vector2(s * 0.68 * r, -1.12 * r), Color("5a3b2a"), ol, 0.0)
		"koala":
			for s in [-1.0, 1.0]:
				_ell(ci, c + Vector2(s * 0.95 * r, -0.5 * r), 0.45 * r, 0.45 * r, face, ol, lw)
				_ell(ci, c + Vector2(s * 0.95 * r, -0.5 * r), 0.25 * r, 0.25 * r, Color("f4e9ef"), ol, 0.0)
		"lion":
			for k in 12:
				var a: float = TAU * k / 12.0
				_ell(ci, c + Vector2(cos(a), sin(a)) * r * 1.05, 0.38 * r, 0.38 * r, Color("e8963a"), ol, lw)
		"cow":
			for s in [-1.0, 1.0]:
				_tri(ci, c + Vector2(s * 0.45 * r, -0.85 * r), c + Vector2(s * 0.7 * r, -1.3 * r), c + Vector2(s * 0.7 * r, -0.75 * r), Color("fff3c4"), ol, lw)
				_ell(ci, c + Vector2(s * 1.0 * r, -0.4 * r), 0.32 * r, 0.18 * r, face, ol, lw)

	# --- 頭 ---
	_ell(ci, c, r * 1.05, r, face, ol, lw)

	# --- 頭前面的部件 ---
	match key:
		"panda":
			for s in [-1.0, 1.0]:
				_ell(ci, c + Vector2(s * 0.38 * r, -0.02 * r), 0.22 * r, 0.27 * r, black, ol, 0.0)
		"dog", "bear":
			_ell(ci, c + Vector2(0, 0.38 * r), 0.42 * r, 0.3 * r, face.lightened(0.45), ol, lw * 0.7)
			_ell(ci, c + Vector2(0, 0.26 * r), 0.12 * r, 0.09 * r, black, ol, 0.0)
			mouth_y = 0.4
		"pig":
			_ell(ci, c + Vector2(0, 0.3 * r), 0.36 * r, 0.25 * r, Color("ff9fb5"), ol, lw * 0.7)
			for s in [-1.0, 1.0]:
				_ell(ci, c + Vector2(s * 0.12 * r, 0.3 * r), 0.06 * r, 0.09 * r, Color("a8506a"), ol, 0.0)
			has_snout = true
		"chick":
			_tri(ci, c + Vector2(-0.16 * r, 0.18 * r), c + Vector2(0.16 * r, 0.18 * r), c + Vector2(0, 0.42 * r), Color("ff9a3c"), ol, lw * 0.7)
			has_snout = true
		"fox":
			for s in [-1.0, 1.0]:
				_ell(ci, c + Vector2(s * 0.42 * r, 0.42 * r), 0.42 * r, 0.3 * r, Color.WHITE, ol, 0.0)
		"koala":
			_ell(ci, c + Vector2(0, 0.18 * r), 0.2 * r, 0.28 * r, Color("4a4a55"), ol, 0.0)
			has_snout = true
		"cow":
			_ell(ci, c + Vector2(-0.55 * r, -0.45 * r), 0.25 * r, 0.2 * r, Color("3a3a3a"), ol, 0.0)
			_ell(ci, c + Vector2(0, 0.48 * r), 0.55 * r, 0.3 * r, Color("ffc0cf"), ol, lw * 0.7)
			for s in [-1.0, 1.0]:
				_ell(ci, c + Vector2(s * 0.2 * r, 0.48 * r), 0.06 * r, 0.08 * r, Color("a8506a"), ol, 0.0)
			has_snout = true
		"lion":
			_ell(ci, c + Vector2(0, 0.38 * r), 0.36 * r, 0.24 * r, Color("fff0c8"), ol, 0.0)
			mouth_y = 0.36

	# --- 眼睛（每隻都有） ---
	for s in [-1.0, 1.0]:
		var e: Vector2 = c + Vector2(s * 0.38 * r, -0.05 * r)
		if key == "panda":
			ci.draw_circle(e, 0.13 * r, Color.WHITE)
		ci.draw_circle(e, 0.12 * r if key != "panda" else 0.09 * r, Color("2b1d14"))
		ci.draw_circle(e + Vector2(-0.04 * r, -0.04 * r), 0.045 * r, Color.WHITE)
	# --- 腮紅 ---
	for s in [-1.0, 1.0]:
		ci.draw_circle(c + Vector2(s * 0.62 * r, 0.3 * r), 0.11 * r, Color(1.0, 0.55, 0.65, 0.55))
	# --- 鼻子與嘴巴 ---
	if not has_snout:
		if key in ["cat", "rabbit", "fox", "lion", "frog", "panda"]:
			_tri(ci, c + Vector2(-0.07 * r, 0.12 * r), c + Vector2(0.07 * r, 0.12 * r), c + Vector2(0, 0.19 * r), Color("5a3b2a"), ol, 0.0)
		var y: float = mouth_y * r
		var m := PackedVector2Array([
			c + Vector2(-0.15 * r, y - 0.02 * r), c + Vector2(-0.075 * r, y + 0.07 * r), c + Vector2(0, y),
			c + Vector2(0.075 * r, y + 0.07 * r), c + Vector2(0.15 * r, y - 0.02 * r)])
		ci.draw_polyline(m, ol, lw * 0.8, true)
