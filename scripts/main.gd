extends Control
## 萌寵排排站：主遊戲（盤面、輸入、動畫、UI、開發工具）

const Art := preload("res://scripts/animal_art.gd")

const SAVE_PATH := "user://save.cfg"
const BOARD := Rect2(8, 118, 464, 520)
const SLOT_COUNT := 4
const SLOT_SIZE := 64.0
const SLOT_GAP := 14.0
const SLOT_Y := 690.0
const LIFT := 14.0
const POP_TIME := 0.3
const LAND_TIME := 0.2
# 新手教學步驟：col = 要點的欄；info = 純說明（點任意處繼續）
const TUT := [
	{"col": 0, "text": "點一下這一欄\n拿起最上面的狗狗"},
	{"col": 1, "text": "再點這一欄\n把狗狗放到同伴上面"},
	{"info": "slots", "text": "同一種動物排滿一欄就會消除！\n卡住時可以把動物先放到暫存格"},
	{"col": 2, "text": "換小豬，先拿起來"},
	{"col": 3, "text": "放到小豬同伴上面"},
	{"col": 0, "text": "問號翻開了，是貓咪！\n把兩隻貓咪一起拿起來"},
	{"col": 2, "text": "放過去，全部排好就過關"},
]
# [動物種類數, 欄數, 每欄容量]
const LEVELS := [[4, 5, 6], [5, 6, 7], [5, 7, 8], [6, 7, 9], [6, 8, 10], [7, 8, 11], [6, 8, 12]]

var level: int = 1
var cols: Array = []          # Array[Array[Dictionary]]，索引 0 = 最底
var cap: int = 6
var slots: Array = []         # null 或 Dictionary
var slot_unlocked: Array = []
var sel_col: int = -1
var sel_slot: int = -1
var history: Array = []
var fx: Array = []
var game_over: bool = false
var col_w: float = 90.0
var tile_w: float = 60.0
var tile_h: float = 55.0
var next_id: int = 0
var seen: Dictionary = {}
var font: Font

var level_label: Label
var hint_label: Label
var undo_btn: Button
var restart_btn: Button
var dev_btn: Button
var dev_panel: PanelContainer
var overlay: Control

var sb_tile: StyleBoxFlat
var sb_hidden: StyleBoxFlat
var sb_tube: StyleBoxFlat
var sb_slot: StyleBoxFlat
var sb_slot_locked: StyleBoxFlat
var board_bottom := 638.0
var sb_sel: StyleBoxFlat
var sb_hole: StyleBoxFlat
var sb_bubble: StyleBoxFlat
var clock := 0.0
var tut_active := false
var tut_step := 0
var tut_done := false
var title_layer: Control
var skip_btn: Button
var settings_btn: Button
var sfx: Dictionary = {}        # 音效名稱 → AudioStream
var sfx_players: Array = []
var sfx_idx := 0
var music_player: AudioStreamPlayer
var sfx_on := true
var music_on := true
var combo := 0                  # 連續幾步都有消除（音調逐次升高）
var last_tick := -1.0


# ───────────────────────── 初始化 ─────────────────────────
func _ready() -> void:
	Art.load_all()
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC", "Noto Sans TC", "PingFang TC", "Heiti TC"])
	font = sf
	# 內建字型（網頁版沒有系統字型）；缺字時退回系統字型
	var ff := _load_font("res://assets/fonts/NotoSansTC-SemiBold-subset.ttf")
	if ff != null:
		ff.fallbacks = [sf]
		font = ff
	_build_theme()
	_build_styles()
	_build_ui()
	sfx_on = not _load_flag("sfx_off")
	music_on = not _load_flag("music_off")
	_init_audio()
	level = _load_level()
	tut_done = _load_flag("tutorial_done")
	start_level(level)
	# 測試用啟動參數（接在 -- 後面）：--skip-title 跳過開始畫面、--tutorial 直接進教學、--win 直接過關
	var args := OS.get_cmdline_user_args()
	if args.has("--tutorial"):
		_start_tutorial()
	elif not args.has("--skip-title"):
		_show_title()
	if args.has("--tut-step"):
		tut_step = 2
	if args.has("--dev"):
		_toggle_dev()
	if args.has("--settings"):
		_show_settings()
	if args.has("--audio-check"):
		var ms = music_player.stream
		print("audio-check sfx=%d music=%s loop_end=%s playing=%s" % [sfx.size(), ms != null, ms.loop_end if ms is AudioStreamWAV else -1, music_player.playing])
	if args.has("--tut-auto"):
		# 自動照著教學點，用來驗證七個步驟走得完
		var tm := Timer.new()
		tm.wait_time = 0.7
		tm.autostart = true
		tm.timeout.connect(func() -> void:
			if tut_active and not game_over and tut_step < TUT.size():
				var st: Dictionary = TUT[tut_step]
				_tut_tap(Vector2(240, 400) if st.has("info") else _tube_rect(st["col"]).get_center()))
		add_child(tm)
	if args.has("--win"):
		_dev_win()


func _load_font(path: String) -> FontFile:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is FontFile:
			return res
	if FileAccess.file_exists(path):
		var f := FontFile.new()
		if f.load_dynamic_font(path) == OK:
			return f
	return null


func _sb(bg: Color, border: Color, bw: int, radius: int, bottom: int = -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	if bottom >= 0:
		s.border_width_bottom = bottom
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


func _build_theme() -> void:
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 20
	var normal := _sb(Color("ff9f43"), Color("d9771f"), 0, 16, 5)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("ffb062")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("f08a2c")
	pressed.border_width_bottom = 2
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("a3968b")
	disabled.border_color = Color("7d7167")
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_font_size("font_size", "Button", 22)
	th.set_color("font_color", "Button", Color.WHITE)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color.WHITE)
	th.set_color("font_outline_color", "Button", Color("b8601a"))
	th.set_constant("outline_size", "Button", 4)
	th.set_font_size("font_size", "Label", 20)
	th.set_color("font_color", "Label", Color("5a3d2b"))
	var panel := _sb(Color("fffaf0"), Color("f0c080"), 4, 22)
	panel.content_margin_left = 24
	panel.content_margin_right = 24
	panel.content_margin_top = 20
	panel.content_margin_bottom = 20
	th.set_stylebox("panel", "PanelContainer", panel)
	# 有 AI 介面圖就換成圖片樣式
	if Art.ui.has("btn_orange"):
		th.set_stylebox("normal", "Button", _sbt("btn_orange", Color.WHITE))
		th.set_stylebox("hover", "Button", _sbt("btn_orange", Color.WHITE))
		th.set_stylebox("pressed", "Button", _sbt("btn_orange", Color(0.86, 0.86, 0.86)))
	if Art.ui.has("btn_grey"):
		th.set_stylebox("disabled", "Button", _sbt("btn_grey", Color.WHITE))
	if Art.ui.has("panel"):
		var pt := StyleBoxTexture.new()
		pt.texture = Art.ui["panel"]
		pt.texture_margin_left = 60
		pt.texture_margin_right = 60
		pt.texture_margin_top = 44
		pt.texture_margin_bottom = 30
		pt.content_margin_left = 30
		pt.content_margin_right = 30
		pt.content_margin_top = 40
		pt.content_margin_bottom = 30
		th.set_stylebox("panel", "PanelContainer", pt)
	theme = th


## 圖片按鈕樣式（左右兩端不變形，中間拉伸）
func _sbt(tex_name: String, mod: Color) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = Art.ui[tex_name]
	s.texture_margin_left = 36
	s.texture_margin_right = 36
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 4
	s.content_margin_bottom = 10
	s.modulate_color = mod
	return s


## 按鈕按下縮小、放開彈回
func _juice(b: Button) -> void:
	b.button_down.connect(func() -> void:
		_play("button")
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2(0.93, 0.93), 0.06))
	b.button_up.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


func _build_styles() -> void:
	sb_tile = _sb(Color("fffaf0"), Color("e8c9a0"), 2, 9, 4)
	sb_hidden = _sb(Color("8e7cc3"), Color("6a5aa0"), 2, 9, 4)
	sb_tube = _sb(Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.9), 3, 16)
	sb_tube.shadow_color = Color(0.45, 0.3, 0.4, 0.16)
	sb_tube.shadow_size = 8
	sb_tube.shadow_offset = Vector2(0, 4)
	sb_hole = _sb(Color(0, 0, 0, 0), Color("ffd34d"), 4, 18)
	sb_hole.draw_center = false
	sb_bubble = _sb(Color("fffaf0"), Color("ffb45e"), 4, 20)
	sb_bubble.shadow_color = Color(0.2, 0.1, 0.1, 0.3)
	sb_bubble.shadow_size = 8
	sb_bubble.shadow_offset = Vector2(0, 4)
	sb_slot = _sb(Color(1, 1, 1, 0.45), Color("e0b080"), 3, 12)
	sb_slot_locked = _sb(Color(0.4, 0.37, 0.47, 0.9), Color(0.27, 0.24, 0.34), 3, 12)
	sb_sel = _sb(Color(0, 0, 0, 0), Color("ffcc00"), 4, 11)
	sb_sel.draw_center = false


func _make_label(text: String, sz: int, pos: Vector2, w: float, col: Color, outline: Color, osize: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(w, sz + 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", osize)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _make_button(text: String, pos: Vector2, sz: Vector2, cb: Callable, fsize: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fsize)
	b.pressed.connect(cb)
	_juice(b)
	add_child(b)
	return b


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	level_label = _make_label("第 1 關", 30, Vector2(0, 16), 480, Color.WHITE, Color("a83a22"), 8)
	hint_label = _make_label("點欄位拿起最上面同款動物，再點要放的欄位", 16, Vector2(0, 86), 480, Color("5a3d2b"), Color(1, 1, 1, 0.9), 4)
	skip_btn = _make_button("跳過", Vector2(8, 14), Vector2(76, 44), func() -> void: _finish_tutorial(), 18)
	skip_btn.visible = false
	settings_btn = _make_button("設定", Vector2(8, 14), Vector2(76, 44), _show_settings, 18)
	undo_btn = _make_button("撤回", Vector2(60, 776), Vector2(170, 58), _on_undo)
	restart_btn = _make_button("重新開始", Vector2(250, 776), Vector2(170, 58), _on_restart)
	dev_btn = _make_button("開發", Vector2(396, 14), Vector2(76, 44), _toggle_dev, 18)
	_build_dev_panel()
	# 給玩家的正式版不顯示開發按鈕（從編輯器或執行遊戲.bat 開啟時仍然有）
	dev_btn.visible = OS.is_debug_build()


func _build_dev_panel() -> void:
	dev_panel = PanelContainer.new()
	dev_panel.position = Vector2(30, 44)
	dev_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	dev_panel.add_child(vb)
	var title := Label.new()
	title.text = "開發工具"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)
	var items := [
		["全部翻開", _dev_reveal_all],
		["直接過關", _dev_win],
		["下一關", func() -> void: start_level(level + 1)],
		["上一關", func() -> void: start_level(max(1, level - 1))],
		["解鎖第4格", func() -> void: _unlock_slot(3)],
		["製造快完成的欄", _dev_almost_complete],
		["測試卡死畫面", _show_stuck],
		["換一個隨機盤面", func() -> void: start_level(level, randi() % 1000000)],
		["重置存檔(回第1關)", _dev_reset_save],
		["回開始畫面", _show_title],
		["重看新手教學", _start_tutorial],
		["灑彩帶", _spawn_confetti],
		["關閉", func() -> void: pass],
	]
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.custom_minimum_size = Vector2(360, 42)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		var cb: Callable = it[1]
		b.pressed.connect(func() -> void:
			dev_panel.visible = false
			cb.call())
		vb.add_child(b)
	add_child(dev_panel)


func _toggle_dev() -> void:
	dev_panel.visible = not dev_panel.visible
	move_child(dev_panel, get_child_count() - 1)


# ───────────────────────── 關卡 ─────────────────────────
func start_level(l: int, sd: int = -1) -> void:
	level = max(1, l)
	tut_active = false
	combo = 0
	seen.clear()
	if sd < 0:
		sd = level * 7919 + 17
	_generate(sd)
	slots = []
	for k in SLOT_COUNT:
		slots.append(null)
	slot_unlocked = [true, true, true, false]
	sel_col = -1
	sel_slot = -1
	history.clear()
	fx.clear()
	game_over = false
	_layout()
	_reveal_tops(false)
	_drop_in()
	_close_overlay()
	_update_ui()


## 開局動畫：方塊一欄一欄從上面掉下來
func _drop_in() -> void:
	for i in cols.size():
		var c: Array = cols[i]
		for j in c.size():
			var t: Dictionary = c[j]
			t["off"] = Vector2(0, -(board_bottom + 80.0))
			t["wait"] = i * 0.045 + j * 0.03


func _level_cfg() -> Array:
	return LEVELS[min(level - 1, LEVELS.size() - 1)]


func _new_tile(t: String, r: bool) -> Dictionary:
	next_id += 1
	return {"id": next_id, "t": t, "r": r, "off": Vector2.ZERO, "pop": 0.0}


func _generate(sd: int) -> void:
	var cfg := _level_cfg()
	var types: int = cfg[0]
	var n: int = cfg[1]
	cap = cfg[2]
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var pool: Array = Art.KEYS.duplicate()
	_shuffle(pool, rng)
	var bag: Array = []
	for i in types:
		for c in cap:
			bag.append(pool[i])
	_shuffle(bag, rng)
	cols = []
	var total := bag.size()
	var idx := 0
	for i in n:
		var h: int = total / n + (1 if i < total % n else 0)
		var col: Array = []
		for j in h:
			var tile := _new_tile(bag[idx], rng.randf() < 0.12)
			if tile["r"]:
				seen[tile["id"]] = true
			col.append(tile)
			idx += 1
		cols.append(col)


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ───────────────────────── 版面 ─────────────────────────
func _layout() -> void:
	var n := cols.size()
	col_w = BOARD.size.x / n
	tile_w = min(col_w - 8.0, 62.0)
	tile_h = min(480.0 / cap, tile_w * 0.92)
	# 盤面在 BOARD 區域內垂直置中（欄位矮的關卡不再貼底）
	board_bottom = BOARD.position.y + (BOARD.size.y + tile_h * cap + 12.0) / 2.0


func _tube_rect(i: int) -> Rect2:
	var cx := BOARD.position.x + col_w * (i + 0.5)
	var w := tile_w + 8.0
	var h := tile_h * cap + 12.0
	var bottom := board_bottom
	return Rect2(cx - w / 2.0, bottom - h, w, h)


func _tile_pos(i: int, j: int) -> Vector2:
	var cx := BOARD.position.x + col_w * (i + 0.5)
	return Vector2(cx, board_bottom - 6.0 - tile_h * (j + 0.5))


func _slot_rect(k: int) -> Rect2:
	var total := SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_GAP
	var x0 := (480.0 - total) / 2.0
	return Rect2(x0 + k * (SLOT_SIZE + SLOT_GAP), SLOT_Y - SLOT_SIZE / 2.0, SLOT_SIZE, SLOT_SIZE)


func _slot_draw_pos(k: int) -> Vector2:
	var p := _slot_rect(k).get_center()
	if sel_slot == k:
		p.y -= 8.0
	return p


func _col_tile_draw_pos(i: int, j: int) -> Vector2:
	var c: Array = cols[i]
	var p := _tile_pos(i, j) + (c[j]["off"] as Vector2)
	if sel_col == i and j >= c.size() - _run_len(i):
		p.y -= LIFT + sin(clock * 6.0) * 2.5
	return p


func _run_len(i: int) -> int:
	var c: Array = cols[i]
	if c.is_empty():
		return 0
	var top: Dictionary = c.back()
	var n := 0
	for j in range(c.size() - 1, -1, -1):
		var t: Dictionary = c[j]
		if t["r"] and t["t"] == top["t"]:
			n += 1
		else:
			break
	return n


# ───────────────────────── 規則 ─────────────────────────
func _source_type() -> String:
	if sel_col >= 0 and not cols[sel_col].is_empty():
		return cols[sel_col].back()["t"]
	if sel_slot >= 0 and slots[sel_slot] != null:
		return slots[sel_slot]["t"]
	return ""


func _source_count() -> int:
	if sel_col >= 0:
		return _run_len(sel_col)
	if sel_slot >= 0 and slots[sel_slot] != null:
		return 1
	return 0


func _can_move_to_col(i: int) -> bool:
	if sel_col == i:
		return false
	if _source_count() <= 0:
		return false
	var c: Array = cols[i]
	if c.size() >= cap:
		return false
	if c.is_empty():
		return true
	var top: Dictionary = c.back()
	return top["r"] and top["t"] == _source_type()


func _do_move_to_col(i: int) -> void:
	_push_history()
	var movers: Array = []   # [tile, old_pos]
	if sel_col >= 0:
		var src: Array = cols[sel_col]
		var n: int = min(_run_len(sel_col), cap - cols[i].size())
		var start := src.size() - n
		for j in range(start, src.size()):
			movers.append([src[j], _col_tile_draw_pos(sel_col, j)])
		src.resize(start)
	else:
		movers.append([slots[sel_slot], _slot_draw_pos(sel_slot)])
		slots[sel_slot] = null
	for m in movers:
		var tile: Dictionary = m[0]
		cols[i].append(tile)
		tile["off"] = (m[1] as Vector2) - _tile_pos(i, cols[i].size() - 1)
	_play("drop")
	if movers.size() > 1:
		get_tree().create_timer(0.07).timeout.connect(func() -> void: _play("drop", 1.15, -4.0))
	_after_move([i])


func _do_move_to_slot(k: int) -> void:
	if sel_col < 0 or cols[sel_col].is_empty():
		return
	_push_history()
	var src: Array = cols[sel_col]
	var old := _col_tile_draw_pos(sel_col, src.size() - 1)
	var tile: Dictionary = src.pop_back()
	slots[k] = tile
	tile["off"] = old - _slot_rect(k).get_center()
	_play("slot")
	_after_move([])


func _after_move(targets: Array) -> void:
	sel_col = -1
	sel_slot = -1
	_reveal_tops(true)
	var combo_before := combo
	for i in targets:
		_check_complete(i)
	if combo == combo_before:
		combo = 0
	_check_end()
	_update_ui()


func _reveal_tops(anim: bool) -> void:
	var flipped := false
	for c in cols:
		if c.is_empty():
			continue
		var top: Dictionary = c.back()
		if not top["r"]:
			top["r"] = true
			if anim:
				top["pop"] = POP_TIME
				if not flipped:
					flipped = true
					_play("flip")
		seen[top["id"]] = true


func _check_complete(i: int) -> void:
	var c: Array = cols[i]
	if c.size() < cap:
		return
	var t: String = c[0]["t"]
	for tile in c:
		if tile["t"] != t:
			return
	var cx := BOARD.position.x + col_w * (i + 0.5)
	for j in c.size():
		var tile: Dictionary = c[j]
		fx.append({"kind": "tile", "pos": _tile_pos(i, j), "off": tile["off"], "t": t,
			"time": 0.0, "delay": j * 0.03, "dur": 0.35})
	combo += 1
	_play("clear", 1.0 + 0.1 * min(combo - 1, 5))
	var tr := _tube_rect(i)
	fx.append({"kind": "ring", "pos": tr.get_center(), "r": tr.size.y * 0.62, "time": 0.0, "delay": 0.05, "dur": 0.55})
	for s in 20:
		var ang := randf() * TAU
		fx.append({"kind": "spark", "pos": Vector2(cx, tr.position.y + randf() * tr.size.y),
			"vel": Vector2(cos(ang), sin(ang)) * randf_range(60, 160), "size": randf_range(10, 20),
			"time": 0.0, "delay": randf() * 0.2, "dur": 0.7})
	fx.append({"kind": "text", "pos": Vector2(cx, tr.position.y - 10), "text": "完成！",
		"time": 0.0, "delay": 0.1, "dur": 1.0})
	cols[i] = []


func _all_clear() -> bool:
	for c in cols:
		if not c.is_empty():
			return false
	for s in slots:
		if s != null:
			return false
	return true


func _check_end() -> void:
	if _all_clear():
		game_over = true
		_spawn_confetti()
		get_tree().create_timer(0.4).timeout.connect(func() -> void: _play("win"))
		if tut_active:
			tut_done = true
			_save_flag("tutorial_done", true)
			get_tree().create_timer(0.9).timeout.connect(_show_tut_done)
			return
		_save_level(level + 1)
		get_tree().create_timer(0.9).timeout.connect(_show_win)
		return
	if not _has_any_move():
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if not game_over and not _has_any_move() and overlay == null:
				_show_stuck())


func _has_any_move() -> bool:
	for s in slots:
		if s == null:
			continue
		for c in cols:
			if c.is_empty() or (c.size() < cap and c.back()["r"] and c.back()["t"] == s["t"]):
				return true
	var empty_slot := false
	for k in SLOT_COUNT:
		if slot_unlocked[k] and slots[k] == null:
			empty_slot = true
	for i in cols.size():
		var c: Array = cols[i]
		if c.is_empty():
			continue
		if empty_slot:
			return true
		var tt: String = c.back()["t"]
		var rl := _run_len(i)
		for j in cols.size():
			if j == i:
				continue
			var d: Array = cols[j]
			if d.is_empty():
				if rl < c.size():
					return true
			elif d.size() < cap and d.back()["t"] == tt:
				return true
	return false


# ───────────────────────── 撤回 ─────────────────────────
func _tile_snap(t: Dictionary) -> Dictionary:
	return {"id": t["id"], "t": t["t"], "r": t["r"]}


func _push_history() -> void:
	var cs: Array = []
	for c in cols:
		var a: Array = []
		for t in c:
			a.append(_tile_snap(t))
		cs.append(a)
	var ss: Array = []
	for s in slots:
		ss.append(null if s == null else _tile_snap(s))
	history.append({"cols": cs, "slots": ss})


func _restore_tile(d: Dictionary) -> Dictionary:
	return {"id": d["id"], "t": d["t"], "r": d["r"] or seen.has(d["id"]), "off": Vector2.ZERO, "pop": 0.0}


func _on_undo() -> void:
	if history.is_empty():
		return
	_play("undo")
	var snap: Dictionary = history.pop_back()
	cols = []
	for a in snap["cols"]:
		var c: Array = []
		for d in a:
			c.append(_restore_tile(d))
		cols.append(c)
	slots = []
	for d in snap["slots"]:
		slots.append(null if d == null else _restore_tile(d))
	sel_col = -1
	sel_slot = -1
	fx.clear()
	game_over = false
	_close_overlay()
	_update_ui()


func _on_restart() -> void:
	start_level(level)


# ───────────────────────── 輸入 ─────────────────────────
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if dev_panel.visible:
		dev_panel.visible = false
		return
	if game_over or overlay != null:
		return
	var p := mb.position
	if tut_active:
		_tut_tap(p)
		return
	var h0 := history.size()
	var had := sel_col >= 0 or sel_slot >= 0
	for k in SLOT_COUNT:
		if _slot_rect(k).grow(4).has_point(p):
			_tap_slot(k)
			_tap_sound(h0, had)
			return
	for i in cols.size():
		var tr := _tube_rect(i)
		var hit := Rect2(BOARD.position.x + col_w * i, tr.position.y - 40, col_w, tr.size.y + 40)
		if hit.has_point(p):
			_tap_col(i)
			_tap_sound(h0, had)
			return
	sel_col = -1
	sel_slot = -1


## 點擊後的音效：剛拿起來 → 拿起聲；本來有拿、沒搬成功卻換了選取 → 不行的提示聲
func _tap_sound(h0: int, had: bool) -> void:
	if history.size() > h0:
		return   # 有搬動，搬動的地方自己會出聲
	var has := sel_col >= 0 or sel_slot >= 0
	if has and not had:
		_play("pick")
	elif has and had:
		_play("deny")


func _tap_col(i: int) -> void:
	var c: Array = cols[i]
	if sel_slot >= 0:
		if _can_move_to_col(i):
			_do_move_to_col(i)
		else:
			sel_slot = -1
			sel_col = i if not c.is_empty() else -1
		return
	if sel_col < 0:
		if not c.is_empty():
			sel_col = i
		return
	if sel_col == i:
		sel_col = -1
		return
	if _can_move_to_col(i):
		_do_move_to_col(i)
	elif not c.is_empty():
		sel_col = i
	else:
		sel_col = -1


func _tap_slot(k: int) -> void:
	if not slot_unlocked[k]:
		_unlock_slot(k)
		return
	if slots[k] != null:
		if sel_slot == k:
			sel_slot = -1
		else:
			sel_col = -1
			sel_slot = k
		return
	if sel_col >= 0:
		_do_move_to_slot(k)
	else:
		sel_slot = -1


func _unlock_slot(k: int) -> void:
	if slot_unlocked[k]:
		return
	slot_unlocked[k] = true
	_play("unlock")
	var c := _slot_rect(k).get_center()
	for s in 8:
		var ang := TAU * s / 8.0
		fx.append({"kind": "spark", "pos": c, "vel": Vector2(cos(ang), sin(ang)) * 110.0, "size": 14.0,
			"time": 0.0, "delay": 0.0, "dur": 0.5})
	if overlay != null:
		_close_overlay()


# ───────────────────────── 動畫 ─────────────────────────
func _process(delta: float) -> void:
	clock += delta
	var k := 1.0 - exp(-16.0 * delta)
	for c in cols:
		for t in c:
			_anim_tile(t, k, delta)
	for s in slots:
		if s != null:
			_anim_tile(s, k, delta)
	for i in range(fx.size() - 1, -1, -1):
		var f: Dictionary = fx[i]
		f["time"] = f["time"] + delta
		if f["time"] > f["delay"] + f["dur"]:
			fx.remove_at(i)
	queue_redraw()


func _anim_tile(t: Dictionary, k: float, delta: float) -> void:
	var wait: float = t.get("wait", 0.0)
	if wait > 0.0:
		t["wait"] = wait - delta
		if wait - delta <= 0.0 and clock - last_tick > 0.06:
			last_tick = clock
			_play("tick", randf_range(0.9, 1.2), -10.0)
		return
	var land: float = t.get("land", 0.0)
	if land > 0.0:
		t["land"] = max(0.0, land - delta)
	var off: Vector2 = t["off"]
	if off != Vector2.ZERO:
		off = off.lerp(Vector2.ZERO, k)
		if off.length() < 0.5:
			off = Vector2.ZERO
			t["land"] = LAND_TIME   # 落地時壓扁彈一下
		t["off"] = off
	if t["pop"] > 0.0:
		t["pop"] = max(0.0, t["pop"] - delta)


func _is_moving(t: Dictionary) -> bool:
	return (t["off"] as Vector2) != Vector2.ZERO


func _pop_scale(t: Dictionary) -> float:
	if t["pop"] <= 0.0:
		return 1.0
	return 1.0 + 0.16 * sin((1.0 - t["pop"] / POP_TIME) * PI)


# ───────────────────────── 繪圖 ─────────────────────────
func _draw() -> void:
	_draw_bg()
	if Art.ui.has("ribbon"):
		draw_texture_rect(Art.ui["ribbon"], Rect2(105, 4, 270, 84), false)
	for i in cols.size():
		draw_style_box(sb_tube, _tube_rect(i))
	var movers: Array = []
	var tsize := Vector2(tile_w, tile_h - 3.0)
	for i in cols.size():
		var c: Array = cols[i]
		var rl := _run_len(i) if sel_col == i else 0
		for j in c.size():
			var t: Dictionary = c[j]
			var p := _col_tile_draw_pos(i, j)
			if _is_moving(t):
				movers.append([t, p, tsize])
				continue
			_draw_tile(t, p, tsize, _pop_scale(t), sel_col == i and j >= c.size() - rl)
	for k in SLOT_COUNT:
		var r := _slot_rect(k)
		if not slot_unlocked[k]:
			if Art.ui.has("slot_lock"):
				var bob := 1.0 + 0.04 * sin(clock * 3.0)
				draw_set_transform(r.get_center(), 0.0, Vector2(bob, bob))
				draw_texture_rect(Art.ui["slot_lock"], Rect2(-r.size / 2.0 - Vector2(3, 3), r.size + Vector2(6, 6)), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				draw_style_box(sb_slot_locked, r)
				_draw_text_center("解鎖", r.get_center() + Vector2(0, 7), 18, Color.WHITE, Color(0.16, 0.13, 0.22))
			continue
		if Art.ui.has("slot"):
			draw_texture_rect(Art.ui["slot"], r.grow(3), false)
		else:
			draw_style_box(sb_slot, r)
		var s = slots[k]
		if s != null:
			var sp := _slot_draw_pos(k) + (s["off"] as Vector2)
			if _is_moving(s):
				movers.append([s, sp, Vector2(56, 52)])
			else:
				_draw_tile(s, sp, Vector2(56, 52), 1.0, sel_slot == k)
	if sel_col >= 0 or sel_slot >= 0:
		for i in cols.size():
			if i == sel_col:
				continue
			var tr := _tube_rect(i)
			_draw_mark(Vector2(tr.get_center().x, tr.position.y - 20), _can_move_to_col(i))
	for m in movers:
		_draw_tile(m[0], m[1], m[2], 1.0, false)
	_draw_fx()
	_draw_tutorial()


func _draw_bg() -> void:
	var sz := size
	if Art.bg_tex != null:
		var ts := Art.bg_tex.get_size()
		var sc: float = max(sz.x / ts.x, sz.y / ts.y)
		var ds := ts * sc
		draw_texture_rect(Art.bg_tex, Rect2((sz - ds) / 2.0, ds), false)
		return
	var top := Color("bfe8ff")
	var bot := Color("ffe3f0")
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)]),
		PackedColorArray([top, top, bot, bot]))


func _draw_tile(t: Dictionary, center: Vector2, tsize: Vector2, sc: float, selected: bool) -> void:
	var sv := Vector2(sc, sc)
	var land: float = t.get("land", 0.0)
	if land > 0.0:
		var q := sin((1.0 - land / LAND_TIME) * PI)
		sv *= Vector2(1.0 + 0.14 * q, 1.0 - 0.12 * q)
	var face_up: bool = t["r"]
	var pop: float = t.get("pop", 0.0)
	if pop > 0.0:
		# 翻牌：前半段還是問號面，轉到側面後換成動物面
		var prog := 1.0 - pop / POP_TIME
		sv.x *= max(0.06, abs(cos(prog * PI)))
		face_up = prog >= 0.5
	draw_set_transform(center, 0.0, sv)
	var r := Rect2(-tsize / 2.0, tsize)
	if face_up:
		if Art.tile_tex != null:
			draw_texture_rect(Art.tile_tex, r, false)
		else:
			draw_style_box(sb_tile, r)
		Art.draw_animal(self, t["t"], Vector2(0, -1), min(tsize.x, tsize.y) * 0.92)
	else:
		if Art.hidden_tex != null:
			draw_texture_rect(Art.hidden_tex, r, false)
		else:
			draw_style_box(sb_hidden, r)
			var fs := int(tsize.y * 0.55)
			_draw_text_center("?", Vector2(0, fs * 0.36), fs, Color.WHITE, Color("4a3a80"))
	if selected:
		draw_style_box(sb_sel, r.grow(2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_text_center(text: String, base: Vector2, fs: int, col: Color, outline: Color) -> void:
	var w := 400.0
	var p := Vector2(base.x - w / 2.0, base.y)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 5, outline)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)


func _draw_mark(c: Vector2, ok: bool) -> void:
	var col := Color("5cc85c") if ok else Color("ff7b7b")
	draw_circle(c, 11.0, col)
	draw_arc(c, 11.0, 0, TAU, 24, Color.WHITE, 2.0, true)
	if ok:
		draw_polyline(PackedVector2Array([c + Vector2(-5, 0), c + Vector2(-1, 4), c + Vector2(5, -4)]), Color.WHITE, 2.5, true)
	else:
		draw_line(c + Vector2(-4, -4), c + Vector2(4, 4), Color.WHITE, 2.5, true)
		draw_line(c + Vector2(4, -4), c + Vector2(-4, 4), Color.WHITE, 2.5, true)


func _draw_fx() -> void:
	for f in fx:
		var lt: float = f["time"] - f["delay"]
		if lt < 0.0:
			continue
		var p: float = clamp(lt / f["dur"], 0.0, 1.0)
		match f["kind"]:
			"tile":
				var sc: float = lerp(1.0, 1.2, p / 0.3) if p < 0.3 else lerp(1.2, 0.0, (p - 0.3) / 0.7)
				var tile := {"t": f["t"], "r": true}
				_draw_tile(tile, (f["pos"] as Vector2) + (f["off"] as Vector2), Vector2(tile_w, tile_h - 3.0), sc, false)
			"spark":
				var pos: Vector2 = f["pos"] + (f["vel"] as Vector2) * lt
				var s: float = f["size"] * (1.0 - p)
				draw_set_transform(pos, lt * 4.0, Vector2(s, s) / 20.0)
				if Art.star_tex != null:
					draw_texture_rect(Art.star_tex, Rect2(-10, -10, 20, 20), false)
				else:
					_draw_star(Vector2.ZERO, 10.0, Color("ffd34d"))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"ring":
				var rr: float = lerp(12.0, float(f["r"]), 1.0 - (1.0 - p) * (1.0 - p))
				draw_arc(f["pos"], rr, 0.0, TAU, 48, Color(1, 1, 1, 0.9 * (1.0 - p)), 2.0 + 8.0 * (1.0 - p), true)
			"confetti":
				var cv: Vector2 = f["vel"]
				var cp: Vector2 = (f["pos"] as Vector2) + cv * lt + Vector2(sin(lt * 5.0 + f["spin"]) * 16.0, 0)
				var cs: float = f["size"]
				var cc: Color = f["col"]
				cc.a = 1.0 - clamp((p - 0.8) / 0.2, 0.0, 1.0)
				draw_set_transform(cp, lt * f["spin"], Vector2(1.0, max(0.15, abs(cos(lt * f["spin"] * 1.3)))))
				draw_rect(Rect2(-cs / 2.0, -cs / 3.0, cs, cs * 0.66), cc)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"text":
				var pos2: Vector2 = f["pos"] - Vector2(0, 40.0 * p)
				var sc2: float = 1.0 + 0.3 * sin(min(p * 4.0, 1.0) * PI)
				draw_set_transform(pos2, 0.0, Vector2(sc2, sc2))
				_draw_text_center(f["text"], Vector2.ZERO, 26, Color("ff6b9d"), Color.WHITE)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var rr := r if i % 2 == 0 else r * 0.42
		var a := -PI / 2.0 + TAU * i / 8.0
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)


# ───────────────────────── UI / 對話框 ─────────────────────────
func _update_ui() -> void:
	level_label.text = "新手教學" if tut_active else "第 %d 關" % level
	hint_label.visible = level <= 2 and not tut_active
	undo_btn.visible = not tut_active
	restart_btn.visible = not tut_active
	skip_btn.visible = tut_active
	settings_btn.visible = not tut_active
	undo_btn.disabled = history.is_empty()
	# 停用時把橘色字框換成深灰，灰底上才讀得清楚
	undo_btn.add_theme_color_override("font_outline_color", Color("5e5148") if undo_btn.disabled else Color("b8601a"))


func _close_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null


func _show_dialog(title: String, msg: String, buttons: Array) -> void:
	_close_overlay()
	_play("pop")
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var tl := Label.new()
	tl.text = title
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 32)
	tl.add_theme_color_override("font_color", Color("ff7a45"))
	vb.add_child(tl)
	if msg != "":
		var ml := Label.new()
		ml.text = msg
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.custom_minimum_size = Vector2(300, 0)
		vb.add_child(ml)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(300, 56)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(b[1])
		_juice(btn)
		vb.add_child(btn)
	overlay.add_child(panel)
	add_child(overlay)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	# 對話框彈出動畫
	dim.modulate.a = 0.0
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.6, 0.6)
	panel.pivot_offset = panel.get_combined_minimum_size() / 2.0
	var tw := overlay.create_tween().set_parallel(true)
	tw.tween_property(dim, "modulate:a", 1.0, 0.2)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	move_child(dev_panel, get_child_count() - 1)


func _show_win() -> void:
	_show_dialog("過關！", "所有動物都排好了，好棒！", [["下一關", func() -> void: start_level(level + 1)]])


func _show_stuck() -> void:
	var btns: Array = []
	if not history.is_empty():
		btns.append(["撤回一步", _on_undo])
	if not slot_unlocked[3]:
		btns.append(["解鎖第4格", func() -> void: _unlock_slot(3)])
	btns.append(["重新開始", _on_restart])
	_show_dialog("卡住了", "沒有可以走的步了", btns)
	_play("stuck")


# ───────────────────────── 存檔 ─────────────────────────
func _load_level() -> int:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return 1
	return max(1, int(cf.get_value("progress", "level", 1)))


func _save_level(l: int) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("progress", "level", l)
	cf.save(SAVE_PATH)


# ───────────────────────── 開發工具 ─────────────────────────
func _dev_reveal_all() -> void:
	for c in cols:
		for t in c:
			if not t["r"]:
				t["r"] = true
				t["pop"] = POP_TIME
			seen[t["id"]] = true
	for s in slots:
		if s != null:
			s["r"] = true


func _dev_win() -> void:
	for i in cols.size():
		cols[i] = []
	for k in SLOT_COUNT:
		slots[k] = null
	_check_end()


func _dev_almost_complete() -> void:
	var all: Array = []
	for c in cols:
		all.append_array(c)
	for s in slots:
		if s != null:
			all.append(s)
	if all.is_empty():
		return
	var a: String = all[0]["t"]
	var as_: Array = []
	var others: Array = []
	for t in all:
		t["off"] = Vector2.ZERO
		t["pop"] = 0.0
		if t["t"] == a:
			as_.append(t)
		else:
			others.append(t)
	var n := cols.size()
	for i in n:
		cols[i] = []
	for k in SLOT_COUNT:
		slots[k] = null
	for j in cap - 1:
		var t: Dictionary = as_[j]
		t["r"] = true
		cols[0].append(t)
	for idx in others.size():
		cols[1 + idx % (n - 1)].append(others[idx])
	var last: Dictionary = as_[cap - 1]
	cols[1].append(last)
	sel_col = -1
	sel_slot = -1
	history.clear()
	_reveal_tops(false)
	_update_ui()


func _dev_reset_save() -> void:
	_save_level(1)
	tut_done = false
	_save_flag("tutorial_done", false)
	start_level(1)
	_show_title()


# ───────────────────────── 存檔旗標 ─────────────────────────
func _load_flag(key: String) -> bool:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return false
	return bool(cf.get_value("progress", key, false))


func _save_flag(key: String, v: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("progress", key, v)
	cf.save(SAVE_PATH)


# ───────────────────────── 音效與音樂 ─────────────────────────
func _init_audio() -> void:
	for n in ["pick", "drop", "deny", "flip", "clear", "win", "button", "undo", "slot", "unlock", "stuck", "pop", "tick", "step"]:
		var p := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(p):
			sfx[n] = load(p)
	for i in 8:
		var pl := AudioStreamPlayer.new()
		add_child(pl)
		sfx_players.append(pl)
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -12.0
	add_child(music_player)
	var bp := "res://assets/audio/bgm.wav"
	if ResourceLoader.exists(bp):
		var st = load(bp)
		if st is AudioStreamWAV:
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = int(st.get_length() * st.mix_rate)
		music_player.stream = st
		if music_on:
			music_player.play()


func _play(n: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if not sfx_on or not sfx.has(n) or sfx_players.is_empty():
		return
	var pl: AudioStreamPlayer = sfx_players[sfx_idx]
	sfx_idx = (sfx_idx + 1) % sfx_players.size()
	pl.stream = sfx[n]
	pl.pitch_scale = pitch
	pl.volume_db = vol_db
	pl.play()


func _show_settings() -> void:
	_show_dialog("設定", "", [
		["音效：%s" % ("開" if sfx_on else "關"), func() -> void: _set_sfx(not sfx_on)],
		["音樂：%s" % ("開" if music_on else "關"), func() -> void: _set_music(not music_on)],
		["關閉", _close_overlay],
	])


func _set_sfx(v: bool) -> void:
	sfx_on = v
	_save_flag("sfx_off", not v)
	_show_settings()


func _set_music(v: bool) -> void:
	music_on = v
	_save_flag("music_off", not v)
	if music_player.stream != null:
		if v:
			music_player.play()
		else:
			music_player.stop()
	_show_settings()


# ───────────────────────── 彩帶 ─────────────────────────
func _spawn_confetti() -> void:
	var cols_hex := ["ff6b9d", "ffd34d", "7ed957", "5cc8ff", "ff9f43", "b98cff"]
	for n in 80:
		fx.append({"kind": "confetti", "pos": Vector2(randf() * 480.0, -20.0 - randf() * 220.0),
			"vel": Vector2(randf_range(-40, 40), randf_range(200, 360)), "col": Color(cols_hex[n % cols_hex.size()]),
			"size": randf_range(7, 12), "spin": randf_range(-8, 8),
			"time": 0.0, "delay": randf() * 0.5, "dur": 2.8})


# ───────────────────────── 開始畫面 ─────────────────────────
func _show_title() -> void:
	if title_layer != null:
		return
	_close_overlay()
	title_layer = Control.new()
	title_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(title_layer)
	if Art.bg_tex != null:
		var bg := TextureRect.new()
		bg.texture = Art.bg_tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_layer.add_child(bg)
	else:
		var cr := ColorRect.new()
		cr.color = Color("ffe3f0")
		cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		title_layer.add_child(cr)
	# 標題
	if Art.ui.has("logo"):
		var logo := _title_pic("logo", Rect2(24, 120, 432, 130))
		var lt := logo.create_tween().set_loops()
		lt.tween_property(logo, "position:y", 132.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		lt.tween_property(logo, "position:y", 120.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		var tl := _make_label("萌寵排排站", 56, Vector2(0, 140), 480, Color("ffb020"), Color("5a3a28"), 12)
		remove_child(tl)
		title_layer.add_child(tl)
	# 動物主視覺（坐在下方草地上）
	if Art.ui.has("hero"):
		var hero := _title_pic("hero", Rect2(20, 632, 440, 156))
		hero.pivot_offset = Vector2(220, 156)
		var ht := hero.create_tween().set_loops()
		ht.tween_property(hero, "scale", Vector2(1.02, 0.97), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		ht.tween_property(hero, "scale", Vector2(1.0, 1.0), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 開始按鈕
	var sb := _make_button("開始遊戲", Vector2(105, 380), Vector2(270, 86), _on_title_start, 32)
	remove_child(sb)
	title_layer.add_child(sb)
	if Art.ui.has("btn_green"):
		sb.add_theme_stylebox_override("normal", _sbt("btn_green", Color.WHITE))
		sb.add_theme_stylebox_override("hover", _sbt("btn_green", Color.WHITE))
		sb.add_theme_stylebox_override("pressed", _sbt("btn_green", Color(0.86, 0.86, 0.86)))
		sb.add_theme_color_override("font_outline_color", Color("2c7a2c"))
		sb.add_theme_constant_override("outline_size", 8)
	var stb := _make_button("設定", Vector2(396, 14), Vector2(76, 44), _show_settings, 18)
	remove_child(stb)
	title_layer.add_child(stb)
	# 進度說明
	var info := "第一次玩會先帶你做新手教學" if not tut_done else "目前進度：第 %d 關" % level
	var il := _make_label(info, 19, Vector2(0, 484), 480, Color("5a3d2b"), Color(1, 1, 1, 0.95), 6)
	remove_child(il)
	title_layer.add_child(il)
	if tut_done:
		var tb := _make_button("玩法教學", Vector2(160, 540), Vector2(160, 52), func() -> void: _leave_title(_start_tutorial), 19)
		remove_child(tb)
		title_layer.add_child(tb)
	# 淡入
	title_layer.modulate.a = 0.0
	title_layer.create_tween().tween_property(title_layer, "modulate:a", 1.0, 0.25)


func _title_pic(tex_name: String, rect: Rect2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Art.ui[tex_name]
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.position = rect.position
	t.size = rect.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_layer.add_child(t)
	return t


func _on_title_start() -> void:
	if tut_done:
		_leave_title(func() -> void: start_level(level))
	else:
		_leave_title(_start_tutorial)


func _leave_title(then: Callable) -> void:
	if title_layer == null:
		then.call()
		return
	var layer := title_layer
	title_layer = null
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	then.call()
	var tw := layer.create_tween()
	tw.tween_property(layer, "modulate:a", 0.0, 0.3)
	tw.tween_callback(layer.queue_free)


# ───────────────────────── 新手教學 ─────────────────────────
func _tut_tile(t: String, r: bool) -> Dictionary:
	var tile := _new_tile(t, r)
	if r:
		seen[tile["id"]] = true
	return tile


func _start_tutorial() -> void:
	if title_layer != null:
		_leave_title(_start_tutorial)
		return
	tut_active = true
	tut_step = 0
	seen.clear()
	cap = 3
	cols = [
		[_tut_tile("cat", true), _tut_tile("cat", false), _tut_tile("dog", true)],
		[_tut_tile("dog", true), _tut_tile("dog", true)],
		[_tut_tile("cat", true), _tut_tile("pig", true)],
		[_tut_tile("pig", true), _tut_tile("pig", true)],
	]
	slots = []
	for k in SLOT_COUNT:
		slots.append(null)
	slot_unlocked = [true, true, true, false]
	sel_col = -1
	sel_slot = -1
	history.clear()
	fx.clear()
	game_over = false
	_layout()
	_drop_in()
	_close_overlay()
	_update_ui()


func _tut_tap(p: Vector2) -> void:
	if tut_step >= TUT.size():
		return
	var st: Dictionary = TUT[tut_step]
	if st.has("info"):
		tut_step += 1
		_play("step")
		return
	var i: int = st["col"]
	var tr := _tube_rect(i)
	var hit := Rect2(BOARD.position.x + col_w * i, tr.position.y - 40, col_w, tr.size.y + 40)
	if hit.has_point(p):
		tut_step += 1
		var h0 := history.size()
		var had := sel_col >= 0 or sel_slot >= 0
		_tap_col(i)
		_tap_sound(h0, had)


func _finish_tutorial() -> void:
	tut_done = true
	_save_flag("tutorial_done", true)
	start_level(level)


func _show_tut_done() -> void:
	_show_dialog("學會了！", "你已經會玩了\n開始排動物吧！", [["開始遊戲", func() -> void: start_level(level)]])


func _draw_tutorial() -> void:
	if not tut_active or game_over or tut_step >= TUT.size():
		return
	var st: Dictionary = TUT[tut_step]
	var is_info: bool = st.has("info")
	var hole: Rect2
	if is_info:
		hole = _slot_rect(0).merge(_slot_rect(SLOT_COUNT - 1)).grow(10)
	else:
		hole = _tube_rect(st["col"]).grow(8)
		hole.position.y -= 26
		hole.size.y += 26
	# 四塊暗幕圍出亮區
	var dimc := Color(0.12, 0.06, 0.16, 0.6)
	var hd := hole.grow(2.0)
	draw_rect(Rect2(0, 0, 480, hd.position.y), dimc)
	draw_rect(Rect2(0, hd.end.y, 480, size.y - hd.end.y), dimc)
	draw_rect(Rect2(0, hd.position.y, hd.position.x, hd.size.y), dimc)
	draw_rect(Rect2(hd.end.x, hd.position.y, 480 - hd.end.x, hd.size.y), dimc)
	# 亮區四個角補上暗幕，讓亮區跟黃框一樣是圓角
	for sx in [1.0, -1.0]:
		for sy in [1.0, -1.0]:
			var corner := Vector2(hd.position.x if sx > 0.0 else hd.end.x, hd.position.y if sy > 0.0 else hd.end.y)
			var center := corner + Vector2(sx, sy) * 18.0
			var pts := PackedVector2Array([corner])
			for n in 9:
				var a := n / 8.0 * PI / 2.0
				pts.append(center + Vector2(-sx * cos(a), -sy * sin(a)) * 18.0)
			draw_colored_polygon(pts, dimc)
	draw_style_box(sb_hole, hole.grow(2.0 + 3.0 * (0.5 + 0.5 * sin(clock * 5.0))))
	# 說明框
	var lines: PackedStringArray = (st["text"] as String).split("\n")
	if is_info:
		lines.append("（點任意處繼續）")
	var bh := 30.0 + lines.size() * 30.0
	var by := hole.position.y - bh - 40.0
	if by < 96.0:
		by = hole.end.y + 24.0
	var br := Rect2(36, by, 408, bh)
	draw_style_box(sb_bubble, br)
	for n in lines.size():
		var col := Color("5a3d2b") if not lines[n].begins_with("（") else Color("b08a6a")
		draw_string(font, Vector2(br.position.x, br.position.y + 36.0 + n * 30.0), lines[n], HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 21, col)
	# 手指（指尖對準要點的位置，上下輕點）
	if not is_info:
		var c: Array = cols[st["col"]]
		var tip := _tile_pos(st["col"], max(0, c.size() - 1)) + Vector2(4, 8)
		tip.y += 8.0 * (0.5 + 0.5 * sin(clock * 6.0))
		if Art.ui.has("hand"):
			var hs := Vector2(58, 80)
			draw_texture_rect(Art.ui["hand"], Rect2(tip - Vector2(hs.x * 0.3, 0), hs), false)
		else:
			draw_circle(tip + Vector2(0, 14), 14.0, Color(1, 1, 1, 0.9))
