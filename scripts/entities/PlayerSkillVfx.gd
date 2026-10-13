class_name PlayerSkillVfx
extends Node2D

## 角色随行技能视觉特效控制器与渲染器
## 负责表现角色在施放技能瞬间与增益持续期间的国风空灵修仙视觉效果：
##   1. 金光护体 (aegis): 贴合身形的暖金半透明椭球护罩（罩体填充 + 球面纬线 + 亮边高光 +
##      公转能量流光 + 呼吸脉动 + 弹出登场 + 粒子化崩解碎散）——唯一允许低透明罩体填充的技能，
##      填充 alpha 压在 0.12 以内保持通透，杜绝"死皮感"的大面积糊罩
##   2. 疾风咒 (haste): 脚下双层疾风轮 + 贴身螺旋上升气流 + 向上生腾的风丝灵气粒子
##      （不环身画法阵、不遮角色，与护罩构图彻底区分）
##   3. 神行术 (gale): 御风破空矢量身法虚影 + 脚底透视双层风轮 + 飘逸风灵飘带
##   4. 缩地成寸 (dash): 瞬身纯白剑意锋芒 + 破空剑气割裂裂痕 + 矢量残影
##   5. 回春术 (renewal): 地面九品青莲甘露阵 + 穿透升华的生机光羽与甘露灵丝
##
## 三色三形速查：无敌=暖金椭球罩 / 攻速=蓝色脚下风轮+升腾气流 / 移速=黄色脚下风轮+飘带。
## 罩体/风轮几何随角色体型插槽（config.body 的 scale×width_scale / scale×height_scale）等比缩放，
## 保证狂战（宽 1.54 倍）不穿模、驯兽师（宽 0.78 倍）不空荡；取色严格源自 GameStyle
## （暖金为 AURUM/AURUM_EDGE），其余技能维持纯线条不填充，
## 全面联动角色矢量本体（眼睛变色爆芒、斗篷流光反光、道印激活），达到主机级高精仙侠观感。

# ---------------- 常量与配置 ----------------
const BODY_CENTER := Vector2(0.0, -14.0)    ## 角色身躯中心（dash/renewal 沿用的历史基准）
const FEET_CENTER := Vector2(0.0, 14.0)     ## 角色脚底地面中心（gale/renewal 沿用的历史基准）

## 金光护体椭球护罩几何（对齐程序化角色实际身形：宽 ±12、头顶 y≈-18、脚底 y≈+24，
## 兼容跑步 hover 弹性 ±7% 后留 ~6px 余量；SkillVfx 无缩放，坐标即 Player 本地）
const SHIELD_CENTER := Vector2(0.0, 3.0)
const SHIELD_RX := 18.0
const SHIELD_RY := 28.0
const AEGIS_APPEAR_DUR := 0.16              ## 护罩弹出登场时长

## 疾风咒脚下疾风轮几何（锚定真实脚底 y≈22）
const HASTE_FEET := Vector2(0.0, 22.0)
const HASTE_WHEEL_RX := 26.0
const HASTE_WHEEL_RY := 10.0

const GHOST_POOL_CAP := 12                  ## 图集残影池上限

# ---------------- 运行时状态 ----------------
@onready var player: CharacterBody2D = get_parent() as CharacterBody2D

# 1. 金光护体状态
var aegis_active: bool = false
var aegis_timer: float = 0.0
var aegis_max_dur: float = 1.6
var aegis_rot: float = 0.0
var aegis_appear: float = 1.0  ## 罩体弹出登场进度 0→1（1 为稳态）
var aegis_shatter_progress: float = -1.0  ## >=0 时播放消散碎裂动画
var aegis_shatter_sparks: Array[Dictionary] = [] ## {pos, vel, alpha, size}

# 2. 疾风咒状态
var haste_active: bool = false
var haste_timer: float = 0.0
var haste_rot: float = 0.0
var haste_particle_timer: float = 0.0
var haste_sparks: Array[Dictionary] = []  ## {pos, vel, life, max_life}

# 3. 神行术状态
var gale_active: bool = false
var gale_timer: float = 0.0
var gale_trail_timer: float = 0.0
var gale_wind_phase: float = 0.0

# 4. 缩地成寸状态
var dash_flash_timer: float = 0.0
var dash_crit_timer: float = 0.0
var dash_total_dur: float = 0.16
var dash_dir: Vector2 = Vector2.DOWN

# 5. 回春术状态
var renewal_progress: float = -1.0  ## >=0 播放回春法阵与生机光柱 (0.0 -> 1.0)
var renewal_particles: Array[Dictionary] = []

# 6. 图集残影对象池 (Sprite2D，仅供图集模式兼容)
var _ghost_pool: Array[Sprite2D] = []

# 7. 程序化角色纯矢量流光残影队列
var _vector_ghosts: Array[Dictionary] = []

# 8. 角色体型系数（X=scale×width_scale，Y=scale×height_scale），与渲染器 total_scale 同源
var _body_scale := Vector2.ONE

# 9. 踏影（闪避攒的影层）状态
## 读数必须贴在主体上：影层是「我躲掉了几刀」，拇指正盖着技能键时那颗角标是看不见的，
## 所以角色身后要同时拖出等量的残影点——键上给数字、身上给形状，两处同一个数。
var shadow_stacks: int = 0
var _shadow_pop: float = 0.0  ## 刚攒上一层时的弹跳余量（1→0）

# 10. 药爆状态（药王：摔药罐）
var elixir_progress: float = -1.0  ## >=0 播放药爆摔碎药瓶动效 (0.0 -> 1.0)
var elixir_shards: Array[Dictionary] = [] ## 药雾飞沫与草木微粒 {pos, vel, size, is_leaf}

# 11. 天雷引动状态（雷法真君）
var thunder_flash_timer: float = 0.0
var thunder_sparks: Array[Dictionary] = []

# 12. 盾势罡气状态（守卫）
var guard_charge_ratio: float = 0.0
var guard_rot: float = 0.0
var _guard_pop: float = 0.0
var guard_burst_timer: float = 0.0

# 13. 战意气焰状态（狂战士）
var frenzy_stacks: float = 0.0
var frenzy_particle_timer: float = 0.0
var frenzy_sparks: Array[Dictionary] = []
var frenzy_burst_timer: float = 0.0

# 14. 斩灭凝神回溯状态（绝尘）
var cd_refund_timer: float = 0.0

# 15. 陷阵煞环状态（蛮兵）
var crowd_aura_alpha: float = 0.0

func _ready() -> void:
	z_index = 2  ## 略高于角色精灵
	_init_ghost_pool()
	_refresh_body_scale()

## 从程序化角色配置读取体型插槽，护罩/风轮几何按此等比缩放（图集角色保持 1:1）
func _refresh_body_scale() -> void:
	_body_scale = Vector2.ONE
	if player == null:
		return
	var pv = player.get("procedural_view")
	if pv == null:
		return
	var cfg = pv.get("config")
	if cfg == null or not ("body" in cfg):
		return
	var body: Dictionary = cfg.body
	if body.is_empty():
		return
	var s := float(body.get("scale", 1.0))
	var w := float(body.get("width_scale", 1.0))
	var h := float(body.get("height_scale", 1.0))
	_body_scale = Vector2(s * w, s * h)

func _init_ghost_pool() -> void:
	for i in range(GHOST_POOL_CAP):
		var s := Sprite2D.new()
		s.top_level = true
		s.visible = false
		s.z_index = 1
		add_child(s)
		_ghost_pool.append(s)

func _acquire_ghost() -> Sprite2D:
	for s in _ghost_pool:
		if not s.visible:
			return s
	return null

## 通知角色本体视图联动更新法相与流光状态
func _notify_procedural_view(skill_id: String, active: bool, intensity: float = 1.0) -> void:
	if player == null:
		return
	if player.get("is_procedural") and player.get("procedural_view") != null:
		var pv = player.procedural_view
		if pv.has_method("set_skill_visual"):
			pv.set_skill_visual(skill_id, active, intensity)

# ---------------- 技能触发入口 ----------------

## 缩地成寸瞬间释放
func on_dash_start(direction: Vector2, distance: float, duration: float, crit_window: float = 1.0) -> void:
	dash_dir = direction.normalized()
	dash_total_dur = maxf(duration, 0.05)
	dash_flash_timer = dash_total_dur + 0.10
	dash_crit_timer = maxf(crit_window, dash_flash_timer)
	_notify_procedural_view("dash", true, 1.0)
	# 生成瞬身残影
	spawn_ghost(Color(GameStyle.GOLD_EDGE, 0.85), 0.28)
	queue_redraw()

## 神行术激活
func on_gale_start(duration: float) -> void:
	gale_active = true
	gale_timer = duration
	gale_trail_timer = 0.0
	_notify_procedural_view("gale", true, 1.0)
	spawn_ghost(Color(GameStyle.JADE_EDGE, 0.75), 0.25)
	queue_redraw()

## 疾风咒激活
func on_haste_start(duration: float) -> void:
	_refresh_body_scale()
	haste_active = true
	haste_timer = duration
	haste_rot = 0.0
	haste_particle_timer = 0.0
	_notify_procedural_view("haste", true, 1.0)
	queue_redraw()

## 金光护体激活
func on_aegis_start(duration: float) -> void:
	_refresh_body_scale()
	aegis_active = true
	aegis_max_dur = duration
	aegis_timer = duration
	aegis_rot = 0.0
	aegis_appear = 0.0
	aegis_shatter_progress = -1.0
	aegis_shatter_sparks.clear()
	_notify_procedural_view("aegis", true, 1.0)
	queue_redraw()

## 回春术施放
func on_renewal_cast() -> void:
	renewal_progress = 0.0
	renewal_particles.clear()
	_notify_procedural_view("renewal", true, 1.0)
	for i in range(16):
		var ang := float(i) * (TAU / 16.0)
		renewal_particles.append({
			"ang": ang,
			"radius": randf_range(14.0, 36.0),
			"y": randf_range(10.0, 24.0),
			"speed_y": randf_range(110.0, 160.0),
			"rot_speed": randf_range(3.2, 5.8),
			"size": randf_range(1.5, 3.0)
		})
	queue_redraw()

## 踏影：闪避成功攒下一层影（层数由 Player 持有，这里只跟着画，不另存一份账）
func on_shadow_gained(stacks: int) -> void:
	shadow_stacks = stacks
	_shadow_pop = 1.0
	queue_redraw()

## 踏影落地兑现后清空（Player.shadow_ring 已空，读数跟着归零）
func on_shadow_spent() -> void:
	shadow_stacks = 0
	_shadow_pop = 0.0
	queue_redraw()

## 药爆施放（摔碎药罐：自身回血甘霖 + 毒雾飞沫四溅）
func on_elixir_cast() -> void:
	elixir_progress = 0.0
	elixir_shards.clear()
	_notify_procedural_view("renewal", true, 1.0)
	for i in range(16):
		var ang := float(i) * (TAU / 16.0) + randf_range(-0.18, 0.18)
		var spd := randf_range(90.0, 180.0)
		elixir_shards.append({
			"pos": FEET_CENTER,
			"vel": Vector2(cos(ang) * spd, sin(ang) * (spd * 0.72)),
			"size": randf_range(1.8, 3.4),
			"is_leaf": (i % 2 == 0),
		})
	queue_redraw()

## 天雷引动（雷法真君）：周身电芒激荡 + 法相爆闪
func on_thunder_cast() -> void:
	_refresh_body_scale()
	thunder_flash_timer = 0.28
	_notify_procedural_view("thunder", true, 1.0)
	thunder_sparks.clear()
	for i in range(6):
		var ang := randf() * TAU
		var spd := randf_range(35.0, 80.0)
		thunder_sparks.append({
			"pos": BODY_CENTER * _body_scale.y + Vector2(cos(ang) * 10.0, sin(ang) * 10.0),
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd),
			"life": randf_range(0.12, 0.24),
			"max_life": 0.24,
		})
	queue_redraw()

## 盾势受击蓄能更新（守卫）：玄金护体残弧渐显
func on_guard_charge_updated(charge: float, max_charge: float) -> void:
	_refresh_body_scale()
	guard_charge_ratio = clampf(charge / maxf(1.0, max_charge), 0.0, 1.0)
	_guard_pop = 1.0
	_notify_procedural_view("guard", guard_charge_ratio > 0.0, guard_charge_ratio)
	queue_redraw()

## 盾势蓄满爆发（守卫）：罡气炸开
func on_guard_burst() -> void:
	guard_charge_ratio = 0.0
	guard_burst_timer = 0.24
	_notify_procedural_view("guard", false)
	queue_redraw()

## 同步狂战士战意层数
func sync_frenzy(stacks: float, max_stacks: float) -> void:
	var prev := frenzy_stacks
	frenzy_stacks = maxf(0.0, stacks)
	var ratio := clampf(frenzy_stacks / maxf(1.0, max_stacks), 0.0, 1.0)
	if frenzy_stacks > 0.0:
		_notify_procedural_view("frenzy", true, clampf(ratio * 1.2, 0.35, 1.0))
	elif prev > 0.0:
		_notify_procedural_view("frenzy", false)

## 狂战士战意满层爆气
func on_frenzy_max_burst() -> void:
	frenzy_burst_timer = 0.28
	queue_redraw()

## 斩灭凝神返还技能冷却（绝尘）
func on_cd_refunded() -> void:
	cd_refund_timer = 0.24
	queue_redraw()

# ---------------- 每帧逻辑更新 ----------------

func update_vfx(delta: float, is_moving: bool, velocity: Vector2) -> void:
	var needs_redraw := false

	# 1. 图集残影生命周期淡出
	for s in _ghost_pool:
		if s.visible:
			var life: float = float(s.get_meta(&"life", 0.0)) - delta
			var max_l: float = float(s.get_meta(&"max_life", 0.2))
			if life <= 0.0:
				s.visible = false
			else:
				s.set_meta(&"life", life)
				var base_col: Color = s.get_meta(&"base_color", Color.WHITE)
				var ratio := clampf(life / max_l, 0.0, 1.0)
				s.modulate.a = base_col.a * ratio

	# 2. 程序化角色纯矢量流光虚影更新
	if not _vector_ghosts.is_empty():
		needs_redraw = true
		var vi := _vector_ghosts.size() - 1
		while vi >= 0:
			var vg: Dictionary = _vector_ghosts[vi]
			vg["life"] = float(vg["life"]) - delta
			if float(vg["life"]) <= 0.0:
				_vector_ghosts.remove_at(vi)
			vi -= 1

	# 3. 金光护体
	if aegis_active:
		needs_redraw = true
		aegis_rot += delta * 2.5
		if aegis_appear < 1.0:
			aegis_appear = minf(1.0, aegis_appear + delta / AEGIS_APPEAR_DUR)
		aegis_timer -= delta
		if aegis_timer <= 0.0:
			aegis_active = false
			aegis_shatter_progress = 0.0  ## 启动消散碎裂动效
			_notify_procedural_view("aegis", false)
			# 生成崩散碎星粒子（从护罩轮廓向四周迸散，随体型缩放）
			aegis_shatter_sparks.clear()
			var bs := _body_scale
			for i in range(12):
				var a := float(i) * (TAU / 12.0) + randf_range(-0.15, 0.15)
				var spd := randf_range(75.0, 140.0)
				aegis_shatter_sparks.append({
					"pos": Vector2(SHIELD_CENTER.x, SHIELD_CENTER.y * bs.y) + Vector2(cos(a) * SHIELD_RX * bs.x, sin(a) * SHIELD_RY * bs.y),
					"vel": Vector2(cos(a) * spd, sin(a) * spd * 0.8),
					"size": randf_range(2.0, 3.8)
				})
	elif aegis_shatter_progress >= 0.0:
		needs_redraw = true
		aegis_shatter_progress += delta * 4.2  ## 约 0.24 秒碎散淡出
		for spk in aegis_shatter_sparks:
			spk["pos"] = Vector2(spk["pos"]) + Vector2(spk["vel"]) * delta
			spk["vel"] = Vector2(spk["vel"]) * 0.92
		if aegis_shatter_progress >= 1.0:
			aegis_shatter_progress = -1.0
			aegis_shatter_sparks.clear()

	# 4. 疾风咒
	if haste_active:
		needs_redraw = true
		haste_rot += delta * 7.8
		haste_timer -= delta
		if haste_timer <= 0.0:
			haste_active = false
			haste_sparks.clear()
			_notify_procedural_view("haste", false)
		else:
			# 周期性散逸微风刃灵气（贴身窄幅随体型，随气流升腾）
			haste_particle_timer -= delta
			if haste_particle_timer <= 0.0:
				haste_particle_timer = 0.05
				if haste_sparks.size() < 16:
					var p_ang := randf() * TAU
					var spawn_y := randf_range(-34.0, 16.0) * _body_scale.y
					var spawn_x := cos(p_ang) * randf_range(5.0, 15.0) * _body_scale.x
					haste_sparks.append({
						"pos": Vector2(spawn_x, spawn_y),
						"vel": Vector2(randf_range(-12.0, 12.0), randf_range(-80.0, -140.0)),
						"life": 0.30,
						"max_life": 0.30,
					})

	# 更新疾风咒飞散微粒子
	if not haste_sparks.is_empty():
		needs_redraw = true
		var i := haste_sparks.size() - 1
		while i >= 0:
			var sp: Dictionary = haste_sparks[i]
			sp["life"] = float(sp["life"]) - delta
			if float(sp["life"]) <= 0.0:
				haste_sparks.remove_at(i)
			else:
				sp["pos"] = Vector2(sp["pos"]) + Vector2(sp["vel"]) * delta
			i -= 1

	# 5. 神行术
	if gale_active:
		needs_redraw = true
		gale_wind_phase += delta * 12.0
		gale_timer -= delta
		if gale_timer <= 0.0:
			gale_active = false
			_notify_procedural_view("gale", false)
		else:
			# 移动中产生残影
			if is_moving and velocity.length_squared() > 1600.0:
				gale_trail_timer -= delta
				if gale_trail_timer <= 0.0:
					gale_trail_timer = 0.08
					spawn_ghost(Color(GameStyle.JADE_EDGE, 0.55), 0.22)

	# 6. 缩地成寸
	if dash_flash_timer > 0.0:
		needs_redraw = true
		dash_flash_timer -= delta
		if is_moving and fmod(dash_flash_timer, 0.04) < delta:
			spawn_ghost(Color(GameStyle.GOLD_EDGE, 0.65), 0.20)
	if dash_crit_timer > 0.0:
		dash_crit_timer -= delta
		if dash_crit_timer <= 0.0:
			_notify_procedural_view("dash", false)

	# 7. 回春术
	if renewal_progress >= 0.0:
		needs_redraw = true
		renewal_progress += delta * 1.7  ## 约 0.58s 走完
		for p in renewal_particles:
			p["y"] = float(p["y"]) - float(p["speed_y"]) * delta
			p["ang"] = float(p["ang"]) + float(p["rot_speed"]) * delta
		if renewal_progress >= 1.0:
			renewal_progress = -1.0
			renewal_particles.clear()
			_notify_procedural_view("renewal", false)

	# 8. 踏影影层：只在「刚攒上一层」的弹跳期重画，稳态靠 on_shadow_gained 那一次 queue_redraw
	if _shadow_pop > 0.0:
		needs_redraw = true
		_shadow_pop = maxf(0.0, _shadow_pop - delta * 5.0)

	# 9. 药爆动效更新（摔药罐四溅飞沫与药雾）
	if elixir_progress >= 0.0:
		needs_redraw = true
		elixir_progress += delta * 2.2  ## 约 0.45s 走完
		for s in elixir_shards:
			s["pos"] = Vector2(s["pos"]) + Vector2(s["vel"]) * delta
			s["vel"] = Vector2(s["vel"]) * 0.90
		if elixir_progress >= 1.0:
			elixir_progress = -1.0
			elixir_shards.clear()
			_notify_procedural_view("renewal", false)

	# 10. 天雷引动电芒（雷法真君）
	if thunder_flash_timer > 0.0:
		needs_redraw = true
		thunder_flash_timer -= delta
		if thunder_flash_timer <= 0.0:
			_notify_procedural_view("thunder", false)
			thunder_sparks.clear()
		else:
			var ti := thunder_sparks.size() - 1
			while ti >= 0:
				var tsp: Dictionary = thunder_sparks[ti]
				tsp["life"] = float(tsp["life"]) - delta
				if float(tsp["life"]) <= 0.0:
					thunder_sparks.remove_at(ti)
				else:
					tsp["pos"] = Vector2(tsp["pos"]) + Vector2(tsp["vel"]) * delta
				ti -= 1

	# 11. 盾势罡气更新（守卫）
	if guard_charge_ratio > 0.0:
		needs_redraw = true
		guard_rot += delta * (1.6 + guard_charge_ratio * 2.2)
		if _guard_pop > 0.0:
			_guard_pop = maxf(0.0, _guard_pop - delta * 4.5)
	if guard_burst_timer > 0.0:
		needs_redraw = true
		guard_burst_timer -= delta

	# 12. 战意气焰与煞火微粒（狂战士）
	if frenzy_stacks > 0.0:
		needs_redraw = true
		frenzy_particle_timer -= delta
		if frenzy_particle_timer <= 0.0:
			var spawn_interval := lerpf(0.12, 0.035, clampf(frenzy_stacks / 20.0, 0.0, 1.0))
			frenzy_particle_timer = spawn_interval
			var max_particles := int(lerpf(4.0, 18.0, clampf(frenzy_stacks / 20.0, 0.0, 1.0)))
			if frenzy_sparks.size() < max_particles:
				var p_x := randf_range(-14.0, 14.0) * _body_scale.x
				var p_y := (FEET_CENTER.y + randf_range(-6.0, 4.0)) * _body_scale.y
				var spd_y := randf_range(-50.0, -110.0)
				frenzy_sparks.append({
					"pos": Vector2(p_x, p_y),
					"vel": Vector2(randf_range(-10.0, 10.0), spd_y),
					"life": randf_range(0.22, 0.38),
					"max_life": 0.35,
					"size": randf_range(1.6, 3.2),
				})
	if not frenzy_sparks.is_empty():
		needs_redraw = true
		var fi := frenzy_sparks.size() - 1
		while fi >= 0:
			var fsp: Dictionary = frenzy_sparks[fi]
			fsp["life"] = float(fsp["life"]) - delta
			if float(fsp["life"]) <= 0.0:
				frenzy_sparks.remove_at(fi)
			else:
				fsp["pos"] = Vector2(fsp["pos"]) + Vector2(fsp["vel"]) * delta
				fsp["vel"] = Vector2(fsp["vel"]) * 0.94
			fi -= 1
	if frenzy_burst_timer > 0.0:
		needs_redraw = true
		frenzy_burst_timer -= delta

	# 13. 斩灭凝神回溯光丝（绝尘）
	if cd_refund_timer > 0.0:
		needs_redraw = true
		cd_refund_timer -= delta

	# 14. 陷阵煞环平滑淡入淡出（蛮兵）
	var target_crowd_alpha := 0.0
	if GameManager.crowd_damage_radius > 0.0 and GameManager.nearby_enemy_count >= 2:
		target_crowd_alpha = clampf(float(GameManager.nearby_enemy_count) / 10.0, 0.25, 0.85)
	if not is_equal_approx(crowd_aura_alpha, target_crowd_alpha):
		crowd_aura_alpha = move_toward(crowd_aura_alpha, target_crowd_alpha, delta * 3.0)
		needs_redraw = true
	elif crowd_aura_alpha > 0.0:
		needs_redraw = true

	if needs_redraw:
		queue_redraw()

## 生成一具角色当前帧的身法残影
func spawn_ghost(color: Color, duration: float) -> void:
	if player == null:
		return

	# 若为程序化角色：生成纯矢量修仙流光虚影，绝不使用图集！
	if player.get("is_procedural"):
		if _vector_ghosts.size() < 16:
			var facing_str: String = "s"
			var is_flip: bool = false
			var pv = player.get("procedural_view")
			if pv != null:
				facing_str = pv.facing
				is_flip = pv.flip_h
			_vector_ghosts.append({
				"pos": player.global_position,
				"facing": facing_str,
				"flip_h": is_flip,
				"color": color,
				"life": duration,
				"max_life": duration
			})
		return

	# 若为图集角色：从 AnimatedSprite2D 获取帧
	var sprite: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return

	var anim := sprite.animation
	if not sprite.sprite_frames.has_animation(anim):
		return
	var frame_idx := sprite.frame
	var frame_count := sprite.sprite_frames.get_frame_count(anim)
	if frame_count <= 0:
		return
	var tex := sprite.sprite_frames.get_frame_texture(anim, frame_idx % frame_count)
	if tex == null:
		return

	var ghost := _acquire_ghost()
	if ghost == null:
		return

	ghost.texture = tex
	ghost.offset = sprite.offset
	ghost.flip_h = sprite.flip_h
	ghost.scale = sprite.global_scale
	ghost.rotation = sprite.global_rotation
	ghost.global_position = sprite.global_position
	ghost.modulate = color
	ghost.set_meta(&"base_color", color)
	ghost.set_meta(&"life", duration)
	ghost.set_meta(&"max_life", duration)
	ghost.visible = true

# ---------------- 动态图形绘制 ----------------

func _draw() -> void:
	# 绘制层级：相对于 Player 中心 (0, 0)

	# 0. 程序化角色纯矢量流光虚影（最底层）
	if not _vector_ghosts.is_empty():
		_draw_vector_ghosts()

	# 1. 疾风咒：环身风刃切线与八卦疾风大阵（无任何大半透蒙皮填充）
	if haste_active:
		_draw_haste_fx()

	# 2. 神行术：踝部风旋微弧与御风流带
	if gale_active:
		_draw_gale_wind()

	# 3. 缩地成寸：前方破空剑气割裂裂痕
	if dash_flash_timer > 0.0:
		_draw_dash_cone()

	# 4. 金光护体：浑天星轨金线 + 六合天罡法印（无任何多边形填色死皮）
	if aegis_active or aegis_shatter_progress >= 0.0:
		_draw_aegis_shield()

	# 5. 回春术：九品青莲生机甘露阵与生机光羽
	if renewal_progress >= 0.0:
		_draw_renewal_fx()

	# 6. 药爆：摔碎药罐的地面药液波纹、四散飞沫与升华药气
	if elixir_progress >= 0.0:
		_draw_elixir_fx()
	# 7. 陷阵煞环（蛮兵）：脚底破阵刻印
	if crowd_aura_alpha > 0.0:
		_draw_crowd_aura_fx()

	# 8. 战意气焰（狂战士）：血煞腾空火星与战圈
	if frenzy_stacks > 0.0 or frenzy_burst_timer > 0.0:
		_draw_frenzy_fx()

	# 9. 盾势罡气（守卫）：玄金护体残弧
	if guard_charge_ratio > 0.0 or guard_burst_timer > 0.0:
		_draw_guard_stance_fx()

	# 10. 天雷引动（雷法真君）：周身雷弧火花
	if thunder_flash_timer > 0.0:
		_draw_thunder_sparks()

	# 11. 斩灭凝神（绝尘）：剑意返照十字星光
	if cd_refund_timer > 0.0:
		_draw_cd_refund_fx()

	# 12. 踏影影层读数（最后画：它是给人数的数，不许被任何特效压住）
	if shadow_stacks > 0:
		_draw_shadow_pips()

## 绘制【踏影】影层读数：头顶一排幽夜紫菱形，一层就是一刀，攒满换成亮紫并压一条可释放底线。
## 为什么画头顶而不是身后：身后那条已经被 dash/gale 的流光残影占用，同处叠两套形状数不出层数。
func _draw_shadow_pips() -> void:
	var n := shadow_stacks
	if n <= 0:
		return
	var full := n >= ShadowStepData.MAX_STACKS
	# 抬高到耳尖之上：影者是狐耳/角类头饰，读数压在耳朵上就半遮半掩（看不见等于没做）
	var top_y := -38.0 * _body_scale.y
	# 上限提到 8 层后行宽按 7px 间距会横出耳外，层数多时收窄间距保住「一排读得清」
	var gap := 7.0 if n <= 5 else 5.5
	var start_x := -gap * float(n - 1) * 0.5
	var col := GameStyle.SHADOW_EDGE if full else GameStyle.SHADOW
	for i in range(n):
		var c := Vector2(start_x + float(i) * gap, top_y)
		# 刚攒上的那一层弹一下（证明"这一刀收到了"），其余层稳态不动
		var r := 3.0 * (1.0 + _shadow_pop * 0.35 if i == n - 1 else 1.0)
		var pts := PackedVector2Array([
			c + Vector2(0.0, -r), c + Vector2(r * 0.72, 0.0), c + Vector2(0.0, r), c + Vector2(-r * 0.72, 0.0)])
		var alpha := 0.55 + 0.45 * float(i) / maxf(1.0, float(n - 1))
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, alpha))
		pts.append(pts[0])
		draw_polyline(pts, Color(GameStyle.CHALK.r, GameStyle.CHALK.g, GameStyle.CHALK.b, 0.32), 1.0)
	if full:
		# 满层底线画在行的上方：往下压会横穿耳尖，把读数切成两截
		draw_line(Vector2(start_x - gap * 0.6, top_y - 7.0),
			Vector2(start_x + gap * float(n - 1) + gap * 0.6, top_y - 7.0), GameStyle.SHADOW_EDGE, 1.6)

## 绘制程序化修仙角色的纯矢量流光身法虚影（彻底解决老版蓝衫小人残影 Bug）
func _draw_vector_ghosts() -> void:
	for g in _vector_ghosts:
		var life: float = float(g["life"])
		var max_l: float = float(g["max_life"])
		var ratio := clampf(life / max_l, 0.0, 1.0)
		var col: Color = g["color"]
		var alpha := col.a * ratio * 0.72
		if alpha <= 0.01:
			continue

		var rel_pos: Vector2 = Vector2(g["pos"]) - player.global_position
		var flip: float = -1.0 if bool(g["flip_h"]) else 1.0

		# 绘制流光身形剪影：头部面具轮廓 + 飘逸斗篷下摆
		var head_c := rel_pos + Vector2(0.0, -15.0)
		draw_circle(head_c, 8.5, Color(col.r, col.g, col.b, alpha * 0.45))
		draw_arc(head_c, 8.5, 0, TAU, 16, Color(1.0, 1.0, 1.0, alpha * 0.75), 1.0, true)

		# 飘逸斗篷轮廓
		var cloak_pts := PackedVector2Array([
			rel_pos + Vector2(0.0, -6.0),
			rel_pos + Vector2(10.0 * flip, -1.0),
			rel_pos + Vector2(13.0 * flip, 14.0),
			rel_pos + Vector2(11.0 * flip, 26.0),
			rel_pos + Vector2(0.0, 28.0),
			rel_pos + Vector2(-11.0 * flip, 26.0),
			rel_pos + Vector2(-13.0 * flip, 14.0),
			rel_pos + Vector2(-10.0 * flip, -1.0)
		])
		draw_colored_polygon(cloak_pts, Color(col.r, col.g, col.b, alpha * 0.40))
		draw_polyline(cloak_pts, Color(1.0, 1.0, 1.0, alpha * 0.85), 1.2, true)

## 绘制【疾风咒】：脚下双层疾风轮 + 贴身螺旋上升气流 + 升腾风丝
## （不环身画法阵、不遮角色，与金光护体的椭球罩构图彻底区分）
func _draw_haste_fx() -> void:
	var col_main := Color(GameStyle.GOLD, 0.82)       # 主蓝
	var col_edge := Color(GameStyle.GOLD_EDGE, 0.95)  # 霜华亮蓝
	# 几何随角色体型插槽缩放（脚底锚点随身高、轮径/摆幅随体宽）
	var bs := _body_scale
	var feet := Vector2(0.0, HASTE_FEET.y * bs.y)

	# 1. 脚下疾风轮：外层两段对置弧 + 内层一段弧，反向快转，轮缘纯白锋点
	for i in range(2):
		var wheel_rx := (HASTE_WHEEL_RX - float(i) * 9.0) * bs.x
		var wheel_ry := (HASTE_WHEEL_RY - float(i) * 3.5) * bs.x
		var spin := haste_rot * (1.0 + float(i) * 0.45)
		var base_a := -spin if i == 1 else spin
		var seg_count := 2 if i == 0 else 1
		for seg in range(seg_count):
			var pts := PackedVector2Array()
			var steps := 12
			var span := 1.75
			var a0 := base_a + float(seg) * PI
			for s in range(steps + 1):
				var a := a0 + span * (float(s) / float(steps))
				pts.append(feet + Vector2(cos(a) * wheel_rx, sin(a) * wheel_ry))
			draw_polyline(pts, col_edge, 2.0 if i == 0 else 1.4, true)
			# 轮端纯白破空锋点
			draw_circle(pts[steps], 2.2 if i == 0 else 1.6, Color.WHITE)

	# 轮心贴地加速微弧（扁弧快转，蓄势感）
	var hub_a := haste_rot * 2.2
	var hub_pts := PackedVector2Array()
	for s in range(9):
		var a := hub_a + 1.5 * (float(s) / 8.0)
		hub_pts.append(feet + Vector2(cos(a) * 11.0 * bs.x, sin(a) * 4.0 * bs.x))
	draw_polyline(hub_pts, col_main, 1.3, true)

	# 2. 贴身螺旋上升气流：3 条相位差 TAU/3 的流线从脚底绕升到头顶上方，逐段渐隐
	var steps_c := 12
	for i in range(3):
		var phase := haste_rot * 1.5 + float(i) * (TAU / 3.0)
		var prev_p := Vector2.ZERO
		for s in range(steps_c + 1):
			var t := float(s) / float(steps_c)
			var y := lerpf(20.0 * bs.y, -34.0 * bs.y, t)
			var wob := sin(phase + t * 4.6)
			var p := Vector2(wob * (17.0 * (1.0 - t * 0.5) * bs.x), y)
			if s > 0:
				var seg_a := (1.0 - t) * 0.62 + 0.08
				draw_line(prev_p, p, Color(col_main.r, col_main.g, col_main.b, seg_a), 1.8, true)
			prev_p = p
		# 流线顶端逸散微光
		draw_circle(prev_p, 1.5, Color(1, 1, 1, 0.55))

	# 3. 向上飞升的蓝色风刃光丝（Sparks）
	for sp in haste_sparks:
		var ratio := clampf(float(sp["life"]) / float(sp["max_life"]), 0.0, 1.0)
		var p_col := Color(GameStyle.GOLD_EDGE.r, GameStyle.GOLD_EDGE.g, GameStyle.GOLD_EDGE.b, ratio * 0.95)
		var p_pos := Vector2(sp["pos"])
		var p_tail := p_pos - Vector2(sp["vel"]).normalized() * (10.0 * ratio)
		draw_line(p_tail, p_pos, p_col, 2.0, true)
		draw_circle(p_pos, 1.2, Color(1, 1, 1, ratio * 0.9))

## 绘制【神行术】：脚底御风双层青轮 + 身侧破风流光飘带
func _draw_gale_wind() -> void:
	var wave := sin(gale_wind_phase) * 2.2
	var col_edge := Color(GameStyle.JADE_EDGE, 0.92)
	var col_main := Color(GameStyle.JADE, 0.75)

	# 1. 脚底御风大青轮（透视双层风环与破风角标）
	var wheel_rx := 32.0
	var wheel_ry := 13.0
	for i in range(2):
		var base_a := gale_wind_phase * 0.8 + float(i) * PI
		var pts := PackedVector2Array()
		for s in range(11):
			var a := base_a + 1.8 * (float(s) / 10.0)
			pts.append(FEET_CENTER + Vector2(cos(a) * wheel_rx, sin(a) * wheel_ry))
		draw_polyline(pts, col_edge, 2.2, true)
		# 轮端纯白破空锋点
		draw_circle(pts[pts.size() - 1], 2.2, Color.WHITE)

	# 内层风轮
	draw_arc(FEET_CENTER, 18.0, -gale_wind_phase, -gale_wind_phase + PI * 1.2, 16, col_main, 1.4, true)

	# 2. 身躯两侧上升的灵动青风流带（轻柔飘逸曲线，告别生硬粗折线）
	for side_val in [-1.0, 1.0]:
		var side: float = float(side_val)
		var ribbon := PackedVector2Array()
		for s in range(10):
			var t := float(s) / 9.0
			var y := lerpf(16.0, -36.0, t)
			var x: float = side * (24.0 + sin(gale_wind_phase * 0.8 + t * PI * 2.2) * 4.5)
			ribbon.append(Vector2(x, y))
		draw_polyline(ribbon, Color(col_main.r, col_main.g, col_main.b, 0.65), 1.8, true)
		# 飘带尖端流萤微光
		draw_circle(ribbon[ribbon.size() - 1], 1.5, Color(1, 1, 1, 0.85))

## 绘制【缩地成寸】：破空剑气割裂裂痕（纯正仙侠剑步破空感，彻底剔除实心填色大三角锥）
func _draw_dash_cone() -> void:
	var cone_dir := dash_dir
	var ratio := clampf(dash_flash_timer / (dash_total_dur + 0.10), 0.0, 1.0)
	var col_outer := Color(GameStyle.GOLD_EDGE.r, GameStyle.GOLD_EDGE.g, GameStyle.GOLD_EDGE.b, ratio * 0.95)
	var col_core := Color(1.0, 1.0, 1.0, ratio * 0.98)

	# 1. 中心主破障剑芒裂痕
	var tip := BODY_CENTER + cone_dir * (52.0 * ratio)
	var base_origin := BODY_CENTER - cone_dir * 12.0
	draw_line(base_origin, tip, col_outer, 3.2, true)
	draw_line(base_origin + cone_dir * 8.0, tip, col_core, 1.6, true)
	draw_circle(tip, 3.2, Color.WHITE)

	# 2. 左右两翼破空折线剑气（锐利破障）
	var spread_ang := deg_to_rad(32.0)
	var l_dir := cone_dir.rotated(spread_ang)
	var r_dir := cone_dir.rotated(-spread_ang)
	var l_wing_tip := BODY_CENTER + l_dir * (42.0 * ratio)
	var r_wing_tip := BODY_CENTER + r_dir * (42.0 * ratio)

	var l_pts := PackedVector2Array([
		BODY_CENTER,
		BODY_CENTER + l_dir * (24.0 * ratio) + cone_dir * 6.0,
		l_wing_tip
	])
	var r_pts := PackedVector2Array([
		BODY_CENTER,
		BODY_CENTER + r_dir * (24.0 * ratio) + cone_dir * 6.0,
		r_wing_tip
	])
	draw_polyline(l_pts, col_outer, 2.2, true)
	draw_polyline(r_pts, col_outer, 2.2, true)
	draw_polyline(l_pts, col_core, 1.2, true)
	draw_polyline(r_pts, col_core, 1.2, true)

	# 3. 破障碎刃星点
	for i in range(4):
		var spark_p := BODY_CENTER + cone_dir * (15.0 + float(i) * 9.0) + Vector2(-cone_dir.y, cone_dir.x) * (float(i % 2 * 2 - 1) * 8.0)
		draw_circle(spark_p, 1.6 * ratio, Color.WHITE)

## 绘制【金光护体】：暖金半透明椭球护罩（贴合身形，覆盖头顶到脚底）
## 唯一允许克制罩体填充的技能（填充 alpha ≤ 0.12 保持通透）：
## 罩体填充 + 球面纬线 + 双层亮边 + 左上高光 + 公转能量流光 + 脚底落地光晕；到期粒子化崩解碎散
func _draw_aegis_shield() -> void:
	var pulse := sin(aegis_rot * 2.5) * 1.2
	var rx := SHIELD_RX + pulse
	var ry := SHIELD_RY + pulse

	if aegis_active:
		# 登场弹出（back-out 过冲回弹）+ 淡入
		var pop := lerpf(0.55, 1.0, _back_out(clampf(aegis_appear, 0.0, 1.0)))
		var fade := clampf(aegis_appear * 1.4, 0.0, 1.0)
		# 呼吸脉动（微幅缩放，罩体活着的感觉）；几何随角色体型插槽缩放
		var breathe := 1.0 + sin(aegis_rot * 1.7) * 0.018
		var s_rx := rx * pop * breathe * _body_scale.x
		var s_ry := ry * pop * breathe * _body_scale.y
		var c := Vector2(SHIELD_CENTER.x, SHIELD_CENTER.y * _body_scale.y)

		var col_edge := GameStyle.AURUM_EDGE   # 暖金亮边
		var col_main := GameStyle.AURUM        # 暖金主色

		# 1. 罩体半透明填充（极低 alpha，通透不糊人）
		var body_pts := PackedVector2Array()
		for i in range(33):
			var a := float(i) * (TAU / 32.0)
			body_pts.append(c + Vector2(cos(a) * s_rx, sin(a) * s_ry))
		draw_colored_polygon(body_pts, Color(col_main.r, col_main.g, col_main.b, 0.10 * fade))

		# 2. 球面纬线（3 条按椭球截面收窄的透视扁弧，撑起立体罩感）
		for k in range(3):
			var t := -0.42 + float(k) * 0.42
			var ly := c.y + t * s_ry
			var lw := s_rx * sqrt(maxf(0.04, 1.0 - t * t))
			var lat_pts := PackedVector2Array()
			for i in range(25):
				var a := float(i) * (TAU / 24.0)
				lat_pts.append(Vector2(c.x + cos(a) * lw, ly + sin(a) * s_ry * 0.20))
			draw_polyline(lat_pts, Color(col_main.r, col_main.g, col_main.b, 0.20 * fade), 1.0, true)

		# 3. 双层亮边：外圈暖金主描边 + 内衬白细线（能量壁质感）
		var rim_pts := PackedVector2Array()
		var rim_in_pts := PackedVector2Array()
		for i in range(33):
			var a := float(i) * (TAU / 32.0)
			rim_pts.append(c + Vector2(cos(a) * s_rx, sin(a) * s_ry))
			rim_in_pts.append(c + Vector2(cos(a) * (s_rx - 1.6), sin(a) * (s_ry - 1.6)))
		draw_polyline(rim_pts, Color(col_edge.r, col_edge.g, col_edge.b, 0.95 * fade), 2.2, true)
		draw_polyline(rim_in_pts, Color(1.0, 1.0, 1.0, 0.38 * fade), 1.0, true)

		# 4. 左上高光弧（光源反射，强化球体受光）
		var hl_pts := PackedVector2Array()
		for i in range(13):
			var a := deg_to_rad(lerpf(-155.0, -65.0, float(i) / 12.0))
			hl_pts.append(c + Vector2(cos(a) * (s_rx - 3.2), sin(a) * (s_ry - 3.2)))
		draw_polyline(hl_pts, Color(1.0, 1.0, 1.0, 0.5 * fade), 2.4, true)

		# 5. 沿罩面公转的能量流光（4 枚能量光点 + 拖尾）
		for i in range(4):
			var fa := -aegis_rot * 1.6 + float(i) * (TAU / 4.0)
			var fp := c + Vector2(cos(fa) * s_rx, sin(fa) * s_ry)
			var fp_prev := c + Vector2(cos(fa - 0.26) * s_rx, sin(fa - 0.26) * s_ry)
			draw_line(fp_prev, fp, Color(col_edge.r, col_edge.g, col_edge.b, 0.6 * fade), 1.6, true)
			draw_circle(fp, 2.1, Color(col_edge.r, col_edge.g, col_edge.b, 0.92 * fade))
			draw_circle(fp, 1.0, Color(1.0, 1.0, 1.0, 0.95 * fade))

		# 6. 脚底落地光晕（罩体接地暗示，替代旧金莲大阵）
		var ground_y := c.y + s_ry * 0.86
		var glow_pts := PackedVector2Array()
		for i in range(25):
			var a := float(i) * (TAU / 24.0)
			glow_pts.append(Vector2(c.x + cos(a) * s_rx * 1.05, ground_y + sin(a) * 4.5))
		draw_colored_polygon(glow_pts, Color(col_main.r, col_main.g, col_main.b, 0.10 * fade))
		draw_polyline(glow_pts, Color(col_edge.r, col_edge.g, col_edge.b, 0.30 * fade), 1.2, true)

	elif aegis_shatter_progress >= 0.0:
		# 结界到期破碎：纯粒子化向四周迸散（暖金碎星）
		var p := aegis_shatter_progress
		var alpha := 1.0 - p
		for spk in aegis_shatter_sparks:
			var sp_pos: Vector2 = spk["pos"]
			var sp_sz: float = float(spk["size"]) * (1.0 - p * 0.4)
			draw_circle(sp_pos, sp_sz, Color(1, 1, 1, alpha * 0.95))
			var tail := sp_pos - Vector2(spk["vel"]).normalized() * (8.0 * (1.0 - p))
			draw_line(tail, sp_pos, Color(GameStyle.AURUM_EDGE.r, GameStyle.AURUM_EDGE.g, GameStyle.AURUM_EDGE.b, alpha * 0.85), 1.6)

		# 微细环形音爆裂纹（急速淡出，暖金，随体型缩放）
		if p < 0.4:
			var ring_p := p / 0.4
			var s_rx := (SHIELD_RX + ring_p * 18.0) * _body_scale.x
			var s_ry := (SHIELD_RY + ring_p * 18.0) * _body_scale.y
			var sc := Vector2(SHIELD_CENTER.x, SHIELD_CENTER.y * _body_scale.y)
			var shatter_pts := PackedVector2Array()
			for i in range(25):
				var a := float(i) * (TAU / 24.0)
				shatter_pts.append(sc + Vector2(cos(a) * s_rx, sin(a) * s_ry))
			draw_polyline(shatter_pts, Color(GameStyle.AURUM_EDGE.r, GameStyle.AURUM_EDGE.g, GameStyle.AURUM_EDGE.b, (1.0 - ring_p) * 0.75), 1.8, true)

## back-out 缓出（护罩登场弹出用，末端略过冲再回弹）
func _back_out(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var x := t - 1.0
	return 1.0 + c3 * x * x * x + c1 * x * x

## 绘制【回春术】：地面九品青莲生机甘露阵 + 穿透升华的生机光羽（彻底剔除绿色大光罩覆盖）
func _draw_renewal_fx() -> void:
	var p := renewal_progress
	var alpha := 1.0 - p
	var r := 16.0 + p * 36.0

	# 1. 地面九品青莲甘露阵（层叠展开的生机青玉莲瓣与甘露环）
	var ring_col := Color(GameStyle.GOOD.r, GameStyle.GOOD.g, GameStyle.GOOD.b, alpha * 0.95)
	draw_arc(FEET_CENTER, r, 0.0, TAU, 32, ring_col, maxf(1.0, 3.2 * (1.0 - p)), true)
	draw_arc(FEET_CENTER, r * 0.65, -p * 2.5, -p * 2.5 + TAU * 0.85, 24, Color(1.0, 1.0, 1.0, alpha * 0.85), 1.5, true)

	# 莲瓣角标
	for i in range(8):
		var la := float(i) * (TAU / 8.0) + p * 0.8
		var lp := FEET_CENTER + Vector2(cos(la) * r, sin(la) * (r * 0.42))
		draw_circle(lp, maxf(1.0, 2.8 * (1.0 - p * 0.5)), Color.WHITE)

	# 2. 旋升穿透身躯的甘露光羽与灵气微粒（从脚底直冲云霄，化作点点甘霖）
	for pt in renewal_particles:
		var cur_y := float(pt["y"])
		var cur_r := float(pt["radius"]) * (1.0 - p * 0.2)
		var ang := float(pt["ang"])
		var pos := Vector2(cos(ang) * cur_r, cur_y)
		var p_alpha := clampf((1.0 - p) * 1.3, 0.0, 1.0)
		var p_sz: float = float(pt.get("size", 2.2)) * (1.0 - p * 0.3)

		# 翠绿甘露光羽 + 纯白灵核
		draw_circle(pos, p_sz, Color(GameStyle.GOOD.r, GameStyle.GOOD.g, GameStyle.GOOD.b, p_alpha * 0.9))
		draw_circle(pos, p_sz * 0.55, Color(1.0, 1.0, 1.0, p_alpha * 0.95))
		# 向上拖曳的甘霖光丝
		var tail_p := pos + Vector2(0.0, float(pt["speed_y"]) * 0.06 * (1.0 - p))
		draw_line(tail_p, pos, Color(GameStyle.GOOD.r, GameStyle.GOOD.g, GameStyle.GOOD.b, p_alpha * 0.65), 1.2)

## 绘制【药爆】：摔碎药罐的地面药液波纹、四散飞沫与升华药气
func _draw_elixir_fx() -> void:
	var p := elixir_progress
	var alpha := 1.0 - p

	# 1. 地面药罐碎裂波纹：两层透视椭圆（脚底展开）
	var col_good := GameStyle.GOOD
	var col_edge := GameStyle.GOOD  # TODO(药爆作者): 原写 GOOD_EDGE 并不存在，先以 GOOD 顶替编译
	var ring_rx := 24.0 + p * 38.0
	var ring_ry := 10.0 + p * 16.0
	var ring_pts := PackedVector2Array()
	for i in range(25):
		var a := float(i) * (TAU / 24.0)
		ring_pts.append(FEET_CENTER + Vector2(cos(a) * ring_rx, sin(a) * ring_ry))
	draw_polyline(ring_pts, Color(col_good.r, col_good.g, col_good.b, alpha * 0.85), 2.0, true)

	# 内圈白细光环
	if p < 0.6:
		var in_p := p / 0.6
		var in_rx := ring_rx * 0.65
		var in_ry := ring_ry * 0.65
		var in_pts := PackedVector2Array()
		for i in range(25):
			var a := float(i) * (TAU / 24.0)
			in_pts.append(FEET_CENTER + Vector2(cos(a) * in_rx, sin(a) * in_ry))
		draw_polyline(in_pts, Color(1.0, 1.0, 1.0, (1.0 - in_p) * 0.75), 1.2, true)

	# 2. 四散飞溅的药沫与药液微滴
	for spk in elixir_shards:
		var sp_pos: Vector2 = spk["pos"]
		var sp_sz: float = float(spk["size"]) * (1.0 - p * 0.4)
		var is_leaf: bool = bool(spk.get("is_leaf", false))
		var col := col_edge if is_leaf else col_good
		draw_circle(sp_pos, sp_sz, Color(col.r, col.g, col.b, alpha * 0.95))
		draw_circle(sp_pos, sp_sz * 0.5, Color(1.0, 1.0, 1.0, alpha * 0.95))
		# 飞溅短拖尾
		var vel: Vector2 = spk["vel"]
		if vel.length_squared() > 100.0:
			var tail := sp_pos - vel.normalized() * (6.0 * (1.0 - p))
			draw_line(tail, sp_pos, Color(col.r, col.g, col.b, alpha * 0.65), 1.2)

	# 3. 自身周围升华的药香甘气（6 缕青碧药气，代表自身治疗）
	for k in range(6):
		var ka := float(k) * (TAU / 6.0) + p * 2.5
		var kr := 10.0 + sin(p * PI + float(k)) * 6.0
		var ky := lerpf(FEET_CENTER.y, BODY_CENTER.y - 12.0, p) + sin(float(k) * 1.5) * 4.0
		var kp := Vector2(cos(ka) * kr, ky)
		draw_circle(kp, 1.6 * (1.0 - p * 0.3), Color(col_good.r, col_good.g, col_good.b, alpha * 0.8))
		draw_circle(kp, 0.8, Color(1.0, 1.0, 1.0, alpha * 0.9))

## 绘制【天雷】周身雷弧火花（雷法真君）
func _draw_thunder_sparks() -> void:
	var alpha := clampf(thunder_flash_timer / 0.28, 0.0, 1.0)
	var bc := BODY_CENTER * _body_scale.y
	for i in range(2):
		var a1 := float(i) * PI + randf_range(-0.4, 0.4)
		var r1 := randf_range(12.0, 22.0) * _body_scale.x
		var p1 := bc + Vector2(cos(a1) * r1, sin(a1) * r1 * 0.8)
		var mid := bc + Vector2(cos(a1 + 0.6) * (r1 * 1.3), sin(a1 + 0.6) * (r1 * 0.9))
		var a2 := a1 + 1.2
		var p2 := bc + Vector2(cos(a2) * r1, sin(a2) * r1 * 0.8)
		var pts := PackedVector2Array([p1, mid, p2])
		draw_polyline(pts, Color(GameStyle.GOLD_EDGE.r, GameStyle.GOLD_EDGE.g, GameStyle.GOLD_EDGE.b, alpha * 0.85), 1.6)
		draw_polyline(pts, Color(1.0, 1.0, 1.0, alpha * 0.95), 0.8)
	for sp in thunder_sparks:
		var sp_alpha := clampf(float(sp["life"]) / float(sp["max_life"]), 0.0, 1.0) * alpha
		draw_circle(sp["pos"], 1.5, Color(1.0, 1.0, 1.0, sp_alpha))
		draw_circle(sp["pos"], 2.4, Color(GameStyle.GOLD_EDGE.r, GameStyle.GOLD_EDGE.g, GameStyle.GOLD_EDGE.b, sp_alpha * 0.6))

## 绘制【盾势】玄金护体残弧（守卫）
func _draw_guard_stance_fx() -> void:
	var sc := Vector2(SHIELD_CENTER.x, SHIELD_CENTER.y * _body_scale.y)
	if guard_charge_ratio > 0.0:
		var pop_scale := 1.0 + _guard_pop * 0.22
		var rx := SHIELD_RX * _body_scale.x * pop_scale
		var ry := SHIELD_RY * _body_scale.y * pop_scale
		var alpha := clampf(0.22 + guard_charge_ratio * 0.62, 0.0, 0.85)
		var width := 1.8 + guard_charge_ratio * 1.2
		var col_edge := GameStyle.AURUM_EDGE

		# 绘制 4 段环绕罡气弧
		var a_span := (TAU * 0.25) * 0.65
		for i in range(4):
			var a_start := guard_rot + float(i) * (TAU * 0.25)
			var arc_pts := PackedVector2Array()
			var steps := 8
			for s in range(steps + 1):
				var ang := a_start + a_span * (float(s) / float(steps))
				arc_pts.append(sc + Vector2(cos(ang) * rx, sin(ang) * ry))
			draw_polyline(arc_pts, Color(col_edge.r, col_edge.g, col_edge.b, alpha), width, true)
			draw_polyline(arc_pts, Color(1.0, 1.0, 1.0, alpha * 0.4), maxf(1.0, width * 0.4), true)

		# 接近蓄满时（>=90%）在四极闪烁蓄力标示
		if guard_charge_ratio >= 0.90:
			var pip_alpha := (0.6 + sin(guard_rot * 6.0) * 0.4) * alpha
			for i in range(4):
				var pa := guard_rot + float(i) * (TAU * 0.25) + a_span * 0.5
				var pp := sc + Vector2(cos(pa) * (rx + 2.5), sin(pa) * (ry + 2.5))
				draw_circle(pp, 2.0, Color(col_edge.r, col_edge.g, col_edge.b, pip_alpha))
				draw_circle(pp, 1.0, Color(1.0, 1.0, 1.0, pip_alpha))

	# 蓄满爆发当帧扩散冲击
	if guard_burst_timer > 0.0:
		var bp := 1.0 - guard_burst_timer / 0.24
		var b_rx := lerpf(SHIELD_RX * _body_scale.x, 48.0 * _body_scale.x, bp)
		var b_ry := lerpf(SHIELD_RY * _body_scale.y, 48.0 * _body_scale.y, bp)
		var b_pts := PackedVector2Array()
		for i in range(25):
			var a := float(i) * (TAU / 24.0)
			b_pts.append(sc + Vector2(cos(a) * b_rx, sin(a) * b_ry))
		draw_polyline(b_pts, Color(GameStyle.AURUM_EDGE.r, GameStyle.AURUM_EDGE.g, GameStyle.AURUM_EDGE.b, (1.0 - bp) * 0.8), 2.2, true)

## 绘制【战意】血煞腾空火星与战圈（狂战士）
func _draw_frenzy_fx() -> void:
	# 1. 升腾的血煞煞气星芒
	for sp in frenzy_sparks:
		var ratio := clampf(float(sp["life"]) / float(sp["max_life"]), 0.0, 1.0)
		var p_pos: Vector2 = sp["pos"]
		var sz: float = float(sp.get("size", 2.0))
		var col := Color(0.95, 0.22, 0.16, ratio * 0.85)
		var tail := p_pos + Vector2(0.0, 4.0 * ratio)
		draw_line(tail, p_pos, col, sz, true)
		draw_circle(p_pos, sz * 0.5, Color(1.0, 0.7, 0.4, ratio * 0.95))

	# 2. 战意达到 10 层以上时在脚底绘制旋转血煞战印
	if frenzy_stacks >= 10.0:
		var f_ratio := clampf(frenzy_stacks / 20.0, 0.0, 1.0)
		var r := 16.0 * _body_scale.x
		var fc := FEET_CENTER * _body_scale.y
		var col_ring := Color(0.92, 0.18, 0.15, 0.28 * f_ratio)
		draw_arc(fc, r, 0.0, TAU, 20, col_ring, 1.2, true)
		for i in range(4):
			var a := float(i) * (TAU * 0.25)
			var p1 := fc + Vector2(cos(a) * r, sin(a) * r)
			var p2 := fc + Vector2(cos(a) * (r + 3.5), sin(a) * (r + 3.5))
			draw_line(p1, p2, col_ring, 1.2)

	# 3. 满层（20层）瞬时爆气光环
	if frenzy_burst_timer > 0.0:
		var p := 1.0 - frenzy_burst_timer / 0.28
		var bc := BODY_CENTER * _body_scale.y
		var r_burst := lerpf(12.0, 36.0, p) * _body_scale.x
		draw_arc(bc, r_burst, 0.0, TAU, 24, Color(1.0, 0.25, 0.18, (1.0 - p) * 0.9), 2.4, true)

## 绘制【斩灭凝神】剑意返照十字星芒（绝尘）
func _draw_cd_refund_fx() -> void:
	var alpha := clampf(cd_refund_timer / 0.24, 0.0, 1.0)
	var bc := BODY_CENTER * _body_scale.y
	var s_len := 9.0 * alpha * _body_scale.x
	var col_jade := GameStyle.JADE_EDGE
	draw_line(bc - Vector2(s_len, 0.0), bc + Vector2(s_len, 0.0), Color(col_jade.r, col_jade.g, col_jade.b, alpha * 0.9), 1.8)
	draw_line(bc - Vector2(0.0, s_len), bc + Vector2(0.0, s_len), Color(col_jade.r, col_jade.g, col_jade.b, alpha * 0.9), 1.8)
	draw_circle(bc, 2.2 * alpha, Color(1.0, 1.0, 1.0, alpha * 0.95))

## 绘制【陷阵】脚底破阵刻印（蛮兵）
func _draw_crowd_aura_fx() -> void:
	var r := 26.0 * _body_scale.x
	var fc := FEET_CENTER * _body_scale.y
	var col := Color(0.88, 0.62, 0.30, crowd_aura_alpha * 0.45)
	for i in range(4):
		var a_start := float(i) * (TAU * 0.25) + 0.18
		var a_span := (TAU * 0.25) * 0.64
		draw_arc(fc, r, a_start, a_start + a_span, 10, col, 1.4, true)
		var tick_a := float(i) * (TAU * 0.25)
		var p1 := fc + Vector2(cos(tick_a) * r, sin(tick_a) * r)
		var p2 := fc + Vector2(cos(tick_a) * (r + 4.5), sin(tick_a) * (r + 4.5))
		draw_line(p1, p2, col, 1.4)

