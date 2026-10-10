extends Control

## 音效与 BGM 试听台：支持 6 大场景正式 BGM 即点试听、全量 SFX 轮播，以及
## 「器型音色候选 A/B 对比」（挑定稿用）。
##
## 用法：godot --path . res://tests/AudioGallery.tscn   （要真实出声，不要加 --headless）
##   R = 重听全部 SFX　空格 = 重播最后一声　数字 1..9 = 直听第 N 个候选　Esc = 退出
##
## 候选模式的数据源是 res://assets/audio/sfx_cand/cand_meta.json（由
## `python3 tools/bake_sfx.py --cand` 生成，含 peak/时长/配方参数）。
## 候选绝不注册进 AudioManager —— 挑剩的落选声若进了 sfx_dict，就是一堆哑 key，
## 会同时污染 sfx_keys() 轮播与 UnitRunner 的注册表判据。所以这里自带一个
## AudioStreamPlayer 挂 SFX 总线直接 load wav，与游戏正式音走同一条总线（响度可比）。
## sfx_cand/ 目录清空后，本页自动退回原来的「SFX 轮播 → BGM」流程。

const SFX_GAP := 0.42         ## 每条音效之间的间隔（秒）
const BGM_HOLD := 6.0         ## 自动轮播时每段 BGM 试听时长
const CAND_DIR := "res://assets/audio/sfx_cand"
const CAND_MANIFEST := "cand_meta.json"
const CAND_BURST_GAP := 0.55  ## 连发时每声之间的间隔（够耳朵把上一声放下）
const CAND_BURST_ROUNDS := 3  ## 连发轮数：一轮 A→B→C，共 3 轮，够建立比较记忆
const COMBO_ROW_W := 430.0    ## 每个候选族一栏，两栏并排
const STATUS_W := 860.0       ## 读数行的换行宽度（与 tscn 里 Current 的宽度同源）
const WHIFF_GAP_MS := 50.0    ## 组合试听里 破空 → 命中 的间隔，与近战 tween 的前摇 0.05s 同源
const HIT_LAG_MS := 5.0       ## 命中材质层 → 受击身体声 的间隔（同帧结算，留一点起音差）
const IMPACT_SCALE := 0.95    ## 命中层相对响度，与 FloatingWeapon.MELEE_IMPACT_SCALE 同档

const PHASE_SFX := 0
const PHASE_BGM := 1
const PHASE_MANUAL := 2
const PHASE_CAND := 3         ## 候选挑选：静默等点按，不自动轮播

## 组合试听要用的两族（近战双层 = 前摇破空 + 命中材质），键名即族名
const COMBO_WHOOSH_FAMILY := "whoosh_light"
const COMBO_IMPACT_FAMILY := "impact_blade"

const FAMILY_CN := {
	"impact_blade": "刃金入体（剑/刀/剪）",
	"impact_blunt": "钝器砸击（锤/锏/盾/尺）",
	"whoosh_light": "轻器破空（前摇层）",
	"drum_boom": "春雷鼓（施法与落点）",
}

const BGM_LABELS := {
	"menu": "主菜单 (menu · 60 BPM 古铜钟磬/幽谷泛音)",
	"battle": "战斗 (battle · 120 BPM 冷冽古琴/仪式战鼓)",
	"shop": "商店 (shop · 76 BPM 冷月寒玉微磬/静谧)",
	"trial": "Boss/精英 (trial · 144 BPM 压迫暗脉冲/古金重击)",
	"victory": "胜利 (victory · 88 BPM 破晓钟琴/零延迟起奏)",
	"defeat": "失败 (defeat · 58 BPM 沉鼓碎筝/零延迟起奏)",
}

@onready var title: Label = $Title
@onready var current: Label = $Current

var _keys: Array = []
var _bgm_keys: Array = ["menu", "battle", "shop", "trial", "victory", "defeat"]
var _idx: int = 0
var _phase: int = 0            ## 0=逐条音效 1=BGM 2=结束或手动点选 3=候选挑选
var _timer: float = 0.0
var _last_key: String = ""

var _cand_player: AudioStreamPlayer
var _cands: Dictionary = {}    ## 族名 -> {字母: 参数字典}，读自 cand_meta.json
var _sel: Dictionary = {}      ## 族名 -> 当前选中的候选字母（按钮上的 ● 就是它）
var _cand_buttons: Array = []  ## 数字键 1..9 的直听顺序
var _cand_box: Control
var _bgm_box: Control
var _mode_btn: Button
var _burst_seq: int = 0        ## 连发令牌：再点一次即作废上一轮

func _ready() -> void:
	_keys = AudioManager.sfx_keys()
	_keys.sort()
	_idx = 0
	_timer = 0.2

	_cand_player = AudioStreamPlayer.new()
	_cand_player.bus = AudioManager.BUS_SFX
	add_child(_cand_player)

	_cands = _load_cand_manifest()
	_build_cand_box()
	_build_bgm_buttons()
	_build_mode_button()

	if _cands.is_empty():
		_phase = PHASE_SFX
		_cand_box.visible = false
		_bgm_box.visible = false
		title.text = "音效与 BGM 试听台 · %d 个音效 / %d 首 BGM（可点下方按钮直切 BGM）" % [_keys.size(), _bgm_keys.size()]
	else:
		_phase = PHASE_CAND
		_bgm_box.visible = false
		title.text = "音色候选 A/B · %d 族 / %d 个候选（点一下独听，点「连发」交替对比）" % [_cands.size(), _cand_buttons.size()]
	current.text = "准备…"

	if DisplayServer.get_name() == "headless":
		print("[AUDIO_GALLERY] Headless 模式自动跳过试听，音效 key 数量: %d, BGM 数量: %d, 候选族: %d" % [_keys.size(), _bgm_keys.size(), _cands.size()])
		await get_tree().create_timer(0.1).timeout
		get_tree().quit(0)

## 候选清单读 cand_meta.json：参数与烘焙端同源，不在这里手抄一份（手抄必漂移）
func _load_cand_manifest() -> Dictionary:
	var raw := FileAccess.get_file_as_string("%s/%s" % [CAND_DIR, CAND_MANIFEST])
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("cand_meta.json 解析失败，候选页跳过")
		return {}
	var out: Dictionary = {}
	for family in (parsed as Dictionary):
		var letters: Variant = (parsed as Dictionary)[family]
		if typeof(letters) != TYPE_DICTIONARY:
			continue
		var kept: Dictionary = {}
		for letter in (letters as Dictionary):
			var info: Variant = (letters as Dictionary)[letter]
			if typeof(info) == TYPE_DICTIONARY and ResourceLoader.exists(_cand_path(info)):
				kept[letter] = info
		if kept.is_empty():
			continue
		out[family] = kept
		_sel[family] = _first_letter(kept)
	return out

## Array 没有 min()，取排序后的第一个字母当默认选中
func _first_letter(set: Dictionary) -> String:
	var letters: Array = set.keys()
	letters.sort()
	return String(letters[0])

func _cand_path(info: Dictionary) -> String:
	return "%s/%s.wav" % [CAND_DIR, String(info.get("stem", ""))]

func _build_mode_button() -> void:
	_mode_btn = Button.new()
	_mode_btn.text = "BGM 试听台" if not _cands.is_empty() else "候选试听台"
	_mode_btn.position = Vector2(690, 24)
	_mode_btn.custom_minimum_size = Vector2(238, 34)
	GameStyle.button(_mode_btn, GameStyle.NAVY2, GameStyle.GOLD, 14, GameStyle.PAPER)
	_mode_btn.pressed.connect(_toggle_mode)
	add_child(_mode_btn)

func _toggle_mode() -> void:
	var show_bgm: bool = _bgm_box.visible
	_bgm_box.visible = not show_bgm
	_cand_box.visible = show_bgm
	_mode_btn.text = "候选试听台" if show_bgm else "BGM 试听台"
	_phase = PHASE_MANUAL
	_show("切到 " + _mode_btn.text)

func _build_cand_box() -> void:
	_cand_box = GridContainer.new()
	(_cand_box as GridContainer).columns = 2
	_cand_box.position = Vector2(32, 150)
	_cand_box.add_theme_constant_override("h_separation", 16)
	_cand_box.add_theme_constant_override("v_separation", 10)
	add_child(_cand_box)

	if _cands.is_empty():
		_cand_box.visible = false
		return

	var families: Array = _cands.keys()
	families.sort()
	for family in families:
		_cand_box.add_child(_build_family_section(String(family)))
	_cand_box.add_child(_build_combo_section())

func _build_family_section(family: String) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(COMBO_ROW_W, 0)
	box.add_theme_constant_override("separation", 6)

	var head := Label.new()
	head.text = "%s · %s" % [family, FAMILY_CN.get(family, "音色族")]
	head.custom_minimum_size = Vector2(0, 24)
	GameStyle.label(head, 15, GameStyle.GOLD_EDGE)
	box.add_child(head)

	var letters: Array = (_cands[family] as Dictionary).keys()
	letters.sort()
	for letter in letters:
		box.add_child(_build_cand_button(family, String(letter)))

	var burst := Button.new()
	burst.text = "连发 %s ×%d 轮" % [" → ".join(PackedStringArray(letters)), CAND_BURST_ROUNDS]
	burst.custom_minimum_size = Vector2(COMBO_ROW_W, 30)
	GameStyle.button(burst, GameStyle.NAVY2, GameStyle.GOLD_DK, 13, GameStyle.PAPER_DIM)
	burst.pressed.connect(_burst_family.bind(family))
	box.add_child(burst)
	return box

func _build_cand_button(family: String, letter: String) -> Button:
	var info: Dictionary = _cands[family][letter]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(COMBO_ROW_W, 34)
	btn.set_meta("family", family)
	btn.set_meta("letter", letter)
	# 试听台唯一一次关掉按钮统一点击音：GameStyle.button() 会在 pressed 上挂 ui_click，
	# 而这里要听的正是候选本身，那声玉叩会污染每一次 A/B 比较。
	btn.set_meta("sfx_wired", true)
	GameStyle.button(btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER)
	_refresh_cand_label(btn)
	btn.pressed.connect(_on_cand_pressed.bind(family, letter))
	_cand_buttons.append(btn)
	return btn

## 选中态直接写进按钮文字（●/○），不靠颜色 —— 触屏上「看着像能点」才算数
func _refresh_cand_label(btn: Button) -> void:
	var family := String(btn.get_meta("family"))
	var letter := String(btn.get_meta("letter"))
	var info: Dictionary = _cands[family][letter]
	var mark := "●" if String(_sel.get(family, "")) == letter else "○"
	btn.text = "%s %s · %.3fs · peak %.2f" % [mark, letter, float(info.get("dur", 0.0)), float(info.get("peak", 0.0))]

func _on_cand_pressed(family: String, letter: String) -> void:
	_burst_seq += 1
	_sel[family] = letter
	_refresh_all_labels()
	var info: Dictionary = _cands[family][letter]
	_play_cand(info, 1.0)
	_show_cand("独听 %s · %s" % [family, letter], info)

func _play_cand(info: Dictionary, scale: float) -> void:
	var stream := load(_cand_path(info)) as AudioStream
	if stream == null:
		push_warning("候选 wav 加载失败: " + _cand_path(info))
		return
	_cand_player.stream = stream
	_cand_player.volume_db = linear_to_db(clampf(scale, 0.05, 2.5))
	_cand_player.pitch_scale = 1.0     ## 固定音高：A/B 比的必须是音色，不是随机的抖音高
	_cand_player.play()

func _show_cand(prefix: String, info: Dictionary) -> void:
	var line := "%s\n%s · dur %.3fs · peak %.2f\n%s" % [
		prefix, String(info.get("stem", "")), float(info.get("dur", 0.0)),
		float(info.get("peak", 0.0)), String(info.get("meta", "无参数记录"))]
	current.text = GameStyle.wrap_cjk(line, GameStyle.body_font(), 14, STATUS_W)
	print("[GALLERY] " + line.replace("\n", " "))

func _build_combo_section() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(COMBO_ROW_W, 0)
	box.add_theme_constant_override("separation", 6)

	var head := Label.new()
	head.text = "组合试听（验三件套会不会糊）"
	head.custom_minimum_size = Vector2(0, 24)
	GameStyle.label(head, 15, GameStyle.GOLD_EDGE)
	box.add_child(head)

	var hit := Button.new()
	hit.text = "打中：破空 → %.0fms 刃金 → %.0fms 受击" % [WHIFF_GAP_MS, HIT_LAG_MS]
	hit.custom_minimum_size = Vector2(COMBO_ROW_W, 34)
	GameStyle.button(hit, GameStyle.NAVY2, GameStyle.GOLD, 14, GameStyle.PAPER)
	hit.pressed.connect(_play_combo.bind(true))
	box.add_child(hit)

	var whiff := Button.new()
	whiff.text = "挥空：只有破空（命中层不出声）"
	whiff.custom_minimum_size = Vector2(COMBO_ROW_W, 34)
	GameStyle.button(whiff, GameStyle.NAVY2, GameStyle.GOLD_DK, 14, GameStyle.PAPER_DIM)
	whiff.pressed.connect(_play_combo.bind(false))
	box.add_child(whiff)

	var note := Label.new()
	note.text = GameStyle.wrap_cjk("间隔与前摇 tween 的 0.05s 同源。刃金频段 1.2k-5k，受击声占 40-500Hz，两层错开才不会糊成一片。", GameStyle.body_font(), 13, COMBO_ROW_W)
	GameStyle.label(note, 13, GameStyle.PAPER_DIM)
	box.add_child(note)
	return box

## 按定稿时序复刻近战双层：前摇破空（动作，无条件）→ 命中材质（战果）→ 受击身体声
func _play_combo(is_hit: bool) -> void:
	_burst_seq += 1
	var seq := _burst_seq
	var whoosh: Dictionary = _pick_cand(COMBO_WHOOSH_FAMILY)
	var impact: Dictionary = _pick_cand(COMBO_IMPACT_FAMILY)
	if whoosh.is_empty():
		_show("缺 whoosh_light 候选，无法组合试听")
		return
	_play_cand(whoosh, 1.0)
	_show("组合试听 · %s → %s" % [String(whoosh.get("stem", "")),
		(String(impact.get("stem", "—")) + " + enemy_hit") if is_hit else "挥空无声"])
	await get_tree().create_timer(WHIFF_GAP_MS / 1000.0).timeout
	if seq != _burst_seq:
		return
	if is_hit and not impact.is_empty():
		_play_cand(impact, IMPACT_SCALE)
		await get_tree().create_timer(HIT_LAG_MS / 1000.0).timeout
		if seq != _burst_seq:
			return
		## 第三层走正式注册 key —— 要验的就是会不会和游戏里那声受击糊成一片
		AudioManager.play_sfx("enemy_hit", 1.25, GameManager.rng.randf_range(1.08, 1.22))

func _pick_cand(family: String) -> Dictionary:
	if not _cands.has(family):
		return {}
	var set: Dictionary = _cands[family]
	var letter := String(_sel.get(family, ""))
	if letter == "" or not set.has(letter):
		letter = _first_letter(set)
	return set.get(letter, {})

func _burst_family(family: String) -> void:
	_burst_seq += 1
	var seq := _burst_seq
	var letters: Array = (_cands[family] as Dictionary).keys()
	letters.sort()
	_show("连发 %s · %s ×%d 轮（再点一次或点任一候选即中断）" % [family, " → ".join(PackedStringArray(letters)), CAND_BURST_ROUNDS])
	for r in CAND_BURST_ROUNDS:
		for letter in letters:
			if seq != _burst_seq:
				return
			var info: Dictionary = _cands[family][letter]
			_play_cand(info, 1.0)
			_sel[family] = String(letter)
			_refresh_all_labels()
			_show_cand("连发 第%d轮 %s · %s" % [r + 1, family, String(letter)], info)
			await get_tree().create_timer(CAND_BURST_GAP).timeout
	_show("连发结束 · 当前选 %s = %s" % [family, String(_sel.get(family, ""))])

func _refresh_all_labels() -> void:
	for b in _cand_buttons:
		_refresh_cand_label(b)

func _build_bgm_buttons() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(32, 150)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	add_child(grid)
	_bgm_box = grid

	for bkey in _bgm_keys:
		var btn := Button.new()
		btn.text = BGM_LABELS.get(bkey, bkey)
		btn.custom_minimum_size = Vector2(430, 42)
		GameStyle.button(btn, GameStyle.NAVY2, GameStyle.GOLD, 14, GameStyle.PAPER)
		var k: String = bkey
		btn.pressed.connect(func():
			_phase = PHASE_MANUAL
			AudioManager.play_bgm_key(k, true)
			_last_key = "BGM " + k
			_show("手动试听 BGM · " + BGM_LABELS.get(k, k))
		)
		grid.add_child(btn)

func _process(delta: float) -> void:
	if _phase == PHASE_CAND:
		return
	_timer -= delta
	if _timer > 0.0:
		return

	match _phase:
		PHASE_SFX:
			if _idx >= _keys.size():
				_phase = PHASE_BGM
				_idx = 0
				_timer = 0.2
				return
			_last_key = String(_keys[_idx])
			AudioManager.play_sfx(_last_key, 1.0, 1.0)
			_show("SFX  %d/%d  %s" % [_idx + 1, _keys.size(), _last_key])
			_idx += 1
			_timer = SFX_GAP
		PHASE_BGM:
			if _idx >= _bgm_keys.size():
				_phase = PHASE_MANUAL
				_show("全部播完 · 点按钮切 BGM / R 重听全部 / 空格 重播当前")
				return
			var key := String(_bgm_keys[_idx])
			AudioManager.play_bgm_key(key, true)
			_last_key = "BGM " + key
			_show("BGM  %d/%d  %s" % [_idx + 1, _bgm_keys.size(), BGM_LABELS.get(key, key)])
			_idx += 1
			_timer = BGM_HOLD
		_:
			_timer = 1.0

func _show(text: String) -> void:
	current.text = text
	print("[GALLERY] " + text)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.pressed:
		return
	match String(event.as_text()).to_lower():
		"esc":
			get_tree().quit()
		"r":
			_keys = AudioManager.sfx_keys()
			_keys.sort()
			_idx = 0
			_cand_box.visible = false
			_bgm_box.visible = false
			_phase = PHASE_SFX
			_timer = 0.1
		" ":
			if _last_key.begins_with("BGM"):
				var k := _last_key.replace("BGM ", "")
				AudioManager.bgm_key = &""
				AudioManager.play_bgm_key(k, true)
			elif AudioManager.has_sfx(_last_key):
				AudioManager.play_sfx(_last_key, 1.0, 1.0)
			_show("重播 · " + _last_key)
			_timer = SFX_GAP
		_:
			_pick_by_digit(String(event.as_text()))

## 数字 1..9 直听第 N 个候选（桌面快速过一遍；点按钮是同一件事，真机上只用点）
func _pick_by_digit(digit: String) -> void:
	if digit.length() != 1 or not digit.is_valid_int():
		return
	var n := digit.to_int()
	if n < 1 or n > _cand_buttons.size():
		return
	_cand_box.visible = true
	_bgm_box.visible = false
	var btn: Button = _cand_buttons[n - 1]
	_on_cand_pressed(String(btn.get_meta("family")), String(btn.get_meta("letter")))
