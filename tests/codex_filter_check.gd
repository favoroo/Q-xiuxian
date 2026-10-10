extends Node

## 图鉴流派筛选判据：筛选 chip 点选后网格只留该流派武器、卡面带关键数值行、
## 深链 open_weapons_page 预选生效、再点一次取消回全量。
## 运行: $G --headless --path . res://tests/CodexFilterCheck.tscn
##
## 口径：武器归属唯一真话是 WeaponData.tags_of(id)（与商店羁绊签/羁绊结算同源），
## 期望数量从 DEFS 现数不抄死 —— 加武器或改归属后判据自动跟表。
## chip 用 viewport.push_input 打真实坐标：GameStyle.tap 的「按下-抬起原地才算点」
## 手势口径必须走引擎拾取才量得准（同 ManualHotzoneCheck 的教训）。

const VIEWPORT_SIZE := Vector2i(960, 540)

var _c := TestCheck.new()
var _manual: ManualDialog

func _ready() -> void:
	get_tree().root.size = VIEWPORT_SIZE
	Engine.time_scale = 4.0
	_manual = ManualDialog.new()
	add_child(_manual)
	_manual.open()
	await _settle(3)
	_manual.switch_tab(1)
	await _settle(2)

	# ① 全部视图：全量卡片 + 五行分组标题 + 卡面数值行
	_c.equals(_card_count(), _weapon_total(), "全部视图：卡片数 == DEFS 武器总数（%d）" % _weapon_total())
	_c.check(_group_headers() >= 5, "全部视图：五行分组标题齐全（%d 组）" % _group_headers())
	_c.check(_has_stat_line(), "卡面带关键数值行（伤·秒·金）")

	# ② 深链预选：open_weapons_page("spirit") 只剩召唤系，组标题是流派名
	_manual.open_weapons_page("spirit")
	await _settle(2)
	_c.equals(_card_count(), _tag_total("spirit"), "深链召唤：只列召唤系 %d 把" % _tag_total("spirit"))
	_c.check(_header_text().contains("召唤"), "深链召唤：组标题带流派名（%s）" % _header_text())
	_c.check(_has_stat_line(), "召唤卡面同样带数值行")

	# ③ 元素筛选：火系（用户口径「火属性这种也要能筛」）
	_manual.open_weapons_page("fire")
	await _settle(2)
	_c.equals(_card_count(), _tag_total("fire"), "深链火系：只列火属性 %d 把" % _tag_total("fire"))

	# ④ 真实点按 chip：点「金系」换组，选中态金底
	var metal_chip: Label = _manual._filter_chips.get("metal")
	_c.check(metal_chip != null and is_instance_valid(metal_chip), "筛选条上「金系」chip 找得到")
	if metal_chip != null:
		await _tap_chip(metal_chip)
		_c.equals(_card_count(), _tag_total("metal"), "点按金系 chip：网格换成金系 %d 把" % _tag_total("metal"))
		var sb := metal_chip.get_theme_stylebox("normal") as StyleBoxFlat
		_c.check(sb != null and sb.bg_color == GameStyle.GOLD, "金系 chip 选中态主蓝高亮（GOLD=主蓝历史名）")
		# ⑤ 再点一次取消，回全量（空筛选 = 全部）
		await _tap_chip(metal_chip)
		_c.equals(_card_count(), _weapon_total(), "再点金系 chip：取消筛选回全量 %d 把" % _weapon_total())

	_c.check(_manual.visible, "全程图鉴没被误关")
	get_tree().quit(0 if _c.report("CODEX_FILTER_RESULT") else 1)

# ================================ 取数 ================================

func _weapon_total() -> int:
	var n := 0
	for wid in WeaponData.DEFS.keys():
		if WeaponData.DEFS[wid].has("tags"):
			n += 1
	return n

func _tag_total(tag: String) -> int:
	var n := 0
	for wid in WeaponData.DEFS.keys():
		if tag in WeaponData.tags_of(String(wid)):
			n += 1
	return n

## 网格区里带 tip_title 的卡数（_make_entry_card 打标；重建后的旧树已 queue_free 出去）
func _card_count() -> int:
	return _collect_cards(_manual._weapons_box).size()

func _collect_cards(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	_collect(root, out)
	return out

func _collect(node: Node, out: Array[Control]) -> void:
	if node is Control and node.has_meta("tip_title"):
		out.append(node as Control)
	for ch in node.get_children():
		_collect(ch, out)

func _group_headers() -> int:
	var n := 0
	for lbl in _labels_of(_manual._weapons_box):
		if String(lbl.text).begins_with("──"):
			n += 1
	return n

## 筛选视图的组标题（「── 召唤 · 6 把 ──」）；全部视图下取到的是五行标题，仅深链用例断言
func _header_text() -> String:
	for lbl in _labels_of(_manual._weapons_box):
		if String(lbl.text).begins_with("──"):
			return String(lbl.text)
	return ""

func _has_stat_line() -> bool:
	for lbl in _labels_of(_manual._weapons_box):
		var t := String(lbl.text)
		if t.begins_with("伤") and t.contains("秒") and t.contains("金"):
			return true
	return false

func _labels_of(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	_walk_labels(root, out)
	return out

func _walk_labels(node: Node, out: Array[Label]) -> void:
	if node is Label:
		out.append(node as Label)
	for ch in node.get_children():
		_walk_labels(ch, out)

# ================================ 点按 ================================

## 真发一次按下+抬起（同一坐标）：GameStyle.tap 的划动容差口径下原地点必触发
func _tap_chip(chip_lbl: Control) -> void:
	var p := chip_lbl.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = p
		ev.global_position = p
		ev.pressed = pressed
		get_tree().root.push_input(ev)
	await _settle(2)

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
