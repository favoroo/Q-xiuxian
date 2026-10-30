extends Node2D

## 聚灵阵激活演出的逐帧出图台（非判据，不参与绿灯）：真链路长按充满 → 触发 → 逐帧抓拍。
## 覆盖：① 充能中的阵盘/灵气丝/升灵光柱 ② 灵兽登场 ③ 激活爆发（双环+通天光柱+闪白）
## ④ 熄灭变灰的连续形变。
## 说明：触发会召唤灵兽（2026-10-25 起不再撒金币），会挡住碑体本身；故抓完灵兽后先清场，
## 再抓「干净的」爆发与熄灭帧，纯为肉眼验收。
## 运行（不能加 --headless，headless 不渲染、get_image 拿到空图）：
##   $G --path . res://tests/ObeliskActivationPreview.tscn
## 产物 /tmp/obelisk_act_<tag>.png

const OBELISK := preload("res://scenes/entities/BlessingObelisk.tscn")
const ORIGIN := Vector2(480, 340)

var _ob: BlessingObelisk
var _t0: float = 0.0

func _ready() -> void:
	var tile: Texture2D = load("res://assets/art/courtyard_tile.png")
	var tw := int(tile.get_width())
	for y in range(0, int(540.0 / tw) + 2):
		for x in range(0, int(960.0 / tw) + 2):
			var s := Sprite2D.new()
			s.texture = tile
			s.position = Vector2(x * tw + tw / 2.0, y * tw + tw / 2.0)
			add_child(s)
	_ob = OBELISK.instantiate()
	_ob.position = ORIGIN
	add_child(_ob)
	for i in range(6):
		await get_tree().process_frame

	# ① 充能中：钉在 0.45，抓一张满是灵气丝/光柱的样子
	_ob.is_player_inside = true
	_ob.start_charge()
	_ob.is_charging = false
	_ob._set_readout_ratio(0.45)
	_ob.light.energy = 1.2 + 0.45 * 2.3
	_ob.circle_sprite.rotation = 1.1
	if _ob._charge_particles != null:
		_ob._charge_particles.emitting = true
	_ob._show_readout()
	await _wait(0.35)
	_shoot("charging")

	# ② 真实长按到满触发（2026-10-25 金币启动：先给足启动价；触发含 0.45s 金币注入）
	# 2026-10-30 首次免费档记作已消耗：本预览要拍「金铢注入」的收费档演出
	GameManager.obelisk_activations = 1
	GameManager.spirit_stones = GameBalance.obelisk_activation_cost(
		maxi(GameManager.wave_number, 1), GameManager.obelisk_activations) * 2
	_ob.is_charging = true
	var guard := 0
	while not _ob.spent_this_wave and guard < 900:
		await get_tree().process_frame
		guard += 1
	await _wait(0.05)
	_shoot("beast")   # 灵兽已现身（登场漩涡 + 灵兽本体）

	# 清场：把灵兽与金币移走，露出碑体本身来看爆发与熄灭
	_clear_summoned()

	await _until(0.10, true); _shoot("burst0")   # 闪白 + 冲击双环刚起
	await _until(0.18); _shoot("burst1")          # 光柱拔起
	await _until(0.30); _shoot("burst2")          # 光柱收束 + 环扩散
	await _until(0.46); _shoot("burst3")          # 熄灭形变前段
	await _until(0.85); _shoot("spent")           # 全灰相

	print("ACT PREVIEW done: spent_this_wave=%s light.enabled=%s spent_blend=%.2f" % [
		str(_ob.spent_this_wave), str(_ob.light.enabled),
		_ob._obelisk_renderer.spent_blend if _ob._obelisk_renderer != null else -1.0])
	get_tree().quit(0)

func _clear_summoned() -> void:
	# 灵兽是 preview 直接子节点，金币挂在 acquire_or_new 的内部 host 下 —— 递归清
	_free_type(get_tree().current_scene)

func _free_type(n: Node) -> void:
	if n == null:
		return
	for c in n.get_children():
		_free_type(c)
	if n is SpiritBeast or n is AstralGem:
		n.queue_free()

func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout

## 等到触发后的绝对时间点（以触发为 0 起算）
func _until(target: float, mark_start: bool = false) -> void:
	if mark_start:
		_t0 = Time.get_ticks_msec() / 1000.0
	var now := Time.get_ticks_msec() / 1000.0 - _t0
	if now < target:
		await _wait(target - now)

func _shoot(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	var k := float(img.get_width()) / 960.0
	var crop := Rect2(Vector2((ORIGIN.x - 230.0) * k, (ORIGIN.y - 300.0) * k), Vector2(460.0 * k, 460.0 * k))
	img = img.get_region(Rect2i(Vector2i(crop.position), Vector2i(crop.size)))
	var path := "/tmp/obelisk_act_%s.png" % tag
	img.save_png(path)
	print("SAVED ", path, " ", img.get_size())
