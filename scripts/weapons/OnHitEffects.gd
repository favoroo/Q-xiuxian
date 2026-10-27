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
		or float(snap.get("attack_chain_lightning", 0.0)) > 0.0
	return _memo_any

## 供测试/新开局重置记忆
static func reset_memo() -> void:
	_memo_stamp = -1
	_memo_any = false
	_fast_frame = -1
	_fast_any = false
	_zidian_hit_count = 0

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
			_proc_pop(enemy, 0)
		1:
			ProcStatus.apply(enemy, false, 0.0, 0.0,
				BalanceChain.WUXING_CHILL, BalanceChain.WUXING_CHILL_DUR, false, 0.0, 0.0)
			_proc_pop(enemy, 1)
		_:
			ProcStatus.apply(enemy, false, 0.0, 0.0, 0.0, 0.0,
				true, damage * BalanceChain.WUXING_POISON_RATIO, BalanceChain.WUXING_POISON_DUR)
			_proc_pop(enemy, 2)

## 异常施加瞬间的元素爆发（2026-10-26）：旧写法只在敌人身上留一层淡淡染色，
## 而染色优先级是「冰缓 > 灼烧 > 剧毒」——五行归一三系同挂时玩家永远只看到蓝色。
## 这里在**施加这一刻**放一簇对应元素色的粒子，让「刚刚挂上了什么」有一次性、可分辨的读数。
## 索引：0=灼烧 1=冰缓 2=剧毒。
##
## 为什么走 bypass_budget + 本地帧闸：续发粒子的 FRAME_BUDGET_STATUS_AURA 只有 2/帧，
## 施加瞬间若也挤那条闸，多目标命中时几乎全部被吞（正是要治的「看不见」）。
## 但完全放开会让高频命中把 24 个发射器全抢走（抢占最旧的 = 抢掉死亡爆散/命中火花），
## 所以这里自持一道 PROC_POP_FRAME_BUDGET 的独立闸，与续发粒子互不挤占、总量仍封顶。
const PROC_POP_FRAME_BUDGET := 3
static var _proc_pop_frame: int = -1
static var _proc_pop_count: int = 0

static func _proc_pop(enemy: Object, kind: int) -> void:
	var node := enemy as Node2D
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var frame: int = Engine.get_physics_frames()
	if frame != _proc_pop_frame:
		_proc_pop_frame = frame
		_proc_pop_count = 0
	if _proc_pop_count >= PROC_POP_FRAME_BUDGET:
		return
	_proc_pop_count += 1
	var pos := node.global_position + Vector2(0.0, -10.0)
	match kind:
		0:
			FxParticlePool.burst(FxParticlePool.BURN_AURA, pos, "fire", 1.6, true)
		1:
			FxParticlePool.burst(FxParticlePool.CHILL_AURA, pos, "water", 1.6, true)
		_:
			FxParticlePool.burst(FxParticlePool.POISON_AURA, pos, "poison", 1.6, true)

## 五行归一的三色齐上：同一帧发三簇会挤在同一个点上糊成一坨白，
## 这里按 PROC_POP_STAGGER 秒依次补发，读得出「火 → 冰 → 毒」三下。
const PROC_POP_STAGGER := 0.045

static func _proc_pop_staggered(enemy: Object) -> void:
	var node := enemy as Node2D
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	_proc_pop(node, 0)
	var tree := node.get_tree()
	if tree == null:
		return
	for kind in [1, 2]:
		var delay: float = PROC_POP_STAGGER * float(kind)
		tree.create_timer(delay).timeout.connect(func() -> void:
			if node == null or not is_instance_valid(node):
				return
			_proc_pop(node, kind))

## 紫电命中充能计数（类似电刀：命中积累充能，每 CHAIN_EVERY_ATTACKS 次爆发）
static var _zidian_hit_count: int = 0

## 天罚：暴击时在目标头顶劈一道天雷（固定基值 + 元素加成，不随武器面板膨胀）
## 2026-10-26 重构：直接传入 enemy 节点，天雷自苍穹直劈受击目标天灵盖，伤害精准必中，画面干净利落。
static func _roll_sky_bolt(host: Node, enemy: Node2D, is_crit: bool, enabled: float) -> void:
	if not is_crit or enabled <= 0.0:
		return
	ChainLightning.sky_bolt(host, enemy,
		BalanceChain.crit_bolt_damage(GameManager.elemental_damage),
		GameStyle.FX_HDR_LIGHTNING, &"tianfa")

## 紫电：攻击命中敌人时积累充能，到期以被击中的敌人为源头释放连锁闪电（英雄联盟电刀模式）
## 绝不从玩家身上起跳，玩家身上绝不爆闪，连线只在怪与怪之间传导。
static func _roll_zidian(host: Node, enemy: Node2D, damage: float, s: Dictionary) -> void:
	if float(s.get("attack_chain_lightning", 0.0)) <= 0.0:
		_zidian_hit_count = 0
		return
	_zidian_hit_count += 1
	if _zidian_hit_count < BalanceChain.CHAIN_EVERY_ATTACKS:
		return
	_zidian_hit_count = 0
	var hops := _chain_hops(s)
	# 以被命中的 enemy 为起点和首跳目标，电弧直接从该敌人向周围敌人弹射
	ChainLightning.strike(host, enemy.global_position, enemy, damage, hops,
		GameStyle.FX_HDR_ZIDIAN, &"zidian", "chain_zap")

## 取本帧的机制快照（命中循环外调一次，循环内复用）
static func snapshot() -> Dictionary:
	return StatSystem.super_hook_snapshot(GameManager)

## 近战/横扫/束流命中：五行轮转 / 五行归一 + 天罚 + 紫电
static func on_weapon_hit(host: Node, enemy: Node2D, damage: float, is_crit: bool,
		snap: Dictionary = {}) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var s: Dictionary = snap if not snap.is_empty() else snapshot()
	var guiyi := float(s.get("wuxing_all", 0.0))
	var wuxing := float(s.get("wuxing_rotation_chance", 0.0))
	var bolt := float(s.get("crit_sky_bolt", 0.0))
	var zidian := float(s.get("attack_chain_lightning", 0.0))
	if wuxing <= 0.0 and bolt <= 0.0 and guiyi <= 0.0 and zidian <= 0.0:
		return
	# 归一优先于轮转：两卡同拿时每次命中三系全挂
	if guiyi > 0.0:
		ProcStatus.apply(enemy, true, damage * BalanceChain.GUIYI_BURN_RATIO,
			BalanceChain.WUXING_BURN_DUR,
			BalanceChain.WUXING_CHILL, BalanceChain.WUXING_CHILL_DUR,
			true, damage * BalanceChain.GUIYI_POISON_RATIO, BalanceChain.WUXING_POISON_DUR)
		_proc_pop_staggered(enemy)
	else:
		_roll_wuxing(enemy, damage, wuxing)
	_roll_sky_bolt(host, enemy, is_crit, bolt)
	_roll_zidian(host, enemy, damage, s)

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
		# 染色走 ★4 电光青（箭道共鸣的身份色），与紫电紫罗兰分开读。
		ChainLightning.strike(host, enemy.global_position, enemy, damage,
			_chain_hops(s), GameStyle.FX_HDR_STAR4_CYAN, &"danmu", "chain_zap")

## 万剑归宗已改判（2026-10-26）：不再走「命中后效果」这条路 —— 旧实现是每 3 次近战命中
## 在命中点放一圈 150px 冲击波（玩家读不出打了谁、打了多少，也没有「万剑」的意象），
## 现换成 SwordPhantom 幻影剑阵齐射（出手攒剑意 → 全体剑器各幻化一道齐射）。
## 因此本文件不再有 tick_sword_qi / _burst_sword_qi，剑意计数也不在武器身上。

## 反震电场：玩家受击后向周围放电（固定基值 + 有效反震加成）
## 2026-10-26 演出重做：改用 BalanceChain.THORNS_RADIUS（旧写法让这个常量成了死值，
## 实际走的是链电通用 240px），并补一道同半径的冰蓝冲击环 —— 画多大 == 判多大，
## 玩家一眼能看出「反震圈到哪」。染色走水系灵蓝，与紫电/雷劫/天罚彻底分开。
## 2026-10-27 电刀化：玩家身上只有原地爆闪（起跳锚点），传导弧由 strike 锁最近敌起跳、
## 只画敌人↔敌人之间 —— 旧写法从玩家坐标画一条入站长线，玩家看到的是「空气里的电」。
static func on_player_hurt(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var s := snapshot()
	if float(s.get("thorns_electric", 0.0)) <= 0.0:
		return
	var tint := GameStyle.FX_HDR_WATER
	ChainLightning.strike(player, player.global_position, null,
		BalanceChain.thorns_bolt_damage(GameManager.get_effective_thorns()),
		_chain_hops(s), tint, &"fanzhen", "chain_zap", BalanceChain.THORNS_RADIUS)
	# 同源环：半径就是反震的搜索半径，与判定一字不差
	JuiceEffect.spawn_shockwave(player.get_parent(), player.global_position,
		BalanceChain.THORNS_RADIUS, tint, 0.20)
	JuiceEffect.spawn_bolt_pop(player, player.global_position, tint)

## 血海护盾破碎：盾被打穿这一刻向周身放一片电（基值 + 生命比例 + 元素加成，BalanceChain）。
## 2026-10-26 演出重做：血红染色 + 同半径冲击环 + 四向短弧 nova，
## 读起来是「血盾炸开」而不是又一道普通白雷。
## 2026-10-27 电刀化：四向短弧 nova 已随全局电刀化下线（那是不带敌人的空气弧）；
## 破盾点只留爆闪 + 冲击环，传导弧由 strike 自动锁最近敌起跳、只在敌人之间。
static func on_shield_broken(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var s := snapshot()
	if float(s.get("lifesteal_overflow_shield", 0.0)) <= 0.0:
		return
	var dmg := BalanceChain.shield_break_damage(player.max_health, GameManager.elemental_damage)
	var tint := GameStyle.FX_HDR_XUEHAI
	ChainLightning.strike(player, player.global_position, null, dmg,
		_chain_hops(s), tint, &"xuehai", "chain_zap", BalanceChain.SHIELD_BREAK_RADIUS)
	JuiceEffect.spawn_shockwave(player.get_parent(), player.global_position,
		BalanceChain.SHIELD_BREAK_RADIUS, tint, 0.22)
	JuiceEffect.spawn_bolt_pop(player, player.global_position, tint)
	GameManager.feedback(GameManager.FeedbackTier.MEDIUM)
	AudioManager.play_sfx("thunder_strike", 0.9)

## 灵兽直击挂钩（兽群链电 + 灵蕴五行共用入口）：pet 传灵兽节点，鸭类型不标类型。
## 灵兽出手是低频事件（秒级），不调 any_enabled 快闸，直读快照即可。
static func on_pet_hit(pet: Node, enemy: Node2D, damage: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var s := snapshot()
	if float(s.get("pet_chain_lightning", 0.0)) > 0.0 and pet != null and is_instance_valid(pet):
		# 染色走木系青碧（灵兽的身份色），与玩家侧紫电/雷劫分开；音量压到 0.35，
		# 免得跟灵兽自己的技能音抢（雷灵雀的连锁神雷也播 thunder_strike）。
		ChainLightning.strike(pet, enemy.global_position, enemy,
			damage * BalanceChain.PET_CHAIN_RATIO, BalanceChain.PET_CHAIN_HOPS,
			GameStyle.FX_HDR_WOOD, &"shouqun", "chain_zap")
	var wuxing := float(s.get("pet_wuxing_chance", 0.0))
	if wuxing > 0.0:
		_roll_wuxing(enemy, damage, wuxing)

## 链电跳数 = 基础跳数 + 天罚的加成
static func _chain_hops(s: Dictionary) -> int:
	return BalanceChain.MAX_HOPS + int(float(s.get("chain_hop_bonus", 0.0)))
