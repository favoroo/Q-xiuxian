class_name ProjectileHandler
extends RefCounted

## 远程弹丸（PROJECTILE）行为实现（2026-10-24 自 FloatingWeapon 拆出）：
## 齐射目标分配（_volley_targets）、预判瞄准（lead_aim_pos）、逐发出膛与五行异常装填。
##
## 纪律：首参 w 为宿主武器（不标类型，鸭类型访问——武器侧硬类型引用会触发
## 循环类依赖，把弹丸 preload 打成空 PackedScene，项目坑 12）。
## 目标速度同样鸭类型读取（get_velocity_for_lead / CharacterBody2D.velocity / get("velocity")）。

## 远程弹丸航程余量（2026-10-20 射程体系重做）：
## 旧写法弹丸寿命固定 BASE_LIFETIME=1.0s ⇒ 所有远程裸航程都是 420px，与卡面 range 脱钩
## （range 只改「锁谁」，低 range 的远程反而够不到远处怪，卡面数字成了空头支票）。
## 改后航程 = (攻击范围 × 乘区 + 本余量)：锁得到的就打得到，且各武器航程随自身 range 分化，
## 范围词条叠高时航程同步外扩但不越出「别拉满屏」的口径。60px ≈ 一次脱程判定的缓冲。
const PROJECTILE_TRAVEL_MARGIN := 60.0

## 预判提前量上限（秒）：防止对高速怪算出夸张拦截点，弹丸反而绕大弯
const LEAD_TIME_CAP := 0.35

## _volley_targets 排序上下文（命名方法避免每次开火 new 闭包，照 Player._sort_candidate_by_dist 先例）
static var _volley_player_pos: Vector2 = Vector2.ZERO
static var _volley_muzzle_pos: Vector2 = Vector2.ZERO

## 逐发分配锁定目标：主目标（Player 按扇区统筹分配的那一个）排第一，其余按同屏优先 + 离炮口的远近补齐。
## 返回长度 = min(场上可用人手, n)，调用方按 idx % size 取用 ⇒ 怪少时多发自然归约到同一个敌人。
## 纯索敌，不改任何数值：弹丸拿到目标后按 BladeProjectile.HOMING_TURN_RATE 自己拐过去。
## 2026-10-22 性能优化：三个返回/候选数组改静态缓冲（开火热路径原先每次 new 3 个 Array，
## 8 武器高攻速时每秒数十次分配）。开火在武器 _process 逐把顺序执行、不重入，静态共享安全；
## 调用方只在本次开火内消费返回值，下一次调用覆写。
static var _volley_out_buf: Array[Node2D] = []
static var _volley_cands_buf: Array[Node2D] = []
static var _volley_chest_buf: Array[Node2D] = []

## 预判瞄准点（2026-10-22）：弹丸瞄目标的"当前位置"时，横移的敌人容易擦空 —— 看着就"笨"。
## 按「弹丸飞到所需时间」提前量取拦截点，玩家读起来是武器会"算"，而不是机械地朝哪儿打哪儿。
## 速度必须鸭类型读取：本仓严禁在武器侧硬引用 EnemyBase（循环类依赖会把弹丸 preload 打成空包）。
static func lead_aim_pos(w, target: Node2D) -> Vector2:
	if target == null or not is_instance_valid(target):
		return w.global_position
	var tpos: Vector2 = target.global_position
	var dist: float = (tpos - w.global_position).length()
	# 弹速只在远程武器上有意义；无 bullet_speed 时用经验值兜底
	var shot_speed: float = float(w.def.get("bullet_speed", 420.0))
	var lead_time: float = clampf(dist / maxf(1.0, shot_speed), 0.0, LEAD_TIME_CAP)
	var tv: Vector2 = Vector2.ZERO
	if target.has_method("get_velocity_for_lead"):
		tv = target.get_velocity_for_lead()
	elif target is CharacterBody2D:
		# 只读属性，不类型化调用 EnemyBase 的任何方法
		tv = (target as CharacterBody2D).velocity
	elif target.get("velocity") != null:
		tv = target.get("velocity")
	return tpos + tv * lead_time

static func volley_targets(w, n: int) -> Array[Node2D]:
	var out := _volley_out_buf
	out.clear()
	if n <= 0:
		return out
	if w.current_target != null and is_instance_valid(w.current_target):
		out.append(w.current_target)
	if n <= 1:
		return out
	var player = GameManager.player
	if player == null:
		return out
	var eff_range: float = w.attack_range * w._range_mult()
	var results: Array = w._query_enemies(eff_range, player.global_position, 32)
	var muzzle_pos: Vector2 = w.muzzle_point.global_position
	var player_pos: Vector2 = player.global_position
	var cands := _volley_cands_buf
	var chest_cands := _volley_chest_buf
	cands.clear()
	chest_cands.clear()
	for res in results:
		var col = res.get("collider")
		if col == null or col.get_parent() == null:
			continue
		var e := col.get_parent() as Node2D
		if e == null or not e.has_method("take_damage") or e.is_in_group("herbs"):
			continue
		if out.has(e):
			continue
		if GameBalance.elliptical_distance(e.global_position - player_pos) > eff_range:
			continue
		if e.is_in_group("chests"):
			chest_cands.append(e)
			continue
		cands.append(e)
	# 同屏可见优先，同屏状态一致时离炮口近的先被咬住
	# 命名方法排序避免每次开火 new 闭包（照 Player._sort_candidate_by_dist 先例）
	_volley_player_pos = player_pos
	_volley_muzzle_pos = muzzle_pos
	cands.sort_custom(_sort_by_proximity)
	chest_cands.sort_custom(_sort_by_proximity)
	for e in cands:
		if out.size() >= n:
			break
		out.append(e)
	# 场上妖不够分的时候，多出来的那几发不许往同一个活物身上重复招呼：
	# 脚边有匣子就顺手砸匣子（匣子掉补给，重复的那发只掉一个"过量"）
	for c in chest_cands:
		if out.size() >= n:
			break
		out.append(c)
	return out

## 齐射排序：同屏可见优先，同屏状态一致时离炮口近的先被咬住。
## 命名方法（非闭包）避免每次开火分配 Callable；上下文经静态 _volley_player_pos/_volley_muzzle_pos 传入。
static func _sort_by_proximity(a: Node2D, b: Node2D) -> bool:
	var a_on := GameBalance.is_in_viewport(a.global_position, _volley_player_pos)
	var b_on := GameBalance.is_in_viewport(b.global_position, _volley_player_pos)
	if a_on != b_on:
		return a_on
	return _volley_muzzle_pos.distance_squared_to(a.global_position) < _volley_muzzle_pos.distance_squared_to(b.global_position)

static func perform(w) -> void:
	w.is_attacking = true

	var aim_dir = Vector2.RIGHT.rotated(w.rotation)
	if w.current_target != null:
		# 与武器 _process 的朝向同源：本体已经按预判点拧正，出膛方向必须同一份预判，
		# 否则视觉指向前置点、弹道却飞当前位置，读起来是"瞄偏了"
		aim_dir = (lead_aim_pos(w, w.current_target) - w.global_position).normalized()
		# 开火这一帧就把发射帧拧到目标方位：贴图补偿跟着走，剑尖与出膛方向同轴
		w._apply_facing(aim_dir.angle())

	# 后坐动画：极速后座冲击（0.04s）+ 弹性回正，凸显远程出膛爆发力（帧内状态机，零 Tween）
	w._begin_lunge(-aim_dir * w.RECOIL_DIST, w.RECOIL_BACK_TIME, w.RECOIL_RETURN_TIME, true)

	# 开火反馈：枪口闪光 + 本体亮闪（状态机版本：起火时记初值，_tick_fire_fx 推进）
	if w.muzzle_flash != null:
		w.muzzle_flash.rotation = randf() * TAU
		w._muzzle_scale0 = randf_range(0.42, 0.52)
		w.muzzle_flash.scale = Vector2.ONE * w._muzzle_scale0
		w.muzzle_flash.modulate = w._muzzle_color()
		w.muzzle_flash.visible = true
		w._muzzle_t = w.MUZZLE_TIME
	w._flash_sprite(Color(1.35, 1.35, 1.35), 0.12)

	var p_count: int = maxi(1, int(w.def.get("projectile_count", 1)))
	var tags: Array = WeaponData.tags_of(w.weapon_def_id)
	if tags.has("talisman") or int(w.def.get("behavior", -1)) == WeaponData.Behavior.PROJECTILE:
		p_count += int(round(GameManager.item_hook_sum("projectile_count_bonus")))
	var p_spread: float = float(w.def.get("spread_angle", 0.2))
	var p_bounce: int = int(w.def.get("bounce_count", 0))
	var final_dmg: float = w._final_damage()
	# 弹丸外观按武器归位（2026-10-09 才真正接上）：WeaponData 的 bullet / bullet_scale / bullet_spin
	# 三个字段 2026-10-08 就写进表里了，但出膛那一圈从来没读它 —— 运行时五把远程武器
	# 打出去的全是 BladeProjectile.tscn 里那张公共火符（用户口径：「不知道从哪里发射出来的」）。
	# 2026-10-16 起改为 setup 期解析缓存（武器 _bullet_tex 等），开火热路径零资源查找。
	# 逐发锁定：一次三发的武器，每一发各咬一个最近的敌人。
	# 旧写法三发全按同一个 aim_dir 扇形散开 ⇒ 只剩一个敌人时两边那两发飞过头顶（仿真：350px
	# 处散布侧偏 70+px，而判定只有 7px + 受击圈 15px），群怪时又因为不追踪而大量空放。
	# 现在"扇形疾射…贯穿群敌"按文案兑现：出膛照旧扇形错开，各自追上自己咬定的那一个；
	# 场上只剩一个敌人时三发也统统归它 —— 单点爆发不再靠运气。
	var volley: Array[Node2D] = volley_targets(w, p_count)

	for idx in range(p_count):
		# 弹丸走对象池（2026-10-10 性能优化）：不再 instantiate/queue_free 高频往复
		var p: BladeProjectile = BladeProjectile.acquire_or_new(w.projectile_scene, w.get_tree().current_scene)
		p.global_position = w.muzzle_point.global_position
		var offset_ang := 0.0
		if p_count > 1:
			offset_ang = (float(idx) - float(p_count - 1) * 0.5) * p_spread
		# 出膛方向与追踪：每发优先分配不同敌人；超出目标数的多余弹丸不再全部追踪同一小怪（防散射变秒杀炮），
		# 精英/Boss 允许最多 2 发锁定，其余保持扇形散角飞出。
		var shot_dir: Vector2 = aim_dir
		var locked: Node2D = null
		if idx < volley.size():
			locked = volley[idx]
		elif not volley.is_empty():
			var first_t: Node2D = volley[0]
			if first_t != null and is_instance_valid(first_t) and first_t.get("is_elite") == true and idx == 1:
				locked = first_t
		if locked != null and is_instance_valid(locked):
			var to_lock: Vector2 = lead_aim_pos(w, locked) - w.muzzle_point.global_position
			if to_lock.length_squared() > 1.0:
				shot_dir = to_lock.normalized()
		p.homing_target = locked
		p.direction = shot_dir.rotated(offset_ang)
		p.damage = final_dmg
		p.knockback_base = WeaponData.knockback_for(w.weapon_def_id, 140.0)
		p.pierce_left = WeaponData.capped_pierce(w.pierce + GameManager.bonus_pierce)
		p.bounce_left = p_bounce
		p.bullet_texture = w._bullet_tex
		p.bullet_scale = w._bullet_scale
		p.spin = w._bullet_spins
		# 吸血分档：弹丸按远程系数（机关炮台在 TurretUnit 里另填 TURRET）
		p.source_behavior = WeaponData.Behavior.PROJECTILE
		if w.def.get("proc_burn", false):
			p.proc_burn = true
			p.burn_dps = final_dmg * float(w.def.get("burn_ratio", 0.4))
			p.burn_dur = float(w.def.get("burn_dur", 3.0))
		if float(w.def.get("proc_chill", 0.0)) > 0.0:
			p.proc_chill = float(w.def.get("proc_chill", 0.35))
			p.chill_dur = float(w.def.get("chill_dur", 2.0))
		if w.def.get("proc_poison", false):
			p.proc_poison = true
			p.poison_dps = final_dmg * float(w.def.get("poison_ratio", 0.3))
			p.poison_dur = float(w.def.get("poison_dur", 2.5))
		# 池化后 _ready 先于字段赋值跑过，由 activate 按当前字段值统一铺视觉与物理状态
		p.activate()
		# 航程 = (攻击范围 × 乘区 + 余量) / 弹速（2026-10-20 射程体系重做）：
		# 必须在 activate 之后设：activate 会把 lifetime 重置回 BASE_LIFETIME。
		# 旧写法 p.lifetime *= _range_mult() 让所有远程裸航程恒为 420px、range 形同虚设；
		# 现改为按每把武器自身 range 定量，锁多远的怪就飞多远（近战/横扫的 range 也已改为真实命中半径）。
		p.lifetime = (w.attack_range * w._range_mult() + PROJECTILE_TRAVEL_MARGIN) / maxf(1.0, p.speed)

	AudioManager.play_sfx(WeaponData.sfx_for(w.weapon_def_id))
