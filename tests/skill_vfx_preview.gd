extends Control

## tests/skill_vfx_preview.gd — 技能特效目检预览（非判据现场预览，不加 --headless）
##
## 用途：目检金光护体暖金椭球护罩 / 疾风咒脚下风轮+上升气流等五技能特效，无需进入真实战斗。
## 交互模式：按 1-5 触发技能、B 循环体型（剑痴/狂战/石岳/驯兽师，验证护罩随体型缩放）、S 加一层影、R 清除。
##
## 跑法（需要真实窗口出图，headless 下 Viewport 不出图）：
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --path . res://tests/SkillVfxPreview.tscn               # 交互目检
##   $G --path . res://tests/SkillVfxPreview.tscn -- --export   # 自动连拍导出拼条
## 导出：tests/styles/skill_vfx_strip.png（10 帧：无敌基准/狂战/驯兽师三体型 + 碎散 + 攻速/移速/冲刺/治疗 + 踏影两层与满层），
## 完成打印 SKILL_VFX_RESULT: ALL PASS 后自动退出。
##
## 几何与 Player 内一致：SkillVfx 无缩放、ProceduralCultivatorView scale=0.75，
## 外层整体再放大 2.2 倍便于目检（相对比例不变）。

const VIEW_SCALE := 0.75          ## 与 Player.gd 程序化角色实际缩放一致
const ZOOM := 2.2                 ## 预览整体放大倍率
const CELL_W := 220               ## 拼条单帧宽
const CELL_H := 300               ## 拼条单帧高

## 体型循环表：基准 1.0 / 最宽（狂战 1.54） / 厚重（石岳 1.48） / 最小（驯兽师 0.78）
const BODY_IDS: Array[String] = ["jianchi", "kuangzhan", "shiyue", "fuzhen"]

var _vfx: PlayerSkillVfx
var _view: ProceduralCultivatorView
var _body_idx := 0

func _ready() -> void:
	custom_minimum_size = Vector2(960, 540)
	size = Vector2(960, 540)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title_lbl := Label.new()
	title_lbl.text = "技能特效预览 | 1 无敌(椭球罩) · 2 攻速(风轮气流) · 3 移速 · 4 冲刺 · 5 治疗 · B 切体型 · S 加一层影 · R 清除"
	title_lbl.position = Vector2(16, 10)
	GameStyle.label(title_lbl, 13, GameStyle.PAPER, 0, GameStyle.INK, true)
	add_child(title_lbl)

	var stage := Node2D.new()
	stage.position = Vector2(480, 300)
	stage.scale = Vector2(ZOOM, ZOOM)
	add_child(stage)

	# 程序化角色视图：先 setup 后入树（与 Player.gd 挂载顺序一致，避免 _ready 依赖空 config）
	_view = ProceduralCultivatorView.new()
	_view.position = Vector2.ZERO
	_view.scale = Vector2(VIEW_SCALE, VIEW_SCALE)
	_view.setup_character_id(BODY_IDS[_body_idx])
	stage.add_child(_view)

	# 技能特效：挂在同一 stage（player 为 null，本体联动与体型系数由预览手动驱动）
	_vfx = PlayerSkillVfx.new()
	stage.add_child(_vfx)
	_sync_body_scale()

	var tree := get_tree()
	if tree == null:
		return
	if OS.get_cmdline_user_args().has("--export"):
		for i in range(5):
			await tree.process_frame
		await _run_export(tree)

## 切换角色体型并同步 SkillVfx 的体型系数（预览内 player 为 null，须手动灌入）
func _apply_body(cid: String) -> void:
	_view.setup_character_id(cid)
	_sync_body_scale()

func _sync_body_scale() -> void:
	var cfg = _view.get("config")
	if cfg == null or not ("body" in cfg):
		return
	var body: Dictionary = cfg.body
	var s := float(body.get("scale", 1.0))
	_vfx._body_scale = Vector2(s * float(body.get("width_scale", 1.0)), s * float(body.get("height_scale", 1.0)))

func _process(delta: float) -> void:
	if _vfx == null:
		return
	_vfx.update_vfx(delta, false, Vector2.ZERO)
	_sync_visuals()

## 把特效激活状态手动同步到角色本体法相（SkillVfx.player 为 null 不会自动通知）
func _sync_visuals() -> void:
	if _view == null:
		return
	_view.set_skill_visual("aegis", _vfx.aegis_active)
	_view.set_skill_visual("haste", _vfx.haste_active)
	_view.set_skill_visual("gale", _vfx.gale_active)
	_view.set_skill_visual("dash", _vfx.dash_flash_timer > 0.0)
	_view.set_skill_visual("renewal", _vfx.renewal_progress >= 0.0)

func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_1: _cast("aegis")
		KEY_2: _cast("haste")
		KEY_3: _cast("gale")
		KEY_4: _cast("dash")
		KEY_5: _cast("renewal")
		KEY_B:
			_body_idx = (_body_idx + 1) % BODY_IDS.size()
			_apply_body(BODY_IDS[_body_idx])
		KEY_S:
			# 加一层影（到顶回到 1 层，便于逐帧看读数与满层底线）
			var nxt: int = _vfx.shadow_stacks + 1
			if nxt > ShadowStepData.MAX_STACKS:
				nxt = 1
			_vfx.on_shadow_gained(nxt)
		KEY_R: _clear_all()

func _cast(id: String) -> void:
	# 时长与 SkillData.DEFS 对齐（aegis 2.0 / haste 5.0 / gale 4.0 / dash 0.16）
	match id:
		"aegis": _vfx.on_aegis_start(2.0)
		"haste": _vfx.on_haste_start(5.0)
		"gale": _vfx.on_gale_start(4.0)
		"dash": _vfx.on_dash_start(Vector2.RIGHT, 150.0, 0.16)
		"renewal": _vfx.on_renewal_cast()

func _clear_all() -> void:
	_vfx.aegis_active = false
	_vfx.aegis_shatter_progress = -1.0
	_vfx.aegis_shatter_sparks.clear()
	_vfx.haste_active = false
	_vfx.haste_sparks.clear()
	_vfx.gale_active = false
	_vfx.dash_flash_timer = 0.0
	_vfx.renewal_progress = -1.0
	_vfx.renewal_particles.clear()
	_vfx.on_shadow_spent()
	_vfx.queue_redraw()

# ---------------- 自动连拍导出 ----------------

func _run_export(tree: SceneTree) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var frames: Array[Image] = []

	# 1-3. 金光护体三体型对照（基准剑痴 / 最宽狂战 / 最小驯兽师，验证护罩随体型缩放）
	_cast("aegis")
	await tree.create_timer(0.6).timeout
	frames.append(await _snap(vp))            # 1. 基准体型稳态
	_apply_body("kuangzhan")
	await tree.create_timer(0.06).timeout
	frames.append(await _snap(vp))            # 2. 狂战（宽 1.54 倍）稳态
	_apply_body("fuzhen")
	await tree.create_timer(0.06).timeout
	frames.append(await _snap(vp))            # 3. 驯兽师（宽 0.78 倍）稳态
	# 4. 金光护体碎散中段（驯兽师体型：碎散粒子在 cast 时按当时体型生成，
	#    duration 1.6 结束后 0.05s，裂纹环与碎星并存）
	await tree.create_timer(0.92).timeout
	frames.append(await _snap(vp))
	_apply_body(BODY_IDS[_body_idx])
	_clear_all()

	# 3. 疾风咒稳态（蓝色脚下风轮 + 贴身上升气流）
	_cast("haste")
	await tree.create_timer(0.8).timeout
	frames.append(await _snap(vp))
	_clear_all()

	# 4. 神行术稳态（黄色风轮飘带，对照三色三形不撞型）
	_cast("gale")
	await tree.create_timer(0.6).timeout
	frames.append(await _snap(vp))
	_clear_all()

	# 5. 缩地成寸中段（破空剑气）
	_cast("dash")
	await tree.create_timer(0.06).timeout
	frames.append(await _snap(vp))
	_clear_all()

	# 6. 回春术中段（青莲甘露阵）
	_cast("renewal")
	await tree.create_timer(0.25).timeout
	frames.append(await _snap(vp))
	_clear_all()

	# 7-8. 踏影影层读数（2 层 / 满层）：头顶幽夜紫菱形一层就是一刀，
	#      满层换亮紫并压一条可释放底线（等弹跳回落再拍，量的是稳态读不读得清）
	for n in [2, ShadowStepData.MAX_STACKS]:
		for i in range(n):
			_vfx.on_shadow_gained(i + 1)
		await tree.create_timer(0.4).timeout
		frames.append(await _snap(vp))
	_clear_all()

	_export_strip(frames)
	print("SKILL_VFX_RESULT: ALL PASS")
	tree.quit(0)

func _snap(vp: Viewport) -> Image:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return Image.create_empty(CELL_W, CELL_H, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img

## 从各帧截出角色所在的矩形窗口拼成横向帧条导出
## 注意：viewport 纹理是物理分辨率（Retina 下为逻辑尺寸的整数倍），
## 裁剪窗口须按纹理实际宽度 / 逻辑宽度的比例换算。
func _export_strip(frames: Array[Image]) -> void:
	DirAccess.make_dir_recursive_absolute("tests/styles")
	var strip := Image.create(CELL_W * frames.size(), CELL_H, false, Image.FORMAT_RGBA8)
	for i in range(frames.size()):
		var img := frames[i]
		var factor := float(img.get_width()) / maxf(size.x, 1.0)
		var center := Vector2i(int(480.0 * factor), int(300.0 * factor))
		var src_rect := Rect2i(center.x - CELL_W / 2, center.y - CELL_H / 2, CELL_W, CELL_H)
		var clipped := src_rect.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		if clipped.size.x <= 0 or clipped.size.y <= 0:
			continue
		strip.blit_rect(img, clipped, Vector2i(i * CELL_W, 0))
	var path := "tests/styles/skill_vfx_strip.png"
	strip.save_png(path)
	print("[SkillVfxPreview] 已导出技能特效拼条(%d 帧): %s" % [frames.size(), path])
