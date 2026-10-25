class_name OnHitEffects
extends RefCounted

## 命中/受击后的机制效果统一入口（2026-10-25 超级悟道「三道」重构新增）。
##
## 为什么要单独一层：超级悟道的机制卡（五行轮转 / 天罚 / 雷霆弹幕 / 万剑归宗）都要挂在
## 「某次命中之后」这一个时刻，而命中点散在 MeleeHandler / SweepHandler / ChannelHandler /
## BladeProjectile 四处。若每处各写一遍 hook 读取，加一张新卡就要改四个文件。
## 现在四个命中点各调一行 on_*_hit()，新卡只改本文件。
##
## 性能：命中路径是最高频的（束流 10+ tick/秒 × 多目标），所以本模块不逐字段调
## item_hook_sum（那会每个字段各算一遍 items.hash()），统一走 StatSystem.super_hook_snapshot
## —— 一次指纹校验取出整包机制读数，之后只做字典查找。
##
## 严禁类型化引用 EnemyBase / FloatingWeapon（项目坑 12/16）：全部 has_method 鸭类型。
## 随机：五行轮转属于玩法判定（决定是否挂异常），必须走 GameManager.rng（铁律 3）。

## 「有没有任何一张命中后机制卡」的记忆：指纹不变就不重复判定。
## 调用方每帧/每刀取一次，为 false 时整段跳过（无神通时命中路径退化为一次整数比较）。
static var _memo_stamp: int = -1
static var _memo_any: bool = false

static func any_enabled() -> bool:
	var snap := StatSystem.super_hook_snapshot(GameManager)
	var stamp: int = GameManager._super_hook_stamp
	if stamp == _memo_stamp:
		return _memo_any
	_memo_stamp = stamp
	_memo_any = float(snap.get("wuxing_rotation_chance", 0.0)) > 0.0 \
		or float(snap.get("crit_sky_bolt", 0.0)) > 0.0 \
		or float(snap.get("projectile_chain_lightning", 0.0)) > 0.0 \
		or float(snap.get("wuxing_all", 0.0)) > 0.0 \
		or float(snap.get("sword_qi", 0.0)) > 0.0
	return _memo_any

## 供测试/新开局重置记忆
static func reset_memo() -> void:
	_memo_stamp = -1
	_memo_any = false
	_fast_frame = -1
	_fast_any = false

## 弹丸命中等「每帧可能上百次」的调用点专用：再叠一层按物理帧的布尔缓存。
## any_enabled() 每次都要算一次 items.hash()（20 件道具约几微秒），44 发弹丸齐射时
## 一帧内会被调上百次；按帧折叠后一帧只算一次。
static var _fast_frame: int = -1
static var _fast_any: bool = false

static func any_enabled_fast() -> bool:
	var frame: int = Engine.get_physics_frames()
	if frame == _fast_frame:
		return _fast_any
	_fast_frame = frame
	_fast_any = any_enabled()
	return _fast_any

## 五行轮转：命中时按几率附加一种随机五行异常（火/水/木三系之一）。
static func _roll_wuxing(enemy: Object, damage: float, chance: float) -> void:
	if chance <= 0.0:
		return
	# 归一：几率超过 1 时每次必挂（多张叠加时不至于变成「必定不挂」）
	if GameManager.rng.randf() >= minf(1.0, chance):
		return
	var roll: int = GameManager.rng.randi_range(0, 2)
	match roll:
		0:
			ProcStatus.apply(enemy, true, damage * BalanceChain.WUXING_BURN_RATIO,
				BalanceChain.WUXING_BURN_DUR, 0.0, 0.0, false, 0.0, 0.0)
		1:
			ProcStatus.apply(enemy, false, 0.0, 0.0,
				BalanceChain.WUXING_CHILL, BalanceChain.WUXING_CHILL_DUR, false, 0.0, 0.0)
		_:
			ProcStatus.apply(enemy, false, 0.0, 0.0, 0.0, 0.0,
				true, damage * BalanceChain.WUXING_POISON_RATIO, BalanceChain.WUXING_POISON_DUR)

## 天罚：暴击时在目标头顶劈一道雷（固定基值 + 元素加成，不随武器面板膨胀）
static func _roll_sky_bolt(host: Node, enemy: Node2D, is_crit: bool, enabled: float) -> void:
	if not is_crit or enabled <= 0.0:
		return
	ChainLightning.sky_bolt(host, enemy.global_position,
		BalanceChain.crit_bolt_damage(GameManager.elemental_damage),
		GameStyle.FX_HDR_LIGHTNING)

## 取本帧的机制快照（命中循环外调一次，循环内复用）
static func snapshot() -> Dictionary:
	return StatSystem.super_hook_snapshot(GameManager)

## 近战/横扫/束流命中：五行轮转 / 五行归一 + 天罚
static func on_weapon_hit(host: Node, enemy: Node2D, damage: float, is_crit: bool,
		snap: Dictionary = {}) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var s: Dictionary = snap if not snap.is_empty() else snapshot()
	var guiyi := float(s.get("wuxing_all", 0.0))
	var wuxing := float(s.get("wuxing_rotation_chance", 0.0))
	var bolt := float(s.get("crit_sky_bolt", 0.0))
	if wuxing <= 0.0 and bolt <= 0.0 and guiyi <= 0.0:
		return
	# 归一优先于轮转：两卡同拿时每次命中三系全挂（轮转那条概率腿不再掷，读法更干净）
	if guiyi > 0.0:
		ProcStatus.apply(enemy, true, damage * BalanceChain.GUIYI_BURN_RATIO,
			BalanceChain.WUXING_BURN_DUR,
			BalanceChain.WUXING_CHILL, BalanceChain.WUXING_CHILL_DUR,
			true, damage * BalanceChain.GUIYI_POISON_RATIO, BalanceChain.WUXING_POISON_DUR)
	else:
		_roll_wuxing(enemy, damage, wuxing)
	_roll_sky_bolt(host, enemy, is_crit, bolt)

## 弹丸命中：两条通用效果 + 雷霆弹幕（共鸣卡：弹丸命中时也引发链电）
static func on_projectile_hit(host: Node, enemy: Node2D, damage: float, is_crit: bool,
		snap: Dictionary = {}) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var s: Dictionary = snap if not snap.is_empty() else snapshot()
	on_weapon_hit(host, enemy, damage, is_crit, s)
	if float(s.get("projectile_chain_lightning", 0.0)) > 0.0:
		# 首跳就是这一次命中的实伤（chain_hop_damage(damage, 0) == damage），
		# 之后每跳按 HOP_RATIO 折损 —— 不要在这里再乘一次衰减，否则首跳凭空少 40%。
		ChainLightning.strike(host, enemy.global_position, enemy, damage,
			_chain_hops(s))

## 万剑归宗：近战命中累计到阈值后，在命中点放一道环形剑气。
## charge 由武器侧持有（每把武器独立计数），返回值是「本次结算后的新计数」。
static func tick_sword_qi(host: Node, center: Vector2, damage: float, charge: int,
		snap: Dictionary = {}) -> int:
	var s: Dictionary = snap if not snap.is_empty() else snapshot()
	if float(s.get("sword_qi", 0.0)) <= 0.0:
		return 0
	var next: int = charge + 1
	if next < BalanceChain.SWORD_QI_EVERY:
		return next
	_burst_sword_qi(host, center, BalanceChain.sword_qi_damage(damage))
	return 0

static func _burst_sword_qi(host: Node, center: Vector2, damage: float) -> void:
	if host == null or not is_instance_valid(host) or damage <= 0.0:
		return
	var targets := ChainLightning.collect_in_radius(center, BalanceChain.SWORD_QI_RADIUS)
	for enemy in targets:
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage, Vector2.ZERO, false)
	# 演出（2026-10-25 二阶段加强）：HDR 白金主环 + 放射剑光刻度 + 镜头微顿，
	# 不再借「重器前摇」音效 —— 剑气有自己烘焙的 sword_qi_wave。
	JuiceEffect.spawn_shockwave(host, center, BalanceChain.SWORD_QI_RADIUS,
		GameStyle.FX_HDR_CORE, 0.24)
	JuiceEffect.spawn_radial_slash(host, center, BalanceChain.SWORD_QI_RADIUS)
	GameFeel.micro_kick(GameManager, Vector2.ZERO, 2.0)
	AudioManager.play_sfx("sword_qi_wave", 0.65)

## 反震电场：玩家受击后向周围放电（固定基值 + 有效反震加成）
static func on_player_hurt(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var s := snapshot()
	if float(s.get("thorns_electric", 0.0)) <= 0.0:
		return
	ChainLightning.strike(player, player.global_position, null,
		BalanceChain.thorns_bolt_damage(GameManager.get_effective_thorns()),
		_chain_hops(s), GameStyle.FX_HDR_LIGHTNING)

## 血海护盾破碎：盾被打穿这一刻向周身放一片电（基值 + 生命比例 + 元素加成，BalanceChain）。
## 放电走 ChainLightning（自带事件闸与深度闸），这里是低频大事件，补一记冲击环与震屏。
static func on_shield_broken(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var s := snapshot()
	if float(s.get("lifesteal_overflow_shield", 0.0)) <= 0.0:
		return
	var dmg := BalanceChain.shield_break_damage(player.max_health, GameManager.elemental_damage)
	ChainLightning.strike(player, player.global_position, null, dmg,
		_chain_hops(s), GameStyle.FX_HDR_LIGHTNING)
	JuiceEffect.spawn_shockwave(player.get_parent(), player.global_position,
		BalanceChain.SHIELD_BREAK_RADIUS, GameStyle.FX_HDR_LIGHTNING, 0.22)
	GameManager.feedback(GameManager.FeedbackTier.MEDIUM)
	AudioManager.play_sfx("thunder_strike", 0.8)

## 灵兽直击挂钩（兽群链电 + 灵蕴五行共用入口）：pet 传灵兽节点，鸭类型不标类型。
## 灵兽出手是低频事件（秒级），不调 any_enabled 快闸，直读快照即可。
static func on_pet_hit(pet: Node, enemy: Node2D, damage: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var s := snapshot()
	if float(s.get("pet_chain_lightning", 0.0)) > 0.0 and pet != null and is_instance_valid(pet):
		ChainLightning.strike(pet, enemy.global_position, enemy,
			damage * BalanceChain.PET_CHAIN_RATIO, BalanceChain.PET_CHAIN_HOPS)
	var wuxing := float(s.get("pet_wuxing_chance", 0.0))
	if wuxing > 0.0:
		_roll_wuxing(enemy, damage, wuxing)

## 链电跳数 = 基础跳数 + 天罚的加成
static func _chain_hops(s: Dictionary) -> int:
	return BalanceChain.MAX_HOPS + int(float(s.get("chain_hop_bonus", 0.0)))
