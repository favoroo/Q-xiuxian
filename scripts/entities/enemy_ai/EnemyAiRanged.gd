extends RefCounted

## 远程施法支路（2026-11-02 自 EnemyBase 拆出，逐行平移零逻辑改动）：
## 远程风筝移动 / 火球蓄力直射（御剑邪修） / 雷环齐射（赤雷兽） / 瞬身回斩（剑煞变异）。
##
## 纪律：首参 e 为宿主敌人（不标类型，鸭类型访问——反向硬类型引用 EnemyBase 会触发
## 循环类依赖，把场景 preload 打成空包，项目坑 12/16）。含宿主成员的声明用显式类型
## （无类型参数上 := 推断必炸）。宿主保留同名一行转发器（判据测试直调口径）。

const BOLT_WINDUP_TINT := Color(1.9, 1.35, 0.85)  ## 蓄力本体暖色提亮（比自爆引信的 2.2 档淡，一读是「要出手」不是「要炸了」）
const BOLT_GATHER_INTERVAL := 0.12  ## 蓄力期灵力汇聚粒子续发间隔（低频，走 FxParticlePool 的 SOUL_ORB 帧闸）
const BOLT_GATHER_OFFSET := 26.0    ## 汇聚粒子相对器尖的初始偏移半径（从身周收束向器尖）

## 远程怪移动：保持距离，近了退、远了进、合适距离环绕游走。
static func tick_kite_range(e, dir: Vector2, dist_sq: float, eff_speed: float) -> void:
	# 远程怪：保持距离，近了退、远了进、合适距离环绕游走
	if not e.always_flee and not e._pp_stun and e.preferred_range > 0.0:
		var dist := sqrt(dist_sq)
		if dist < e.preferred_range - 30.0:
			e._pp_target_vel = -dir * eff_speed * 0.8
		elif dist <= e.preferred_range + 30.0:
			e._pp_target_vel = Vector2(-dir.y, dir.x) * e._kite_sign * eff_speed * BalanceCombat.KITE_STRAFE_SPEED

## 御剑邪修：保持距离的同时周期性发射火球（先蓄力预告，蓄力满才出手）。
## 贴脸禁射（2026-11-01）：玩家进到近战距离内不起手、蓄力中则作废 —— 近战贴脸是
## 「压掉直射」的奖励，而不是站在炮口上吃弹。环弹/死亡弹幕/冲刺侧弹不走这里，不受影响。
static func tick_bolt_cast(e, delta: float, player: Node2D, dist_sq: float) -> void:
	# 御剑邪修：保持距离的同时周期性发射火球（先蓄力预告，蓄力满才出手）
	if e.bolt_interval > 0.0 and e._fuse < 0.0:
		if e._bolt_windup_t >= 0.0:
			# 贴脸判先于站定：本帧保留 tick_kite_range 已写好的后撤速度，
			# 否则「蓄力作废却原地站桩」，玩家读不出「它在拉开距离」。
			if BalanceCombat.bolt_in_dead_zone(dist_sq):
				e._bolt_timer = BalanceCombat.BOLT_TOO_CLOSE_RETRY
				e._cancel_bolt_windup()
				return
			# 蓄力段：站定 + 本体提亮变色，出手方向每帧跟玩家（只作读法，出手那帧才锁死）
			e._pp_target_vel = Vector2.ZERO
			e._bolt_windup_dir = (player.global_position - e.global_position).normalized()
			tick_bolt_windup(e, delta)
			if e._bolt_windup_t <= 0.0:
				e._fire_bolt(player)
		else:
			e._bolt_timer -= delta
			if e._bolt_timer <= 0.0 and dist_sq < 396900.0 and not e._pp_stun:
				if BalanceCombat.bolt_in_dead_zone(dist_sq):
					e._bolt_timer = BalanceCombat.BOLT_TOO_CLOSE_RETRY
				else:
					e._bolt_timer = e.bolt_interval
					e._start_bolt_windup()

## 赤雷兽·雷环齐射：短前摇站定提亮 → 全向均布弧线雷弹（旋臂压迫走位）。
static func tick_ring_bolt_step(e, delta: float, dist_sq: float) -> void:
	# 赤雷兽·雷环齐射：短前摇站定提亮 → 全向均布弧线雷弹（旋臂压迫走位）
	if e.ring_bolt_interval > 0.0 and e._fuse < 0.0:
		if e._ring_bolt_windup_t >= 0.0:
			e._ring_bolt_windup_t -= delta
			e._pp_target_vel = Vector2.ZERO
			if e.procedural_view != null:
				e.procedural_view.special_state = clampf(1.0 - e._ring_bolt_windup_t / maxf(e.ring_bolt_windup, 0.001), 0.0, 1.0)
			if e._ring_bolt_windup_t <= 0.0:
				e._fire_ring_bolts()
		else:
			e._ring_bolt_timer -= delta
			# 与冲刺/落石互斥：冲刺锁定段或落石预警中不放环（冲刺中站定开环会撕裂位移）
			if e._ring_bolt_timer <= 0.0 and dist_sq < 640000.0 and not e._pp_stun \
					and e._charge_windup < 0.0 and e._charge_active <= 0.0 and e._charge_brake <= 0.0 \
					and e._rock_windup_t < 0.0:
				e._ring_bolt_timer = e.ring_bolt_interval
				start_ring_bolt_cast(e)

## 剑煞邪修·瞬身回斩（变异专属）：闪现侧翼 + 立刻扇形剑气反打。
static func tick_blink_strike_step(e, delta: float, player: Node2D) -> void:
	# 剑煞邪修·瞬身回斩（变异专属）：闪现侧翼 + 立刻扇形剑气反打
	if e.blink_strike_interval > 0.0 and e._fuse < 0.0:
		e._blink_strike_timer -= delta
		if e._blink_strike_timer <= 0.0 and not e._pp_stun:
			e._blink_strike_timer = e.blink_strike_interval
			e._blink_strike(player)

## 起手蓄力：站定 + 变色 + 形变 + 低音量引信声。方向不在此锁（出手那帧才锁，蓄力期只作预告读法）
static func start_bolt_windup(e) -> void:
	e._bolt_windup_t = maxf(e.bolt_windup, 0.05)
	e._bolt_windup_total = e._bolt_windup_t
	e._bolt_gather_cd = 0.0
	e._bolt_base_tint = e.anim_sprite.modulate
	e.anim_sprite.modulate = BOLT_WINDUP_TINT
	e.play_squash(Vector2(1.14, 0.88), e._bolt_windup_t)
	AudioManager.play_sfx("enemy_fuse", 0.4)
	# 起手当帧就进施法姿态（>0 即 casting），避免首帧剑仍停在巡航位再跳一下
	if e.procedural_view != null:
		e.procedural_view.special_state = 0.001

## 蓄力期推进（每物理帧）：算 0→1 进度写进 special_state（驱动器尖聚能球由小到大），
## 并低频续发向器尖收束的灵力微粒。器尖聚能 = 施法「正在攒劲」的可读读数。
static func tick_bolt_windup(e, delta: float) -> void:
	e._bolt_windup_t -= delta
	var progress: float = 0.0
	if e._bolt_windup_total > 0.001:
		progress = clampf(1.0 - e._bolt_windup_t / e._bolt_windup_total, 0.0, 1.0)
	if e.procedural_view != null:
		e.procedural_view.special_state = progress
		e.procedural_view.aim_dir = e._bolt_windup_dir
	# 灵力汇聚微粒：只对施法读法有意义的邪修系（有法剑器尖）发放，且走 SOUL_ORB 帧闸
	if e._bolt_gather_cd <= 0.0 and e.procedural_view != null:
		e._bolt_gather_cd = BOLT_GATHER_INTERVAL
		var tip: Vector2 = e.procedural_view.get_weapon_tip_global_pos()
		var out_dir: Vector2 = (e._bolt_windup_dir if e._bolt_windup_dir.length_squared() > 0.001 else Vector2.RIGHT)
		# 从器尖反向偏移一圈外沿出发，粒子顺向收束到器尖（FX 内部有上浮/汇聚感）
		var gather_pos: Vector2 = tip - out_dir * BOLT_GATHER_OFFSET
		FxParticlePool.burst(FxParticlePool.SOUL_ORB, gather_pos, _bolt_gather_color(e), 0.8, false, out_dir)
	else:
		e._bolt_gather_cd -= delta

## 灵力汇聚/打断四散的配色：剑煞血红、御剑幽蓝（与弹体色温同源）
static func _bolt_gather_color(e) -> Color:
	var is_jiansha: bool = (e.enemy_id == "jiansha_elite" or e.name.to_lower().begins_with("jiansha"))
	return GameStyle.FX_HDR_CRIT if is_jiansha else GameStyle.FX_HDR_WATER

## 蓄力被打断（受击硬直等）时还原本体色，蓄力作废不补发（硬直窗口就是玩家的反打奖励）
## 同时把已聚拢的灵力「炸散」：一撮微粒反向迸出，强化「打断成功」的反馈读数
static func cancel_bolt_windup(e) -> void:
	if e._bolt_windup_t < 0.0:
		return
	e._bolt_windup_t = -1.0
	e._bolt_windup_total = 0.0
	e.anim_sprite.modulate = e._bolt_base_tint
	if e.procedural_view != null:
		e.procedural_view.position.x = 0.0
		e.procedural_view.special_state = 0.0
		# 打断四散：从器尖处迸一小撮灵光（bypass 帧闸：低频、且这是玩家挣来的反馈，不该被受击火花挤掉）
		var tip: Vector2 = e.procedural_view.get_weapon_tip_global_pos()
		FxParticlePool.burst(FxParticlePool.SOUL_ORB, tip, _bolt_gather_color(e), 1.0, true)

## 发射火球（御剑邪修；bolt_count>1 时按 bolt_spread 扇形展开，剑煞邪修三连击）
static func fire_bolt(e, player: Node2D) -> void:
	e._bolt_windup_t = -1.0
	e._bolt_windup_total = 0.0
	e.anim_sprite.modulate = e._bolt_base_tint
	# 出手方向最后锁死：蓄力期玩家已看过预告，锁死的是「预告过的那个方向」
	var base_dir: Vector2 = (player.global_position - e.global_position).normalized()

	# 出膛点对齐法剑器尖（避免从肚脐中心凭空刷出）
	var spawn_pos: Vector2 = e.global_position
	if e.procedural_view != null:
		spawn_pos = e.procedural_view.get_weapon_tip_global_pos()
		e.procedural_view.trigger_recoil(base_dir)

		var is_jiansha: bool = (e.enemy_id == "jiansha_elite" or e.name.to_lower().begins_with("jiansha"))
		var is_xuanming: bool = (e.enemy_id == "xuanming_elite" or e.name.to_lower().begins_with("xuanming"))
		for i in range(maxi(1, e.bolt_count)):
			# 火球走对象池（2026-10-11）：远程妖周期直射不再走 instantiate/free
			var bolt := EnemyBolt.acquire(e.get_parent())
			bolt.global_position = spawn_pos
			var offset_ang := 0.0
			if e.bolt_count > 1:
				offset_ang = (float(i) - float(e.bolt_count - 1) * 0.5) * e.bolt_spread
			bolt.direction = base_dir.rotated(offset_ang)
			bolt.speed = 300.0 * e.bolt_speed_mult
			if e.bolt_curve_ang != 0.0:
				bolt.angular_speed = e.bolt_curve_ang
			bolt.damage = e.bolt_damage * (e.contact_damage / GameBalance.BOLT_DMG_BASE_REF)  # 随回合缩放比例与接触伤害一致（基准取邪修基础值 13）
			bolt.sword_style = true
			bolt.purple_style = is_jiansha or is_xuanming
			bolt.activate()
		e.play_squash(Vector2(1.16, 0.84), 0.16)
		AudioManager.play_sfx("enemy_bolt", 0.7)
		if e.get_parent() != null:
			# 出膛爆闪色温与弹体同源（火球炽阳 / 剑气赤煞炽阳 / 剑煞绯金），HDR 起辉读得出「这是什么弹」
			var pop_col := GameStyle.FX_HDR_CRIT if (is_jiansha or is_xuanming) else GameStyle.FX_HDR_FIRE
			JuiceEffect.spawn_impact_pop(e.get_parent(), spawn_pos, pop_col, base_dir)

## 雷环起手：短前摇站定，给玩家「要放全向环」的读法（前摇比震地短，但弹速慢可绕）
static func start_ring_bolt_cast(e) -> void:
	e._ring_bolt_windup_t = maxf(e.ring_bolt_windup, 0.05)
	e.play_squash(Vector2(1.16, 0.86), e._ring_bolt_windup_t)
	AudioManager.play_sfx("enemy_fuse", 0.5, 1.1)
	if e.procedural_view != null:
		e.procedural_view.special_state = 0.001

## 雷环出膛：全向均布，弧线角速度让弹幕形成旋臂（正面缝隙会转走，不能站桩等）
static func fire_ring_bolts(e) -> void:
	e._ring_bolt_windup_t = -1.0
	if e.dying or e.get_parent() == null:
		return
	if e.procedural_view != null:
		e.procedural_view.special_state = 0.0
	var count: int = maxi(e.ring_bolt_count, 1)
	var dmg := maxf(1.0, e.contact_damage * e.ring_bolt_dmg_mult)
	var offset_ang := GameManager.rng.randf() * TAU
	for i in range(count):
		var ang := offset_ang + TAU * float(i) / float(count)
		var bolt := EnemyBolt.acquire(e.get_parent())
		bolt.global_position = e.global_position
		bolt.direction = Vector2(cos(ang), sin(ang))
		bolt.speed = e.ring_bolt_speed * e.bolt_speed_mult
		bolt.damage = dmg
		bolt.angular_speed = e.ring_bolt_curve_ang
		bolt.activate()
	e.play_squash(Vector2(1.2, 0.8), 0.16)
	AudioManager.play_sfx("enemy_bolt", 0.7)
	if e.get_parent() != null:
		JuiceEffect.spawn_impact_pop(e.get_parent(), e.global_position, GameStyle.BAD, Vector2.ZERO)

## 瞬身到玩家侧翼 + 立刻扇形剑气反打：先给残影读「它换了位置」，再出弹读「从哪打来」。
## 落点受界碑约束，避免卡进地图外；剑气走 sword_style + purple_style（剑煞血光配色）。
static func blink_strike(e, player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	e._spawn_teleport_ghost()
	var angle := GameManager.rng.randf() * TAU
	var pos: Vector2 = player.global_position + Vector2(cos(angle), sin(angle)) * e.blink_strike_dist
	var lim: float = GameManager.MAP_HALF_EXTENT - GameBalance.BLINK_MAP_INSET
	e.global_position = pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	e.play_squash(Vector2(1.3, 0.7), 0.2)
	AudioManager.play_sfx("enemy_blink", 0.8)
	if e.dying or e.get_parent() == null:
		return
	var base_dir: Vector2 = (player.global_position - e.global_position).normalized()
	var count: int = maxi(e.blink_strike_bolts, 1)
	var dmg: float = e.bolt_damage * (e.contact_damage / GameBalance.BOLT_DMG_BASE_REF)
	for i in range(count):
		var offset_ang: float = (float(i) - float(count - 1) * 0.5) * e.blink_strike_bolt_arc * 2.0
		var bolt := EnemyBolt.acquire(e.get_parent())
		bolt.global_position = e.global_position
		bolt.direction = base_dir.rotated(offset_ang)
		bolt.speed = 300.0 * e.bolt_speed_mult
		bolt.damage = dmg
		bolt.sword_style = true
		bolt.purple_style = true
		bolt.activate()
	AudioManager.play_sfx("enemy_bolt", 0.65, 1.1)
