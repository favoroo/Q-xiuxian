extends Node2D

## 境界光环（PlayerAura）三档现场预览（非判据，2026-10-24）：真渲染排布 1/2/3 圈三档。
## 上排按实机比例摆（程序化角色 0.75 缩放 × 相机 1.1，光环不吃角色缩放、radii 17~32 世界 px），
## 下排同档整体放大 2.2 倍看细节；泛光参数照抄 Main.tscn（HDR 阈值 1.0）。
## 运行: $G --path . res://tests/AuraPreview.tscn   （必须真渲染，不加 --headless）
## 自动存 /tmp/aura_preview_full.png（呼吸峰值 t=1.0s）/ /tmp/aura_preview_trough.png（谷值 t=3.0s）
## / /tmp/aura_preview_zoom.png（圆满档 4 倍特写）后退出，纯目检不接判据。

const SHOT1_MS := 1000   ## 呼吸峰值：sin(TAU/4·t) 在 t=1.0s 达 max
const SHOT2_MS := 3000   ## 呼吸谷值：t=3.0s
const SHOT_PULSE_MS := 3200  ## 谷值拍完后现场触发一次境界突破（2 圈→3 圈）
const SHOT3_MS := 3350   ## 脉冲中段（触发后 150ms，k≈0.25 亮环扩散到一半）
const ZOOM_TIER3_POS := Vector2(800, 388)  ## 下排圆满档站位（设计分辨率坐标）
const DESIGN_W := 960.0  ## 设计宽（物理帧缓冲按比例换算裁窗）

var _t0 := 0
var _shot1 := false
var _shot2 := false
var _shot3 := false
var _shot4 := false
var _pulse_aura: PlayerAura = null  ## 中列下排光环，专供脉冲演示

func _ready() -> void:
	# 泛光参数照抄 Main.tscn 的 Environment（glow_levels/1 + intensity 0.4 + hdr_threshold 1.0）
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = GameStyle.INK
	env.glow_enabled = true
	env.set("glow_levels/1", true)
	env.glow_intensity = 0.4
	env.glow_strength = 0.7
	env.glow_bloom = 0.04
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var bg := ColorRect.new()
	bg.color = GameStyle.INK
	bg.size = Vector2(960, 540)
	add_child(bg)

	for i in 3:
		var col_x := 160.0 + 320.0 * float(i)
		_build_station(i + 1, Vector2(col_x, 128), 1.1)          # 上排：实机比例（相机 1.1）
		var aura := _build_station(i + 1, Vector2(col_x, 388), 1.1 * 2.2)  # 下排：放大 2.2 倍
		if i == 1:
			_pulse_aura = aura
	_t0 = Time.get_ticks_msec()

func _build_station(tier: int, pos: Vector2, overall: float) -> PlayerAura:
	# 站点根节点只承担相机/预览缩放；内部光环保持世界 1.0、角色 0.75，复刻 Player 内真实比例
	var station := Node2D.new()
	station.position = pos
	station.scale = Vector2(overall, overall)
	add_child(station)

	# 档位判定读全局 GameManager.level（PlayerAura._update_tier 只在 _ready 与信号时重算），
	# 逐个改档再挂，光环各自冻结在挂树那刻的档位
	GameManager.level = 1 if tier == 1 else (8 if tier == 2 else 14)
	var aura := PlayerAura.new()
	aura.position = Vector2(0, 16)
	station.add_child(aura)   # 先加光环后加角色 ⇒ 后弧垫底；前弧靠 RingFrontLayer z+1 自动压过角色
	var renderer := HollowKnightCultivatorRenderer.new(CultivatorVisualConfig.get_config("jianchi"))
	renderer.current_angle = CultivatorRendererBase.Angle.FRONT
	renderer.scale = Vector2(0.75, 0.75)
	station.add_child(renderer)
	return aura

func _process(_delta: float) -> void:
	var elapsed := Time.get_ticks_msec() - _t0
	if not _shot1 and elapsed >= SHOT1_MS:
		_shot1 = true
		_snap("/tmp/aura_preview_full.png")
	elif not _shot2 and elapsed >= SHOT2_MS:
		_shot2 = true
		_snap("/tmp/aura_preview_trough.png")
	elif not _shot3 and elapsed >= SHOT_PULSE_MS:
		# 现场触发境界突破：中列下排 2 圈 → 3 圈，放突破脉冲（静态图都拍完了才动它）
		_shot3 = true
		GameManager.level = 14
		if _pulse_aura != null:
			_pulse_aura._advance_tier()
	elif not _shot4 and elapsed >= SHOT3_MS:
		_shot4 = true
		_snap("/tmp/aura_preview_pulse.png")
	elif _shot4:
		_snap_zoom()
		print("AURA_PREVIEW_DONE")
		get_tree().quit(0)

func _snap(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("AURA_PREVIEW_SAVED ", path)

func _snap_zoom() -> void:
	var img := get_viewport().get_texture().get_image()
	var factor := img.get_width() / DESIGN_W
	# 光环世界中心 = 站位 + (0,16)×整体缩放 2.42；裁 ±95 设计 px 窗 4 倍放大
	var center := ZOOM_TIER3_POS + Vector2(0, 16.0 * 2.42)
	var half := 95.0
	var crop := Rect2i(int((center.x - half) * factor), int((center.y - half) * factor), int(half * 2.0 * factor), int(half * 2.0 * factor))
	var part := img.get_region(crop)
	part.convert(Image.FORMAT_RGBA8)
	part.resize(crop.size.x * 2, crop.size.y * 2, Image.INTERPOLATE_NEAREST)
	part.save_png("/tmp/aura_preview_zoom.png")
	print("AURA_PREVIEW_SAVED /tmp/aura_preview_zoom.png")
