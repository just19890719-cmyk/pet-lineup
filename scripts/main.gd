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
const LevelData := preload("res://scripts/level_data.gd")
const LevelVariants := preload("res://scripts/level_variants.gd")   # 每關的其他盤面（開局隨機抽一種）
const I18n := preload("res://scripts/i18n.gd")
const MAX_LEVEL := 300

var level: int = 1
var vary_boards := true       # 開局從這一關的幾種盤面裡隨機抽一種、動物也隨機分配（測試參數 --fixed-boards 可關掉）
var force_variant := -1       # 測試用：指定盤面版本（0 = 正式盤面），-1 = 照 vary_boards
var best_level: int = 1       # 玩到過的最遠關卡（選關畫面可以回到 1 ～ best_level）
var top_pad := 0.0            # 動態島／瀏海要讓開的高度（畫面座標），整個畫面往下推這麼多
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
var reveal_btn: Button
var ad_layer: Control
var ads: Node                   # 真廣告（scripts/ads.gd），只有蘋果手機版有作用
var store: Node                 # 內購（scripts/store.gd），只有蘋果手機版有作用
var no_ads := false             # 已買免廣告：不跳插頁廣告，求救道具不用看廣告
var undo_left := -1             # 這一關剩下的免費撤回次數；-1 = 無限
var reveal_free := 0            # 這一關剩下的免費「翻問號」次數
var ad_this_level := false      # 這一關玩家是否已主動看過廣告
var last_ad_ms := 0
var sys_font: Font              # 系統字型（最後的備援）
var lang_fonts: Dictionary = {} # 內建字型："TC"/"SC"/"JP"/"KR" → FontFile
var last_inter_ms := 0          # 上次過關廣告的時間
var hint_steps_left := 0        # 這次提示還會自動接著給幾步
var hint_was_free := false      # 這次提示用的是免費次數
var dead_bonus_given := false   # 這一關已經送過「解不開」的補償撤回
var paid_hint_used := 0         # 這一關用掉幾次非免費的提示（買斷玩家有每關上限）
var paid_reveal_used := 0       # 這一關用掉幾次非免費的翻問號
var hint_btn: Button
var hint_free := 0              # 這一關剩下的免費提示次數
var hint_busy := false          # 正在計算提示
var hint_last: Dictionary = {}  # 上一次給出的提示
var hint_plan: Array = []       # 記住的解法路線：[[走這步之前的局面, 這一步], ...]
var hint: Dictionary = {}       # 目前顯示中的提示：{"k": "c"/"s"/"p", ...}；空 = 沒有
var run_ready := false          # 啟動完成後才開始寫入關卡中途進度
var has_resume := false         # 這次啟動有接續上次的盤面
var slot_open := 3             # 這一關開局就能用的暫存格數（後面的關卡會變少）
var slot_n := 4                 # 畫面上顯示的暫存格數 = 開放的 + 1 格可解鎖
var sfx: Dictionary = {}        # 音效名稱 → AudioStream
var sfx_players: Array = []
var sfx_idx := 0
var music_player: AudioStreamPlayer
var sfx_vol := 1.0              # 音效音量 0.0 ～ 1.0（設定裡的拉桿；0 = 靜音）
var music_vol := 1.0            # 音樂音量 0.0 ～ 1.0
var combo := 0                  # 連續幾步都有消除（音調逐次升高）
var last_tick := -1.0


# ───────────────────────── 初始化 ─────────────────────────
func _ready() -> void:
	Art.load_all()
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC", "Noto Sans TC", "PingFang TC", "Heiti TC"])
	font = sf
	sys_font = sf
	# 內建字型（網頁版沒有系統字型）：繁中、簡中、日文、韓文各一套，其餘語言用繁中那套裡的歐文字母
	for code in ["TC", "SC", "JP", "KR"]:
		var ff := _load_font("res://assets/fonts/NotoSans%s-SemiBold-subset.ttf" % code)
		if ff != null:
			lang_fonts[code] = ff
	# 語言：存檔裡有選過就用選的，沒有就看系統語言
	var saved_lang := _load_text("lang", "")
	I18n.lang = I18n.LANGS.find(saved_lang) if I18n.LANGS.has(saved_lang) else I18n.detect(OS.get_locale())
	# 測試用啟動參數只在開發版生效，正式版一律忽略
	var args: PackedStringArray = OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()
	vary_boards = not args.has("--fixed-boards")
	for a1 in args:
		if a1.begins_with("--variant="):   # 測試用：指定盤面版本（0 = 正式盤面）
			force_variant = int(a1.get_slice("=", 1))
	for a0 in args:
		if a0.begins_with("--lang="):   # 測試用：只影響這次執行
			I18n.lang = max(0, I18n.LANGS.find(a0.get_slice("=", 1)))
	_apply_lang_font()
	_build_theme()
	_build_styles()
	_build_ui()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	no_ads = _load_flag("no_ads")
	_init_store_and_ads()
	# 音量：沒存過就看舊版的開關（關 = 0，開 = 1）
	sfx_vol = _load_volume("sfx_vol", "sfx_off")
	music_vol = _load_volume("music_vol", "music_off")
	_init_audio()
	level = _load_level()
	best_level = max(level, _load_best())
	tut_done = _load_flag("tutorial_done")
	start_level(level)
	has_resume = _load_run()
	run_ready = true
	last_ad_ms = Time.get_ticks_msec()
	last_inter_ms = last_ad_ms
	# 測試用啟動參數（接在 -- 後面）：--skip-title 跳過開始畫面、--tutorial 直接進教學、--win 直接過關
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
	if args.has("--buy"):
		_show_buy()
	for a in args:
		if a.begins_with("--level="):
			start_level(int(a.get_slice("=", 1)))
	if args.has("--language-dialog"):
		_show_language()
	if args.has("--no-ads"):
		no_ads = true   # 只影響這次執行，不寫入存檔
		_update_ui()
	if args.has("--buyer-used-up"):
		# 測試：買斷玩家這一關提示用完時的畫面
		paid_hint_used = BUYER_HINT_PER_LEVEL
		hint_free = 0
		_update_ui()
		_on_hint()
	if args.has("--resume-check"):
		var tiles := 0
		for c in cols:
			tiles += c.size()
		print("resume-check resumed=%s level=%d tiles=%d history=%d undo_left=%d" % [has_resume, level, tiles, history.size(), undo_left])
	if args.has("--hint"):
		_run_hint()
	if args.has("--auto-hint"):
		# 自動照著提示走到過關，用來驗證提示每一步都走得通
		var state := {"moves": 0, "done": false}
		for a2 in args:
			if a2.begins_with("--stop-at="):
				state["stop_at"] = int(a2.get_slice("=", 1))
		var at := Timer.new()
		at.wait_time = 0.02 if args.has("--fast") else 0.12
		at.autostart = true
		at.timeout.connect(func() -> void: _auto_hint_step(state))
		add_child(at)
	if args.has("--ask-undo"):
		undo_left = 0
		_ask_more_undo()
	if args.has("--ask-unlock"):
		_request_unlock(slot_n - 1)
	if args.has("--fake-ad"):
		_dev_fake_ad()
	if args.has("--check-levels"):
		# 逐關載入檢查：每種動物數量剛好等於每欄格數、沒有超出格數的欄
		var bad := 0
		for l in range(1, MAX_LEVEL + 51):
			for v in range(1 + LevelVariants.EXTRA.size()):
				force_variant = v
				start_level(l)
				var cnt := {}
				for c in cols:
					if c.size() > cap:
						bad += 1
					for t in c:
						cnt[t["t"]] = cnt.get(t["t"], 0) + 1
				for k in cnt:
					if cnt[k] != cap:
						bad += 1
				if cols.size() > 8 or slot_open < 1 or slot_open > 3:
					bad += 1
		force_variant = -1
		print("check-levels bad=%d" % bad)
		start_level(level if level <= MAX_LEVEL else 1)
	if args.has("--audio-check"):
		var ms = music_player.stream
		print("audio-check sfx=%d music=%s type=%s loop=%s length=%.1f playing=%s" % [sfx.size(), ms != null, ms.get_class() if ms != null else "-", ms.loop if ms is AudioStreamOggVorbis else false, ms.get_length() if ms != null else 0.0, music_player.playing])
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
	if args.has("--store-shot"):
		dev_btn.visible = false   # 商店截圖用：藏起「開發」按鈕
	if args.has("--level-select"):
		# 測試：假裝玩到第 58 關（只影響這次執行，不寫入存檔），直接開選關畫面
		best_level = 58
		start_level(58)
		_show_level_select()
	if args.has("--tap-test"):
		# 測試：安全區往下推之後，點第 3 欄（用螢幕座標）要真的選到第 3 欄
		await get_tree().create_timer(1.5).timeout
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		var k := float(DisplayServer.window_get_size().x) / get_viewport_rect().size.x
		ev.position = (_tube_rect(2).get_center() + Vector2(0, top_pad)) * k
		ev.global_position = ev.position
		print("tap-test expect local=", _tube_rect(2).get_center())
		get_viewport().push_input(ev)
		print("tap-test top_pad=%.1f sel_col=%d" % [top_pad, sel_col])


## 翻譯：以繁體中文原文查表，查不到就顯示原文
func T(s: String) -> String:
	return I18n.t(s)


## 依目前語言挑主要字型，其他字型與系統字型當備援
func _apply_lang_font() -> void:
	var want: String = I18n.FONT_OF[I18n.lang]
	if not lang_fonts.has(want):
		want = "TC"
	if not lang_fonts.has(want):
		font = sys_font
	else:
		var primary: FontFile = lang_fonts[want]
		var fb: Array[Font] = []
		for code in lang_fonts:
			var f: FontFile = lang_fonts[code]
			if f != primary:
				f.fallbacks = []
				fb.append(f)
		fb.append(sys_font)
		primary.fallbacks = fb
		font = primary
	if theme != null:
		theme.default_font = font


## 換語言：存檔、換字型、重畫所有文字
func _set_lang(i: int) -> void:
	I18n.lang = clampi(i, 0, I18n.LANGS.size() - 1)
	_save_text("lang", I18n.LANGS[I18n.lang])
	_apply_lang_font()
	_update_ui()
	if title_layer != null:
		title_layer.queue_free()
		title_layer = null
		_show_title()
	_show_settings()


func _show_language() -> void:
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
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var tl := Label.new()
	tl.text = T("語言")
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 28)
	tl.add_theme_color_override("font_color", Color("ff7a45"))
	vb.add_child(tl)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for i in I18n.LANGS.size():
		var b := Button.new()
		b.text = I18n.NATIVE[i]
		b.custom_minimum_size = Vector2(176, 46)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		if i == I18n.lang and Art.ui.has("btn_green"):
			b.add_theme_stylebox_override("normal", _sbt("btn_green", Color.WHITE))
			b.add_theme_stylebox_override("hover", _sbt("btn_green", Color.WHITE))
			b.add_theme_color_override("font_outline_color", Color("2c7a2c"))
		var idx := i
		b.pressed.connect(func() -> void: _set_lang(idx))
		_juice(b)
		grid.add_child(b)
	overlay.add_child(panel)
	add_child(overlay)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	move_child(dev_panel, get_child_count() - 1)


## 字太長時自動縮小字級，讓按鈕文字不會超出按鈕（各國語言長度差很多）
func _fit_button(b: Button, base_size: int, max_w: float) -> void:
	var sz := base_size
	while sz > 10:
		var widest := 0.0
		for ln in b.text.split("\n"):
			widest = max(widest, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x)
		if widest <= max_w:
			break
		sz -= 1
	b.add_theme_font_size_override("font_size", sz)


## 單行文字太寬時回傳縮小後的字級
func _fit_size(text: String, base_size: int, max_w: float) -> int:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, base_size).x
	if w <= max_w:
		return base_size
	return max(10, int(floor(base_size * max_w / w)))


func _load_text(key: String, fallback: String) -> String:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return fallback
	return str(cf.get_value("progress", key, fallback))


func _save_text(key: String, v: String) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("progress", key, v)
	cf.save(SAVE_PATH)


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
	hint_label = _make_label(T("點欄位拿起最上面同款動物，再點要放的欄位"), 16, Vector2(0, 86), 480, Color("5a3d2b"), Color(1, 1, 1, 0.9), 4)
	skip_btn = _make_button(T("跳過"), Vector2(8, 14), Vector2(76, 44), func() -> void: _finish_tutorial(), 18)
	skip_btn.visible = false
	settings_btn = _make_button(T("設定"), Vector2(8, 14), Vector2(76, 44), _show_settings, 18)
	undo_btn = _make_button(T("撤回"), Vector2(10, 772), Vector2(109, 66), _on_undo, 17)
	reveal_btn = _make_button(T("翻問號"), Vector2(127, 772), Vector2(109, 66), _on_reveal, 17)
	hint_btn = _make_button(T("提示"), Vector2(244, 772), Vector2(109, 66), _on_hint, 17)
	restart_btn = _make_button(T("重新開始"), Vector2(361, 772), Vector2(109, 66), _on_restart, 17)
	for b in [undo_btn, reveal_btn, hint_btn, restart_btn]:
		b.add_theme_constant_override("line_spacing", -4)
	dev_btn = _make_button("開發", Vector2(396, 14), Vector2(76, 44), _toggle_dev, 18)
	_build_dev_panel()
	# 給玩家的正式版不顯示開發按鈕（從編輯器或執行遊戲.bat 開啟時仍然有）
	dev_btn.visible = OS.is_debug_build()


func _build_dev_panel() -> void:
	dev_panel = PanelContainer.new()
	dev_panel.position = Vector2(30, 44)
	dev_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
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
		["解鎖暫存格", func() -> void: _unlock_slot(slot_n - 1)],
		["跳 10 關", func() -> void: start_level(level + 10)],
		["跳到最後一關", func() -> void: start_level(MAX_LEVEL)],
		["製造快完成的欄", _dev_almost_complete],
		["測試卡死畫面", _show_stuck],
		["換一個隨機盤面", func() -> void: start_level(level, randi() % 1000000)],
		["重置存檔(回第1關)", _dev_reset_save],
		["回開始畫面", _show_title],
		["重看新手教學", _start_tutorial],
		["灑彩帶", _spawn_confetti],
		["重置求救次數", _dev_reset_helpers],
		["切換免廣告", _dev_toggle_no_ads],
		["模擬插頁廣告", _dev_fake_ad],
		["免廣告購買畫面", _show_buy],
		["直接提示一步", _run_hint],
	]
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.custom_minimum_size = Vector2(360, 32)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
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
	_reset_helpers()   # 要在發牌之後：免費撤回次數看這一關開放幾格暫存格
	slots = []
	for k in SLOT_COUNT:
		slots.append(null)
	slot_n = min(SLOT_COUNT, slot_open + 1)
	slot_unlocked = []
	for k in SLOT_COUNT:
		slot_unlocked.append(k < slot_open)
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


func _new_tile(t: String, r: bool) -> Dictionary:
	next_id += 1
	return {"id": next_id, "t": t, "r": r, "off": Vector2.ZERO, "pop": 0.0}


func _generate(sd: int) -> void:
	# 關卡盤面來自 level_data.gd（每關都經解題程式確認解得開）
	var idx := level - 1
	var flip_cols := false
	if idx >= LevelData.DATA.size():
		# 第 100 關之後：循環使用後 50 關的盤面，換一批動物、偶數輪左右對調
		idx = 150 + (level - MAX_LEVEL - 1) % 150
		flip_cols = ((level - MAX_LEVEL - 1) / 150) % 2 == 0
	# 這一關的所有盤面：正式盤面 + 額外幾種，每種都經解題程式確認解得開
	var variants: Array = [LevelData.DATA[idx]]
	for ex in LevelVariants.EXTRA:
		variants.append(ex[idx])
	# 開發工具「換一個隨機盤面」會傳入自訂種子：同樣的方塊重新洗牌（不保證有解）
	var custom := sd != level * 7919 + 17
	var pick := 0
	if force_variant >= 0:
		pick = mini(force_variant, variants.size() - 1)
	elif vary_boards and not custom:
		pick = randi() % variants.size()
	var parts: PackedStringArray = (variants[pick] as String).split(";")
	var head: PackedStringArray = parts[0].split(",")
	cap = int(head[0])
	slot_open = int(head[1])
	var rng := RandomNumberGenerator.new()
	rng.seed = randi() if (vary_boards and not custom and force_variant < 0) else sd
	var pool: Array = Art.KEYS.duplicate()
	_shuffle(pool, rng)
	var texts: Array = Array(parts[1].split("|"))
	if flip_cols:
		texts.reverse()
	var letters: Array = []
	if custom:
		for text in texts:
			for ch in (text as String):
				letters.append(ch)
		_shuffle(letters, rng)
	cols = []
	var li := 0
	for text in texts:
		var col: Array = []
		for ch in (text as String):
			var c: String = letters[li] if custom else ch
			li += 1
			var low := c.to_lower()
			var tile := _new_tile(pool[low.unicode_at(0) - 97], c != low)
			if tile["r"]:
				seen[tile["id"]] = true
			col.append(tile)
		cols.append(col)


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ───────────────────────── 版面 ─────────────────────────
const CONTENT_H := 846.0   # 遊戲內容往下用到的高度（最底下的按鈕到 y=838）；畫面比這個高的部分才有空間讓位


## 動態島／瀏海安全區：把整個畫面往下推，讓關卡標題與設定鈕不被擋住。
## 畫面較矮的手機（空間不夠）最多只推到不會把底下按鈕推出畫面為止。
func _apply_safe_area() -> void:
	var raw := 0.0
	var sim := -1.0
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--safe-top="):   # 測試用：假裝安全區上緣高度（單位：手機螢幕像素）
				sim = float(a.get_slice("=", 1))
	var vp := get_viewport_rect().size
	var win_w := float(DisplayServer.window_get_size().x)
	if sim >= 0.0:
		raw = sim * vp.x / maxf(1.0, win_w)
	elif OS.has_feature("ios") or OS.has_feature("android"):
		var sa := DisplayServer.get_display_safe_area()
		if win_w > 0.0 and sa.size.x > 0:
			raw = float(sa.position.y) * vp.x / win_w
	if raw > 0.0:
		raw += 8.0   # 多留一點呼吸空間
	var pad := clampf(raw, 0.0, maxf(0.0, vp.y - CONTENT_H))
	if absf(pad - top_pad) < 0.01 and get_viewport().canvas_transform.origin.y == pad:
		return
	top_pad = pad
	get_viewport().canvas_transform = Transform2D(0.0, Vector2(0.0, top_pad))
	queue_redraw()


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
	var total := slot_n * SLOT_SIZE + (slot_n - 1) * SLOT_GAP
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
	hint = {}
	_reveal_tops(true)
	var combo_before := combo
	for i in targets:
		_check_complete(i)
	if combo == combo_before:
		combo = 0
	_check_end()
	_update_ui()
	if hint_steps_left > 0 and not game_over and not tut_active:
		hint_steps_left -= 1
		_continue_hint()


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
	fx.append({"kind": "text", "pos": Vector2(cx, tr.position.y - 10), "text": T("完成！"),
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
		# 重玩舊關卡過關時，最遠關卡不能被拉回來
		best_level = max(best_level, level + 1)
		_save_best(best_level)
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
	if undo_left == 0:
		_ask_more_undo()
		return
	if undo_left > 0:
		undo_left -= 1
	hint = {}
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
	if hint_busy:
		return
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
	for k in slot_n:
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
		_request_unlock(k)
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
	_save_run()
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
	for k in slot_n:
		var r := _slot_rect(k)
		if not slot_unlocked[k]:
			if Art.ui.has("slot_lock"):
				var bob := 1.0 + 0.04 * sin(clock * 3.0)
				draw_set_transform(r.get_center(), 0.0, Vector2(bob, bob))
				draw_texture_rect(Art.ui["slot_lock"], Rect2(-r.size / 2.0 - Vector2(3, 3), r.size + Vector2(6, 6)), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if not tut_active:
					var tag := _ad_text(T("看廣告"), T("解鎖"))
					_draw_text_center(tag, Vector2(r.get_center().x, r.end.y + 20), 14, Color.WHITE, Color("5a3a28"))
			else:
				draw_style_box(sb_slot_locked, r)
				_draw_text_center(T("解鎖"), r.get_center() + Vector2(0, 7), 18, Color.WHITE, Color(0.16, 0.13, 0.22))
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
	_draw_hint()
	_draw_tutorial()


func _draw_bg() -> void:
	# 整個畫面被往下推了 top_pad，背景要從 -top_pad 開始畫，才會鋪滿整個螢幕
	var sz := Vector2(size.x, size.y + top_pad)
	var origin := Vector2(0.0, -top_pad)
	if Art.bg_tex != null:
		var ts := Art.bg_tex.get_size()
		var sc: float = max(sz.x / ts.x, sz.y / ts.y)
		var ds := ts * sc
		draw_texture_rect(Art.bg_tex, Rect2(origin + (sz - ds) / 2.0, ds), false)
		return
	var top := Color("bfe8ff")
	var bot := Color("ffe3f0")
	draw_polygon(PackedVector2Array([origin, origin + Vector2(sz.x, 0), origin + sz, origin + Vector2(0, sz.y)]),
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
	level_label.text = T("新手教學") if tut_active else T("第 %d 關") % level
	hint_label.visible = level <= 2 and not tut_active
	undo_btn.visible = not tut_active
	restart_btn.visible = not tut_active
	reveal_btn.visible = not tut_active
	hint_btn.visible = not tut_active
	reveal_btn.disabled = _hidden_tiles().is_empty()
	hint_btn.disabled = game_over or hint_busy
	# 按鈕第二行標出：剩幾次、免費，或要看廣告
	if undo_left < 0:
		undo_btn.text = T("撤回")
	elif undo_left > 0:
		undo_btn.text = T("撤回\n剩 %d 次") % undo_left
	else:
		undo_btn.text = T("補撤回") + _ad_text(T("\n看廣告"), "")
	# 提示與翻問號每關都有上限（看廣告的玩家和買斷的玩家一樣），第二行顯示還剩幾次
	reveal_btn.text = T("翻問號") + _helper_line(reveal_free, _buyer_reveal_left())
	hint_btn.text = T("提示") + _helper_line(hint_free, _buyer_hint_left())
	skip_btn.visible = tut_active
	settings_btn.visible = not tut_active
	undo_btn.disabled = history.is_empty()
	# 停用時把橘色字框換成深灰，灰底上才讀得清楚
	for b in [undo_btn, reveal_btn, hint_btn]:
		b.add_theme_color_override("font_outline_color", Color("5e5148") if b.disabled else Color("b8601a"))
	# 換語言後固定文字也要更新；各國文字長度不同，太長就自動縮小
	restart_btn.text = T("重新開始")
	skip_btn.text = T("跳過")
	settings_btn.text = T("設定")
	hint_label.text = T("點欄位拿起最上面同款動物，再點要放的欄位")
	hint_label.add_theme_font_size_override("font_size", _fit_size(hint_label.text, 16, 410.0))
	level_label.add_theme_font_size_override("font_size", _fit_size(level_label.text, 30, 190.0))
	for b in [undo_btn, reveal_btn, hint_btn, restart_btn]:
		_fit_button(b, 17, 88.0)
	_fit_button(skip_btn, 18, 58.0)
	_fit_button(settings_btn, 18, 58.0)
	_save_run()


func _close_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null


func _show_dialog(title: String, msg: String, buttons: Array, extras: Array = []) -> void:
	_close_overlay()
	_play("pop")
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.offset_top = -top_pad
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var tl := Label.new()
	tl.text = title
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", _fit_size(title, 32, 300.0))
	tl.add_theme_color_override("font_color", Color("ff7a45"))
	vb.add_child(tl)
	if msg != "":
		var ml := Label.new()
		ml.text = msg
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.custom_minimum_size = Vector2(300, 0)
		vb.add_child(ml)
	for ex in extras:
		vb.add_child(ex)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(300, 56)
		btn.focus_mode = Control.FOCUS_NONE
		_fit_button(btn, 22, 268.0)
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
	if level == MAX_LEVEL:
		_show_dialog(T("恭喜全破！"), T("%d 關全部完成，太厲害了！\n後面還有更多關卡等你挑戰") % MAX_LEVEL, [[T("繼續挑戰"), _next_level]])
		return
	_show_dialog(T("過關！"), T("所有動物都排好了，好棒！"), [[T("下一關"), _next_level]])


func _show_stuck() -> void:
	var btns: Array = []
	if not history.is_empty():
		var ut := T("撤回一步")
		if undo_left > 0:
			ut = T("撤回一步（剩 %d 次）") % undo_left
		elif undo_left == 0:
			ut = T("補撤回次數") + _ad_text(T("（看廣告）"), "")
		btns.append([ut, _on_undo])
	if not slot_unlocked[slot_n - 1]:
		btns.append([T("解鎖暫存格") + _ad_text(T("（看廣告）"), ""), func() -> void: _request_unlock(slot_n - 1)])
	if not _hidden_tiles().is_empty():
		btns.append([T("翻開問號") + (T("（免費）") if reveal_free > 0 else _ad_text(T("（看廣告）"), "")), _on_reveal])
	btns.append([T("重新開始"), _on_restart])
	_show_dialog(T("卡住了"), T("沒有可以走的步了"), btns)
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


func _load_best() -> int:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return 1
	return max(1, int(cf.get_value("progress", "best", 1)))


func _save_best(l: int) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("progress", "best", l)
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
	best_level = 1
	_save_best(1)
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
	music_player.volume_db = -15.0   # 外部素材的音樂本身比較大聲，壓低當背景
	add_child(music_player)
	# 背景音樂優先讀立體聲的 ogg，沒有才讀 wav
	var bp := "res://assets/audio/bgm.ogg"
	if not ResourceLoader.exists(bp):
		bp = "res://assets/audio/bgm.wav"
	if ResourceLoader.exists(bp):
		var st = load(bp)
		if st is AudioStreamOggVorbis:
			st.loop = true
		if st is AudioStreamWAV:
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = int(st.get_length() * st.mix_rate)
		music_player.stream = st
		_apply_music_volume()


## 拉桿的 0～1 換成實際增益：用平方讓小聲那一段調起來比較細
func _gain_db(v: float) -> float:
	return linear_to_db(maxf(v * v, 0.0001))


func _apply_music_volume() -> void:
	if music_player == null or music_player.stream == null:
		return
	music_player.volume_db = -15.0 + _gain_db(music_vol)
	if music_vol <= 0.0:
		music_player.stop()
	elif not music_player.playing:
		music_player.play()


func _play(n: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if sfx_vol <= 0.0 or not sfx.has(n) or sfx_players.is_empty():
		return
	var pl: AudioStreamPlayer = sfx_players[sfx_idx]
	sfx_idx = (sfx_idx + 1) % sfx_players.size()
	pl.stream = sfx[n]
	pl.pitch_scale = pitch
	pl.volume_db = vol_db + 2.0 + _gain_db(sfx_vol)   # 音效檔留了餘裕，這裡統一補一點
	pl.play()


func _show_settings() -> void:
	var items: Array = [
		[T("語言：%s") % I18n.NATIVE[I18n.lang], _show_language],
		[T("選關"), _show_level_select],
	]
	if _shop_visible() and not no_ads:
		items.append([T("移除廣告"), _show_buy])
		items.append([T("恢復購買"), _restore_purchase])
	items.append([T("關閉"), _close_overlay])
	var sliders: Array = [
		_volume_row(T("音效"), sfx_vol, _on_sfx_slider, func() -> void: _play("pick")),
		_volume_row(T("音樂"), music_vol, _on_music_slider, Callable()),
	]
	_show_dialog(T("設定"), "", items, sliders)


# ───────────────────────── 選關 ─────────────────────────
const LEVEL_COLS := 5
const LEVEL_BTN := Vector2(58, 48)


## 選關畫面：列出 1 ～ 玩到過的最遠關卡，點一關就回去玩（最遠進度不會被洗掉）
func _show_level_select() -> void:
	_close_overlay()
	_play("pop")
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.offset_top = -top_pad
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var tl := Label.new()
	tl.text = T("選關")
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", _fit_size(tl.text, 32, 300.0))
	tl.add_theme_color_override("font_color", Color("ff7a45"))
	vb.add_child(tl)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LEVEL_COLS * (LEVEL_BTN.x + 8.0) + 18.0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = LEVEL_COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	# 電腦開發版（從編輯器或執行遊戲.bat 開啟）列出全部關卡方便檢查；手機正式版只到玩過的最遠關卡
	var top_level := MAX_LEVEL if OS.is_debug_build() else best_level
	for l in range(1, top_level + 1):
		var b := Button.new()
		b.text = str(l)
		b.custom_minimum_size = LEVEL_BTN
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 20)
		if l == level and Art.ui.has("btn_green"):
			# 目前這一關用綠色標出
			b.add_theme_stylebox_override("normal", _sbt("btn_green", Color.WHITE))
			b.add_theme_stylebox_override("hover", _sbt("btn_green", Color.WHITE))
			b.add_theme_stylebox_override("pressed", _sbt("btn_green", Color(0.86, 0.86, 0.86)))
			b.add_theme_color_override("font_outline_color", Color("2c7a2c"))
			b.add_theme_constant_override("outline_size", 6)
		b.pressed.connect(_pick_level.bind(l))
		_juice(b)
		grid.add_child(b)
	var close := Button.new()
	close.text = T("關閉")
	close.custom_minimum_size = Vector2(300, 56)
	close.focus_mode = Control.FOCUS_NONE
	_fit_button(close, 22, 268.0)
	close.pressed.connect(_close_overlay)
	_juice(close)
	vb.add_child(close)
	overlay.add_child(panel)
	add_child(overlay)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_scroll_to_level(scroll, level)
	move_child(dev_panel, get_child_count() - 1)


## 等版面排好之後，把目前這一關捲到視窗中間附近
func _scroll_to_level(scroll: ScrollContainer, l: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(scroll):
		return
	var row := (l - 1) / LEVEL_COLS
	scroll.scroll_vertical = maxi(0, int(row * (LEVEL_BTN.y + 8.0)) - 150)


func _pick_level(l: int) -> void:
	_close_overlay()
	_save_level(l)
	has_resume = false   # 換了關卡，不再接續上次的盤面
	_leave_title(func() -> void: start_level(l))


# ───────────────────────── 免廣告內購 ─────────────────────────
const AdsScript := preload("res://scripts/ads.gd")
const StoreScript := preload("res://scripts/store.gd")


func _init_store_and_ads() -> void:
	store = StoreScript.new()
	add_child(store)
	store.owned_changed.connect(_on_store_owned)
	store.purchase_finished.connect(_on_purchase_finished)
	store.restore_finished.connect(_on_restore_finished)
	store.start()
	ads = AdsScript.new()
	add_child(ads)
	if not no_ads:
		ads.start()


## 購買入口只在有商店的蘋果手機版出現；開發版也顯示，方便在電腦上看版面（按購買會直接當作買成功）
func _shop_visible() -> bool:
	return StoreScript.available() or OS.is_debug_build()


func _show_buy() -> void:
	var label: String = T("購買") if store.price == "" else T("移除廣告 %s") % store.price
	_show_dialog(T("移除廣告"), T("一次購買，永久移除所有廣告，求救道具不用再看廣告"), [
		[label, _buy_no_ads],
		[T("恢復購買"), _restore_purchase],
		[T("不用了"), _close_overlay],
	])


func _buy_no_ads() -> void:
	if not StoreScript.available():
		_on_store_owned()               # 只有開發版走得到這裡
		_on_purchase_finished(true, false)
		return
	_show_dialog(T("請稍候…"), "", [[T("關閉"), _close_overlay]])
	store.buy()


func _restore_purchase() -> void:
	if not StoreScript.available():
		_on_restore_finished(no_ads)    # 只有開發版走得到這裡
		return
	_show_dialog(T("請稍候…"), "", [[T("關閉"), _close_overlay]])
	store.restore()


func _on_store_owned() -> void:
	no_ads = true
	_save_flag("no_ads", true)
	_update_ui()


func _on_purchase_finished(ok: bool, cancelled: bool) -> void:
	if ok:
		_show_dialog(T("移除廣告"), T("已移除廣告，謝謝你的支持！"), [[T("知道了"), _close_overlay]])
	elif cancelled:
		_close_overlay()
	else:
		_show_dialog(T("移除廣告"), T("購買沒有完成，請稍後再試"), [[T("知道了"), _close_overlay]])


func _on_restore_finished(found: bool) -> void:
	if found:
		_show_dialog(T("恢復購買"), T("已移除廣告，謝謝你的支持！"), [[T("知道了"), _close_overlay]])
	else:
		_show_dialog(T("恢復購買"), T("找不到購買紀錄"), [[T("知道了"), _close_overlay]])


## 一列音量拉桿：左邊名稱、中間拉桿、右邊百分比。on_change(0～1) 拖動時即時呼叫；on_release 放開手指時呼叫（可以是空的 Callable）
func _volume_row(title: String, value: float, on_change: Callable, on_release: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(340, 48)
	var name_l := Label.new()
	name_l.text = title
	name_l.custom_minimum_size = Vector2(78, 0)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", _fit_size(title, 22, 76.0))
	name_l.add_theme_color_override("font_color", Color("5a3d2b"))
	row.add_child(name_l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 100.0
	sl.step = 5.0
	sl.value = roundf(value * 100.0)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(150, 44)
	sl.focus_mode = Control.FOCUS_NONE
	var track := StyleBoxFlat.new()
	track.bg_color = Color("e6d2b4")
	track.set_corner_radius_all(7)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ff9a2e")
	fill.set_corner_radius_all(7)
	fill.content_margin_top = 7
	fill.content_margin_bottom = 7
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _slider_knob()
	sl.add_theme_icon_override("grabber", knob)
	sl.add_theme_icon_override("grabber_highlight", knob)
	sl.add_theme_icon_override("grabber_disabled", knob)
	row.add_child(sl)
	var pct := Label.new()
	pct.text = "%d%%" % int(sl.value)
	pct.custom_minimum_size = Vector2(52, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pct.add_theme_color_override("font_color", Color("5a3d2b"))
	row.add_child(pct)
	sl.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % int(v)
		on_change.call(v / 100.0))
	if on_release.is_valid():
		sl.drag_ended.connect(func(_changed: bool) -> void: on_release.call())
	return row


## 拉桿的圓形把手（橘色、白邊），比內建的大，手指好拖
func _slider_knob() -> Texture2D:
	var d := 34
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d / 2.0, d / 2.0)
	for y in d:
		for x in d:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if r <= 16.0:
				var col := Color("8a4a12") if r > 14.0 else Color.WHITE if r > 11.0 else Color("ff8a1f")
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _on_sfx_slider(v: float) -> void:
	sfx_vol = v
	_save_volume("sfx_vol", v)


func _on_music_slider(v: float) -> void:
	music_vol = v
	_save_volume("music_vol", v)
	_apply_music_volume()


func _load_volume(key: String, old_off_flag: String) -> float:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK and cf.has_section_key("progress", key):
		return clampf(float(cf.get_value("progress", key, 1.0)), 0.0, 1.0)
	return 0.0 if _load_flag(old_off_flag) else 1.0


func _save_volume(key: String, v: float) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("progress", key, v)
	cf.save(SAVE_PATH)


# ───────────────────────── 求救道具與廣告 ─────────────────────────
## 規則（數字集中在這裡，方便之後調整）
const HONEYMOON_LEVELS := 10      # 前幾關：撤回無限、翻問號與提示各免費 1 次、不跳插頁廣告（解鎖暫存格一律要看廣告）
const UNDO_FREE_MID := 3          # 第 11–60 關每關免費撤回次數
const UNDO_FREE_LATE := 5         # 第 61 關以後每關免費撤回次數
const UNDO_PER_AD := [5, 8, 10]   # 看一次廣告補幾次撤回（暫存格 3 格 / 2 格 / 1 格的關卡）
const REVEAL_PER_USE := [3, 5, 8] # 翻問號一次翻開幾個
const HINT_STEPS := [1, 3, 5]     # 提示一次連給幾步
const DEAD_BONUS_UNDO := 3        # 提示發現解不開時送幾次撤回（每關一次）
const BUYER_HINT_PER_LEVEL := 3   # 每關提示上限（免費次數另計；看廣告與買斷的玩家都一樣），避免整關讓程式解完
const BUYER_REVEAL_PER_LEVEL := 3 # 每關翻問號上限（同上）
const AD_MIN_GAP_MS := 240000     # 過關廣告：距離上次廣告滿 4 分鐘才跳（毫秒）
const HINT_NODE_LIMIT := 60000    # 提示最多試幾種局面，超過就放棄
const FAKE_AD_SECONDS := 3


func _reset_helpers() -> void:
	if level <= HONEYMOON_LEVELS:
		undo_left = -1
		reveal_free = 1
		hint_free = 1
	else:
		# 暫存格還有 3 格的關卡給 3 次，暫存格變少的後段關卡給 5 次
		undo_left = UNDO_FREE_MID if _tier() == 0 else UNDO_FREE_LATE
		reveal_free = 0
		hint_free = 0
	ad_this_level = false
	hint = {}
	hint_plan = []
	hint_last = {}
	hint_steps_left = 0
	dead_bonus_given = false
	paid_hint_used = 0
	paid_reveal_used = 0


## 求救按鈕的第二行：免費次數優先顯示；其次是「廣告 剩 N」或買斷的「剩 N 次」；都沒了顯示用完
func _helper_line(free_n: int, left_n: int) -> String:
	if free_n > 0:
		return T("\n免費 %d 次") % free_n
	if left_n <= 0:
		return T("\n用完了")
	return _ad_text(T("\n廣告 剩 %d") % left_n, T("\n剩 %d 次") % left_n)


## 這一關還能用幾次提示 / 翻問號（不含免費次數；看廣告的玩家和買斷的玩家都受這個上限）
func _buyer_hint_left() -> int:
	return max(0, BUYER_HINT_PER_LEVEL - paid_hint_used)


func _buyer_reveal_left() -> int:
	return max(0, BUYER_REVEAL_PER_LEVEL - paid_reveal_used)


func _show_used_up(what: String, cap_n: int) -> void:
	_show_dialog(T("%s用完了") % what, T("每一關最多用 %d 次\n下一關會補滿") % cap_n, [[T("知道了"), _close_overlay]])


## 看完廣告（或買斷直接領）後才計一次
func _paid_hint() -> void:
	paid_hint_used += 1
	_run_hint()


func _paid_reveal() -> void:
	paid_reveal_used += 1
	_do_reveal()


## 求救份量的級距（看關卡位置，不看暫存格數）：第 1–180 關 0、181–255 關 1、256 關起 2。
## 2026-11-17 關卡改成最多 2 格暫存格之後，沿用原本三段的分界，求救份量與免費撤回次數維持不變。
func _tier() -> int:
	var l := level
	if l > MAX_LEVEL:
		l = 150 + (level - MAX_LEVEL - 1) % 150 + 1   # 第 301 關起循環使用第 151–300 關
	return 0 if l <= 180 else 1 if l <= 255 else 2


func _hidden_tiles() -> Array:
	var out: Array = []
	for c in cols:
		for t in c:
			if not t["r"]:
				out.append(t)
	return out


## 按鈕文字：已買免廣告就不提「看廣告」
func _ad_text(with_ad: String, without_ad: String) -> String:
	return without_ad if no_ads else with_ad


func _ask_more_undo() -> void:
	var n: int = UNDO_PER_AD[_tier()]
	_show_dialog(T("撤回用完了"), _ad_text(T("看一段廣告，可以再撤回 %d 次") % n, T("再給你 %d 次撤回") % n), [
		[_ad_text(T("看廣告補 %d 次") % n, T("補 %d 次") % n), func() -> void: _reward_ad(_grant_undo)],
		[T("重新開始（免費）"), _on_restart],
		[T("不用了"), _close_overlay],
	])


func _grant_undo() -> void:
	undo_left += UNDO_PER_AD[_tier()]
	_update_ui()


func _dev_reset_helpers() -> void:
	_reset_helpers()
	_update_ui()


func _dev_toggle_no_ads() -> void:
	no_ads = not no_ads
	_save_flag("no_ads", no_ads)
	_show_dialog("免廣告：%s" % (T("開") if no_ads else T("關")), "", [[T("知道了"), _close_overlay]])


func _dev_fake_ad() -> void:
	_fake_ad(T("過關廣告"), _update_ui)


func _request_unlock(k: int) -> void:
	if slot_unlocked[k]:
		return
	if tut_active:
		_unlock_slot(k)
		return
	_show_dialog(T("解鎖暫存格"), _ad_text(T("看一段廣告，這一關多一格暫存格"), T("這一關多一格暫存格")), [
		[_ad_text(T("看廣告解鎖"), T("解鎖")), func() -> void: _reward_ad(func() -> void: _unlock_slot(k))],
		[T("不用了"), _close_overlay],
	])


func _on_reveal() -> void:
	if _hidden_tiles().is_empty():
		return
	if reveal_free > 0:
		reveal_free -= 1
		_close_overlay()
		_do_reveal()
		return
	if _buyer_reveal_left() <= 0:
		_show_used_up(T("翻問號"), BUYER_REVEAL_PER_LEVEL)
		return
	var n: int = REVEAL_PER_USE[_tier()]
	_show_dialog(T("翻開問號"), _ad_text(T("看一段廣告，隨機翻開 %d 個問號") % n, T("隨機翻開 %d 個問號") % n), [
		[_ad_text(T("看廣告翻開"), T("翻開")), func() -> void: _reward_ad(_paid_reveal)],
		[T("不用了"), _close_overlay],
	])


func _do_reveal() -> void:
	var hidden := _hidden_tiles()
	hidden.shuffle()
	for n in min(REVEAL_PER_USE[_tier()], hidden.size()):
		var t: Dictionary = hidden[n]
		t["r"] = true
		t["pop"] = POP_TIME
		seen[t["id"]] = true
	_play("flip")
	_update_ui()


## 玩家主動看的獎勵廣告：看完才給獎勵；已買免廣告直接給
func _reward_ad(reward: Callable) -> void:
	_close_overlay()
	if no_ads:
		reward.call()
		return
	if AdsScript.available():
		# 蘋果手機版：播真的獎勵廣告，看完才給
		ads.show_rewarded(func() -> void:
			ad_this_level = true
			last_ad_ms = Time.get_ticks_msec()
			reward.call(), func(not_ready: bool) -> void:
			if not_ready:
				# 測試版（AdsScript.DEBUG_ADS）多顯示一行原因，送審前會關掉
				var why: String = "\n\n" + ads.debug_status() if AdsScript.DEBUG_ADS else ""
				_show_dialog(T("獎勵廣告"), T("廣告還沒準備好，請稍後再試") + why, [[T("知道了"), _close_overlay]]))
		return
	ad_this_level = true
	_fake_ad(T("獎勵廣告"), reward)


## 過關後進下一關，符合條件時先跳插頁廣告
func _next_level() -> void:
	var nxt := level + 1
	# 看時間：距離上次「過關廣告」（或開啟遊戲）滿 AD_MIN_GAP_MS 就跳，不管這一關有沒有看過求救廣告
	var due := not no_ads and level > HONEYMOON_LEVELS \
		and Time.get_ticks_msec() - last_inter_ms >= AD_MIN_GAP_MS
	if due:
		last_inter_ms = Time.get_ticks_msec()
		if AdsScript.available():
			ads.show_interstitial(func() -> void: start_level(nxt))
		else:
			_fake_ad(T("過關廣告"), func() -> void: start_level(nxt))
	else:
		start_level(nxt)


## 假廣告只給開發版和網頁試玩版看；手機正式版絕對不能出現「測試用的假廣告」字樣
func _fake_ad_allowed() -> bool:
	return OS.is_debug_build() or OS.has_feature("web")


## 假廣告畫面（還沒接真的廣告服務）：倒數幾秒後自動關閉並執行 then
## 之後接上真的廣告服務時，把下面「手機正式版」那一段換成播放真廣告
func _fake_ad(kind: String, then: Callable) -> void:
	if ad_layer != null:
		return
	if not _fake_ad_allowed():
		# 手機正式版：還沒接真廣告之前直接放行，不顯示任何測試畫面
		_close_overlay()
		last_ad_ms = Time.get_ticks_msec()
		then.call()
		return
	_close_overlay()
	last_ad_ms = Time.get_ticks_msec()
	ad_layer = Control.new()
	ad_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ad_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ad_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.1, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.offset_top = -top_pad
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ad_layer.add_child(bg)
	var texts := [
		[kind, 34, 300.0, Color("ffd34d")],
		[T("這是測試用的假廣告"), 20, 360.0, Color.WHITE],
		[T("正式版會在這裡播放真的廣告"), 18, 394.0, Color(1, 1, 1, 0.7)],
	]
	for it in texts:
		var l := _make_label(it[0], it[1], Vector2(0, it[2]), 480, it[3], Color(0, 0, 0, 0.6), 4)
		remove_child(l)
		ad_layer.add_child(l)
	var count := _make_label(str(FAKE_AD_SECONDS), 72, Vector2(0, 450), 480, Color.WHITE, Color(0, 0, 0, 0.6), 6)
	remove_child(count)
	ad_layer.add_child(count)
	var layer := ad_layer
	var tw := layer.create_tween()
	for s in range(FAKE_AD_SECONDS, 0, -1):
		tw.tween_callback(func() -> void: count.text = str(s))
		tw.tween_interval(1.0)
	tw.tween_callback(func() -> void:
		ad_layer = null
		layer.queue_free()
		then.call())


# ───────────────────────── 關卡中途進度（關掉再開可接著玩） ─────────────────────────
const RUN_HISTORY_KEEP := 20      # 接續後最多還能撤回幾步


func _run_tile_code(t: Dictionary, idx_of: Dictionary, types: Array) -> String:
	if not idx_of.has(t["id"]):
		idx_of[t["id"]] = idx_of.size()
		types.append(char(97 + Art.KEYS.find(t["t"])))
	return "%02d%s" % [idx_of[t["id"]], "1" if (t["r"] or seen.has(t["id"])) else "0"]


func _run_encode(snap_cols: Array, snap_slots: Array, idx_of: Dictionary, types: Array) -> String:
	var parts: Array = []
	for c in snap_cols:
		var s := ""
		for t in c:
			s += _run_tile_code(t, idx_of, types)
		parts.append(s)
	var sl: Array = []
	for t in snap_slots:
		sl.append("-" if t == null else _run_tile_code(t, idx_of, types))
	return "|".join(parts) + ";" + ",".join(sl)


func _save_run() -> void:
	if not run_ready:
		return
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	if tut_active or game_over or cols.is_empty():
		if cf.has_section("run"):
			cf.erase_section("run")
			cf.save(SAVE_PATH)
		return
	var idx_of := {}
	var types: Array = []
	var cur := _run_encode(cols, slots, idx_of, types)
	var hist: Array = []
	for i in range(max(0, history.size() - RUN_HISTORY_KEEP), history.size()):
		hist.append(_run_encode(history[i]["cols"], history[i]["slots"], idx_of, types))
	if idx_of.size() > 99:
		return
	cf.set_value("run", "level", level)
	cf.set_value("run", "cap", cap)
	cf.set_value("run", "types", "".join(types))
	cf.set_value("run", "cur", cur)
	cf.set_value("run", "hist", hist)
	cf.set_value("run", "unlocked", slot_unlocked)
	cf.set_value("run", "undo_left", undo_left)
	cf.set_value("run", "reveal_free", reveal_free)
	cf.set_value("run", "hint_free", hint_free)
	cf.set_value("run", "paid_hint_used", paid_hint_used)
	cf.set_value("run", "paid_reveal_used", paid_reveal_used)
	cf.set_value("run", "dead_bonus_given", dead_bonus_given)
	cf.set_value("run", "ad_this_level", ad_this_level)
	cf.save(SAVE_PATH)


func _run_decode(text: String, types: String, ids: Array, full: bool) -> Dictionary:
	var halves := text.split(";")
	var out_cols: Array = []
	for part in halves[0].split("|"):
		var col: Array = []
		for i in range(0, part.length(), 3):
			col.append(_run_tile(part.substr(i, 3), types, ids, full))
		out_cols.append(col)
	var out_slots: Array = []
	for part in halves[1].split(","):
		out_slots.append(null if part == "-" else _run_tile(part, types, ids, full))
	return {"cols": out_cols, "slots": out_slots}


func _run_tile(code: String, types: String, ids: Array, full: bool) -> Dictionary:
	var idx := int(code.substr(0, 2))
	var d := {"id": ids[idx], "t": Art.KEYS[types.unicode_at(idx) - 97], "r": code[2] == "1"}
	if full:
		d["off"] = Vector2.ZERO
		d["pop"] = 0.0
	return d


## 讀回上次沒玩完的盤面；要在 start_level(level) 之後呼叫。成功回傳 true
func _load_run() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK or not cf.has_section_key("run", "cur"):
		return false
	if int(cf.get_value("run", "level", -1)) != level:
		return false
	var types: String = str(cf.get_value("run", "types", ""))
	var cur_text: String = str(cf.get_value("run", "cur", ""))
	var unlocked = cf.get_value("run", "unlocked", [])
	var saved_cap := int(cf.get_value("run", "cap", 0))
	if types == "" or cur_text.count(";") != 1 or saved_cap < 4 or cur_text.split(";")[0].split("|").size() > 8:
		return false   # 沒有記錄每欄上限的舊存檔不接續（現在開局盤面是隨機的，沒辦法對回去）
	if not (unlocked is Array) or unlocked.size() != SLOT_COUNT:
		return false
	var ids: Array = []
	for i in types.length():
		next_id += 1
		ids.append(next_id)
	var cur := _run_decode(cur_text, types, ids, true)
	if cur["slots"].size() != SLOT_COUNT:
		return false
	cap = saved_cap
	cols = cur["cols"]
	slots = cur["slots"]
	history = []
	for h in cf.get_value("run", "hist", []):
		history.append(_run_decode(str(h), types, ids, false))
	seen.clear()
	for c in cols:
		for t in c:
			if t["r"]:
				seen[t["id"]] = true
	slot_unlocked = unlocked
	undo_left = int(cf.get_value("run", "undo_left", undo_left))
	reveal_free = int(cf.get_value("run", "reveal_free", reveal_free))
	hint_free = int(cf.get_value("run", "hint_free", hint_free))
	paid_hint_used = int(cf.get_value("run", "paid_hint_used", 0))
	paid_reveal_used = int(cf.get_value("run", "paid_reveal_used", 0))
	dead_bonus_given = bool(cf.get_value("run", "dead_bonus_given", false))
	ad_this_level = bool(cf.get_value("run", "ad_this_level", false))
	sel_col = -1
	sel_slot = -1
	fx.clear()
	game_over = false
	_layout()
	_update_ui()
	return true


# ───────────────────────── 提示一步 ─────────────────────────
func _on_hint() -> void:
	if game_over or hint_busy or tut_active:
		return
	if hint_free > 0:
		hint_free -= 1
		hint_was_free = true
		_close_overlay()
		_run_hint()
		return
	hint_was_free = false
	if _buyer_hint_left() <= 0:
		_show_used_up(T("提示"), BUYER_HINT_PER_LEVEL)
		return
	var n: int = HINT_STEPS[_tier()]
	var with_ad := T("看一段廣告，告訴你下一步怎麼走") if n == 1 else T("看一段廣告，告訴你接下來 %d 步怎麼走") % n
	var without_ad := T("告訴你下一步怎麼走") if n == 1 else T("告訴你接下來 %d 步怎麼走") % n
	_show_dialog(T("提示"), _ad_text(with_ad, without_ad), [
		[_ad_text(T("看廣告拿提示"), T("拿提示")), func() -> void: _reward_ad(_paid_hint)],
		[T("不用了"), _close_overlay],
	])


func _run_hint() -> void:
	if hint_busy or game_over or tut_active:
		return
	hint_busy = true
	hint = {}
	_update_ui()
	var tip := _make_label(T("想一下…"), 22, Vector2(0, 92), 480, Color.WHITE, Color("5a3a28"), 6)
	var lv := level
	var hs := history.size()
	var res: Dictionary = await _solve_hint()
	tip.queue_free()
	hint_busy = false
	if lv != level or hs != history.size() or game_over:
		_update_ui()
		return
	hint_steps_left = 0
	if res.is_empty() or res.get("fail", "") == "none":
		# 解不開：這次提示不算（免費次數還回去），並送幾次撤回讓玩家退回去（每關一次）
		if hint_was_free:
			hint_free += 1
		elif paid_hint_used > 0:
			paid_hint_used -= 1
		var msg := T("照現在的排法已經過不了關\n建議撤回幾步，或重新開始")
		if not dead_bonus_given and undo_left >= 0:
			dead_bonus_given = true
			undo_left += DEAD_BONUS_UNDO
			msg = T("照現在的排法已經過不了關\n送你 %d 次撤回，退回去再試試") % DEAD_BONUS_UNDO
		_show_dialog(T("這樣排解不開了"), msg, [
			[T("撤回一步"), _on_undo], [T("重新開始"), _on_restart], [T("知道了"), _close_overlay]])
	elif res.has("fail"):
		hint_free += 1   # 沒算出來，這次不算（還一次免費提示）
		_show_dialog(T("想不出來"), T("這個局面太複雜了\n這次提示不算，還你一次免費提示"), [[T("知道了"), _close_overlay]])
	else:
		hint = res
		hint_steps_left = HINT_STEPS[_tier()] - 1
		_play("step")
	hint_was_free = false
	_update_ui()


## 提示連給幾步時，玩家走完一步後自動接著標出下一步（不另外收費）
func _continue_hint() -> void:
	if hint_busy or game_over or tut_active:
		return
	hint_busy = true
	var lv := level
	var hs := history.size()
	var res: Dictionary = await _solve_hint()
	hint_busy = false
	if lv != level or hs != history.size() or game_over or res.is_empty() or res.has("fail"):
		hint_steps_left = 0
	else:
		hint = res
	_update_ui()


func _hint_letter(t: Dictionary) -> String:
	return char(97 + Art.KEYS.find(t["t"]))


## 欄位字串最上面那一格一定是翻開的（大寫）
func _top_up(col: String) -> String:
	if col == "":
		return col
	var n := col.length()
	return col.substr(0, n - 1) + col[n - 1].to_upper()


## 目前局面轉成解題用的字串：每欄由下往上，一個字母一隻動物（不分翻開與否，跟 tools/gen_levels.py 同一個模型）
func _hint_state() -> Array:
	var c0: Array = []
	for c in cols:
		var s := ""
		for t in c:
			s += _hint_letter(t)
		c0.append(s)
	var sl: Array = []
	var nslots := 0
	for k in slot_n:
		if slot_unlocked[k]:
			nslots += 1
			if slots[k] != null:
				sl.append(_hint_letter(slots[k]))
	sl.sort()
	return [c0, "".join(sl), nslots]


func _hint_key(c: Array, s: String) -> String:
	var sorted_c := c.duplicate()
	sorted_c.sort()
	return "|".join(sorted_c) + ";" + s


## 找出下一步提示。先看記住的解法路線還能不能用（玩家照著走就沿用，才不會前後矛盾），不行才重算。
## 回傳第一步：{"k":"c","a":來源欄,"b":目標欄}、{"k":"s","t":動物,"b":目標欄}、{"k":"p","a":來源欄}
## 解不開回傳 {"fail":"none"}，超過搜尋上限回傳 {"fail":"limit"}
func _solve_hint() -> Dictionary:
	var st := _hint_state()
	var c0: Array = st[0]
	var s0: String = st[1]
	var nslots: int = st[2]
	var real_key := "|".join(c0) + ";" + s0   # 不排序：欄的位置也要一樣，記住的步驟才對得上
	for i in hint_plan.size():
		if hint_plan[i][0] == real_key:
			hint_plan = hint_plan.slice(i)
			hint_last = hint_plan[0][1]
			return hint_last
	# 解題程式把一整串同款當成一步，但遊戲裡問號要翻開才搬得動，所以一步可能要分幾次搬
	if not hint_plan.is_empty() and hint_last.get("k", "") == "c":
		var ca: String = c0[hint_last["a"]]
		var cb: String = c0[hint_last["b"]]
		if ca != "" and cb != "" and cb.length() < cap and ca[ca.length() - 1] == cb[cb.length() - 1]:
			return hint_last
	hint_plan = []
	hint_last = {}
	# 深度優先搜尋；每個節點記父節點與走法，找到解後回頭串出整條路線
	var node_par: Array = [-1]
	var node_move: Array = [{}]
	var node_real: Array = [real_key]
	var stack: Array = [[c0, s0, 0]]
	var visited := {}
	var count := 0
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var c: Array = it[0]
		var s: String = it[1]
		var ni: int = it[2]
		var clear := s == ""
		if clear:
			for x in c:
				if x != "":
					clear = false
					break
		if clear:
			var path: Array = []
			var cur := ni
			while node_par[cur] >= 0:
				path.append([node_real[node_par[cur]], node_move[cur]])
				cur = node_par[cur]
			path.reverse()
			hint_plan = path
			hint_last = {} if path.is_empty() else path[0][1]
			return hint_last
		var key := _hint_key(c, s)
		if visited.has(key):
			continue
		visited[key] = true
		count += 1
		if count > HINT_NODE_LIMIT:
			return {"fail": "limit"}
		if count % 250 == 0:
			await get_tree().process_frame
		var mv := _sim_moves(c, s, nslots)
		for idx in range(mv.size() - 1, -1, -1):
			var m: Array = mv[idx]
			node_par.append(ni)
			node_move.append(m[3])
			node_real.append("|".join(m[1]) + ";" + m[2])
			stack.append([m[1], m[2], node_par.size() - 1])
	return {"fail": "none"}


## 列出某個局面所有可走的步，依「越像好棋越前面」排序。
## 順序必須跟 tools/gen_levels.py 的 moves() 完全一樣（同優先度維持產生順序），
## 這樣每一關從開局搜尋的節點數才會跟產生關卡時相同，保證在上限內算得出來。
func _sim_moves(c: Array, s: String, nslots: int) -> Array:
	var out: Array = []
	var n := c.size()
	for i in n:
		var a: String = c[i]
		if a == "":
			continue
		var al := a.length()
		var x := a[al - 1]
		var r := 1
		while r < al and a[al - 1 - r] == x:
			r += 1
		var seen_empty := false
		for j in n:
			if j == i:
				continue
			var b: String = c[j]
			if b.length() >= cap:
				continue
			var pri := 0
			if b != "":
				if b[b.length() - 1] != x:
					continue
			else:
				if r == al or seen_empty:
					continue
				seen_empty = true
				pri = 3
			var m: int = min(r, cap - b.length())
			var nc := c.duplicate()
			nc[i] = a.substr(0, al - m)
			var nb := b + x.repeat(m)
			nc[j] = "" if (nb.length() == cap and nb == x.repeat(cap)) else nb
			out.append([pri, nc, s, {"k": "c", "a": i, "b": j}])
	var done := {}
	for si in s.length():
		var x2 := s[si]
		if done.has(x2):
			continue
		done[x2] = true
		var seen_empty2 := false
		for j in n:
			var b2: String = c[j]
			if b2.length() >= cap:
				continue
			var pri2 := 1
			if b2 != "":
				if b2[b2.length() - 1] != x2:
					continue
			else:
				if seen_empty2:
					continue
				seen_empty2 = true
				pri2 = 4
			var nc2 := c.duplicate()
			var nb2 := b2 + x2
			nc2[j] = "" if (nb2.length() == cap and nb2 == x2.repeat(cap)) else nb2
			out.append([pri2, nc2, s.substr(0, si) + s.substr(si + 1), {"k": "s", "t": x2, "b": j}])
	if s.length() < nslots:
		for i in n:
			var a3: String = c[i]
			if a3 == "":
				continue
			var al3 := a3.length()
			var good := false
			if al3 > 1:
				var under := a3[al3 - 2]
				for j in n:
					if j != i and c[j] != "" and (c[j] as String)[(c[j] as String).length() - 1] == under:
						good = true
						break
			var nc3 := c.duplicate()
			nc3[i] = a3.substr(0, al3 - 1)
			var chars: Array = []
			for ch in s:
				chars.append(ch)
			chars.append(a3[al3 - 1])
			chars.sort()
			out.append([5 if good else 6, nc3, "".join(chars), {"k": "p", "a": i}])
	var ordered: Array = []
	for pri_level in 7:
		for m2 in out:
			if m2[0] == pri_level:
				ordered.append(m2)
	return ordered


## 測試用：有提示就照著點，沒提示就要一個
func _auto_hint_step(state: Dictionary) -> void:
	if state["done"]:
		if not OS.get_cmdline_user_args().has("--store-shot"):   # 截圖時停住等動畫結束
			get_tree().quit()
		return
	if hint_busy:
		return
	if game_over:
		state["done"] = true
		print("auto-hint 過關 level=%d moves=%d" % [level, state["moves"]])
		return
	if overlay != null:
		state["done"] = true
		print("auto-hint 中斷（跳出對話框） level=%d moves=%d" % [level, state["moves"]])
		return
	if hint.is_empty():
		_run_hint()
		return
	var h := hint
	var limit: int = state.get("stop_at", -1)
	state["moves"] += 1
	if h["k"] == "c":
		sel_col = -1
		sel_slot = -1
		_tap_col(h["a"])
		_tap_col(h["b"])
	elif h["k"] == "p":
		sel_col = -1
		sel_slot = -1
		_tap_col(h["a"])
		for k in slot_n:
			if slot_unlocked[k] and slots[k] == null:
				_tap_slot(k)
				break
	else:
		sel_col = -1
		sel_slot = -1
		for k in slot_n:
			if slots[k] != null and _hint_letter(slots[k]) == h["t"]:
				_tap_slot(k)
				break
		_tap_col(h["b"])
	hint = {}
	if limit > 0 and state["moves"] >= limit:
		state["done"] = true
		print("auto-hint 停在第 %d 步" % state["moves"])


func _draw_hint() -> void:
	if hint.is_empty() or game_over or tut_active:
		return
	var src := Rect2()
	var dst := Rect2()
	var tip := Vector2.ZERO
	var kind: String = hint["k"]
	if kind == "s":
		var found := -1
		for k in slot_n:
			if slots[k] != null and _hint_letter(slots[k]) == hint["t"]:
				found = k
				break
		if found < 0:
			return
		src = _slot_rect(found).grow(6)
		tip = src.get_center() + Vector2(4, 6)
	else:
		var a: int = hint["a"]
		if a >= cols.size() or cols[a].is_empty():
			return
		src = _tube_rect(a).grow(6)
		tip = _tile_pos(a, cols[a].size() - 1) + Vector2(4, 8)
	if kind == "p":
		var free := -1
		for k in slot_n:
			if slot_unlocked[k] and slots[k] == null:
				free = k
				break
		if free < 0:
			return
		dst = _slot_rect(free).grow(6)
	else:
		dst = _tube_rect(hint["b"]).grow(6)
	var pulse := 2.0 + 3.0 * (0.5 + 0.5 * sin(clock * 5.0))
	draw_style_box(sb_hole, src.grow(pulse))
	draw_style_box(sb_hole, dst.grow(pulse))
	var marks := [[src, "1"], [dst, "2"]]
	for mk in marks:
		var rc: Rect2 = mk[0]
		var p := Vector2(rc.get_center().x, rc.position.y - 4)
		draw_circle(p, 14.0, Color("ffd34d"))
		draw_arc(p, 14.0, 0, TAU, 24, Color("5a3a28"), 2.0, true)
		_draw_text_center(mk[1], p + Vector2(0, 7), 19, Color("5a3a28"), Color("ffd34d"))
	tip.y += 8.0 * (0.5 + 0.5 * sin(clock * 6.0))
	if Art.ui.has("hand"):
		var hs := Vector2(58, 80)
		draw_texture_rect(Art.ui["hand"], Rect2(tip - Vector2(hs.x * 0.3, 0), hs), false)


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
		bg.offset_top = -top_pad   # 整個畫面被往下推了，背景要往上補回去，不然最上面會露出空白
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_layer.add_child(bg)
	else:
		var cr := ColorRect.new()
		cr.color = Color("ffe3f0")
		cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cr.offset_top = -top_pad
		title_layer.add_child(cr)
	# 標題
	# 標題圖是中文字，只有中文語系用圖；其他語言先用文字顯示翻譯後的名稱
	if Art.ui.has("logo") and I18n.lang <= 1:
		var logo := _title_pic("logo", Rect2(24, 120, 432, 130))
		var lt := logo.create_tween().set_loops()
		lt.tween_property(logo, "position:y", 132.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		lt.tween_property(logo, "position:y", 120.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		var title_text := T("萌寵排排站")
		var tl := _make_label(title_text, _fit_size(title_text, 60, 430.0), Vector2(0, 140), 480, Color("ffb020"), Color("5a3a28"), 14)
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
	var sb := _make_button(T("開始遊戲"), Vector2(105, 380), Vector2(270, 86), _on_title_start, 32)
	remove_child(sb)
	title_layer.add_child(sb)
	if Art.ui.has("btn_green"):
		sb.add_theme_stylebox_override("normal", _sbt("btn_green", Color.WHITE))
		sb.add_theme_stylebox_override("hover", _sbt("btn_green", Color.WHITE))
		sb.add_theme_stylebox_override("pressed", _sbt("btn_green", Color(0.86, 0.86, 0.86)))
		sb.add_theme_color_override("font_outline_color", Color("2c7a2c"))
		sb.add_theme_constant_override("outline_size", 8)
	_fit_button(sb, 32, 226.0)
	var stb := _make_button(T("設定"), Vector2(396, 14), Vector2(76, 44), _show_settings, 18)
	_fit_button(stb, 18, 58.0)
	remove_child(stb)
	title_layer.add_child(stb)
	# 進度說明
	var info := T("第一次玩會先帶你做新手教學") if not tut_done else T("目前進度：第 %d 關") % level
	if tut_done and has_resume:
		info += T("（接續上次）")
	var il := _make_label(info, _fit_size(info, 19, 452.0), Vector2(0, 484), 480, Color("5a3d2b"), Color(1, 1, 1, 0.95), 6)
	remove_child(il)
	title_layer.add_child(il)
	if tut_done:
		var tb := _make_button(T("玩法教學"), Vector2(50, 540), Vector2(180, 52), func() -> void: _leave_title(_start_tutorial), 19)
		_fit_button(tb, 19, 150.0)
		remove_child(tb)
		title_layer.add_child(tb)
		var lb := _make_button(T("選關"), Vector2(250, 540), Vector2(180, 52), _show_level_select, 19)
		_fit_button(lb, 19, 150.0)
		remove_child(lb)
		title_layer.add_child(lb)
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
	if not tut_done:
		_leave_title(_start_tutorial)
	elif has_resume:
		# 接續上次沒玩完的盤面，不重新發牌
		has_resume = false
		_leave_title(_update_ui)
	else:
		_leave_title(func() -> void: start_level(level))


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
	slot_open = 3
	slot_n = 4
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
	_show_dialog(T("學會了！"), T("你已經會玩了\n開始排動物吧！"), [[T("開始遊戲"), func() -> void: start_level(level)]])


func _draw_tutorial() -> void:
	if not tut_active or game_over or tut_step >= TUT.size():
		return
	var st: Dictionary = TUT[tut_step]
	var is_info: bool = st.has("info")
	var hole: Rect2
	if is_info:
		hole = _slot_rect(0).merge(_slot_rect(slot_n - 1)).grow(10)
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
	var lines: PackedStringArray = T(st["text"] as String).split("\n")
	if is_info:
		lines.append(T("（點任意處繼續）"))
	var bh := 30.0 + lines.size() * 30.0
	var by := hole.position.y - bh - 40.0
	if by < 96.0:
		by = hole.end.y + 24.0
	var br := Rect2(36, by, 408, bh)
	draw_style_box(sb_bubble, br)
	for n in lines.size():
		var col := Color("b08a6a") if (is_info and n == lines.size() - 1) else Color("5a3d2b")
		var fsz := _fit_size(lines[n], 21, br.size.x - 24.0)
		draw_string(font, Vector2(br.position.x, br.position.y + 36.0 + n * 30.0), lines[n], HORIZONTAL_ALIGNMENT_CENTER, br.size.x, fsz, col)
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
