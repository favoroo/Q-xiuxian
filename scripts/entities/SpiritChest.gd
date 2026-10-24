class_name SpiritChest
extends Node2D

## 藏宝匣：竞技场内随机刷新的可破坏宝箱（Brotato 树木的修仙版）
## 挨够 GameBalance.chest_break_hits() 下砸开，掉什么按档位查 BalanceChest.reward_of（三档）：
##   木匣 —— 约四成掉回春葫芦（回 15% 生命），约六成掉 3 颗金币
##   铜匣 —— 同样的葫芦概率但回得更多，掉 6 颗金币
##   玉匣 —— 必送一件随机道具（与金币阁同一个 roller），另有金币；每局送出件数有顶，
##           到顶后退回铜匣奖励 ×1.5（见 BalanceChest.jade_fallback_reward）
## 掉出的葫芦在满血时不会被吃掉，会压在灰相留在原地等玩家掉血（见 HealOrb）
## 持有「纳灵盘」道具时，砸开掉的掉落物当场飞进袖中（残血时葫芦也一同吸附）
## 挂在 4 号层（enemies）让武器判定能碰到；加入 chests 组 = 「可砸但不是威胁」的标记：
## 索敌按两段式走（见 GameBalance.assign_targets_with_chests）—— 场上还有活妖时武器不会
## 甩开妖来砸匣子，只有闲着的武器与多出来的弹道才流向它。
## 耐久按「几下」计而不按生命：伤害数值随星级/属性涨几十倍，若匣子跟着敌方 hp 曲线走，
## 后期会变成打不动的石头或一碰就没，两种都读不出「砸」这个动作。
## 档位（tier）由 WaveSpawner 在 add_child 之前写入：_ready 里造型/体型/击数/配色全读它，
## 挂树后再改 tier 不会重建这些件，所以构造顺序是契约的一部分。

## 剩余击数读数：只在受损后出现，一格一下，从右往左熄灭
class HitPips:
	extends Node2D

	var total: int = 0
	var left: int = 0
	var pip_size: float = 6.0
	var pip_gap: float = 4.0
	## 颜色一律由外层灌进来（GameStyle 是唯一取色入口，这里只留空默认）
	var kept_color: Color = Color(0, 0, 0, 0)
	var spent_color: Color = Color(0, 0, 0, 0)
	var edge_color: Color = Color(0, 0, 0, 0)

	func _draw() -> void:
		# 满匣时不画：还没开打就先摆一排格子，读的是"这是什么"而不是"还剩几"
		if total <= 0 or left >= total:
			return
		var step: float = pip_size + pip_gap
		var width: float = float(total) * step - pip_gap
		var x: float = -width * 0.5
		for i in range(total):
			var rect := Rect2(x + float(i) * step, -pip_size * 0.5, pip_size, pip_size)
			draw_rect(rect, kept_color if i < left else spent_color, true)
			draw_rect(rect.grow(1.0), edge_color, false, 1.0)

const BASE_SCALE := Vector2(34.0 / 96.0, 34.0 / 96.0)
## 体型倍率（2026-10-10 用户口径「敌人和宝箱的大小要大一点」）。
## 判定圆直径 34（局部半径 17），造型按「屏幕宽 == 判定直径」定标：
## ChestVisual 画布 96×87、原点居中（2026-10-18 起程序绘制，与旧 prop_chest.png 同画布口径），
## ×SIZE_MULT 后与判定同涨 —— 视觉与判定同倍放缩（AGENTS.md 铁律 7），PIP_LIFT 跟着走。
const SIZE_MULT := 1.5
## 读数离匣心的高度：产物画布 87 高，×(34/96×1.5) 后上沿在匣心上方约 23px，
## 这条要在它之上 —— 摆在 40×SIZE_MULT=60px，远在匣顶上方，不压画面。
const PIP_LIFT := 40.0 * SIZE_MULT
const JIGGLE_PX := 3.2        ## 受击瞬间造型微反冲位移
const FLASH_MOD := 2.2        ## 受击闪白倍率（modulate 超过 1 即提亮，无需着色器）

## 三档造型（2026-10-18 换程序绘制，几何共用一套、材质配色分档）：
## 木=棕木铁箍、铜=青铜红绸、玉=青玉金箍嵌宝，绘制在 ChestVisual，无贴图依赖；
## 档位之间的体型差由 BalanceChest.TIER_SCALE 同倍乘在绘制与判定圆上（画多大 == 判多大）。
## 耐久格配色分档（取色只从 GameStyle）：木=金币黄、铜=霜金、玉=青碧
const TIER_PIP_COLORS: Array[Color] = [GameStyle.JADE, GameStyle.RARITY_EPIC, GameStyle.RARITY_RARE]

var gem_scene: PackedScene = preload("res://scenes/entities/AstralGem.tscn")

## 与 EnemyBase 同名：ThunderBurst 按 get("dying") 判断这一件是否已结算过
var dying: bool = false
## 档位（0 木 / 1 铜 / 2 玉）：必须在 add_child 之前由 WaveSpawner 写好，_ready 才读得到。
## 默认木匣 —— 直接 new() 出来摆上场的测试与预览工具拿到的就是改版前那口匣子。
var tier: int = BalanceChest.TIER_WOOD
var max_hits: int = GameBalance.CHEST_BREAK_HITS
var remaining_hits: int = GameBalance.CHEST_BREAK_HITS
var _tier_scale: float = 1.0   ## 本档体型倍率（造型与判定圆同乘）

var _visual: ChestVisual
var _pips: HitPips
var _box: Area2D
var _box_shape: CollisionShape2D
var _flash_tw: Tween
var _jiggle_tw: Tween
var _breathe: Tween
var _entrance_tw: Tween

func _ready() -> void:
	add_to_group("chests")

	# 档位先落地成一等公民：击数、体型、贴图、读数配色全部由它派生（曲线见 BalanceChest）
	_tier_scale = GameBalance.chest_tier_scale(tier)
	max_hits = GameBalance.chest_break_hits(GameManager.chest_break_bonus)
	remaining_hits = max_hits

	_box = Area2D.new()
	_box.collision_layer = 4
	_box.collision_mask = 0
	add_child(_box)
	_box_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 17.0 * SIZE_MULT * _tier_scale
	_box_shape.shape = circle
	_box.add_child(_box_shape)

	_visual = ChestVisual.new()
	_visual.tier = tier
	_visual.scale = Vector2.ZERO
	add_child(_visual)

	_pips = HitPips.new()
	_pips.position = Vector2(0.0, -PIP_LIFT * _tier_scale)
	_pips.total = max_hits
	_pips.left = remaining_hits
	_pips.kept_color = TIER_PIP_COLORS[clampi(tier, 0, TIER_PIP_COLORS.size() - 1)]
	_pips.spent_color = GameStyle.NAVY2
	_pips.edge_color = GameStyle.INK
	add_child(_pips)

	# 砸落登场 + 匣内灵气吞吐，两者都落在 SIZE_MULT×档位 这一档体型上。
	# 呼吸必须等登场落定再接手：两条 tween 同写 _visual.scale 时谁后写谁赢。
	var rest := BASE_SCALE * SIZE_MULT * _tier_scale
	_entrance_tw = create_tween()
	_entrance_tw.tween_property(_visual, "scale", rest, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_entrance_tw.tween_callback(_start_breathe)

## 登场落定后才开始吞吐：起幅就是 rest，之后只在 rest 与 rest×1.04 之间摆
func _start_breathe() -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	var rest := BASE_SCALE * SIZE_MULT * _tier_scale
	_breathe = create_tween().set_loops()
	_breathe.tween_property(_visual, "scale", rest * 1.04, 1.1).set_trans(Tween.TRANS_SINE)
	_breathe.tween_property(_visual, "scale", rest, 1.1).set_trans(Tween.TRANS_SINE)

## 受损后的常驻相：微暗微冷，越裂越沉 —— 「这匣子挨过打」的底色，闪白要回到这里而不是纯白
func _resting_modulate() -> Color:
	var dmg := 1.0 - float(remaining_hits) / float(maxi(1, max_hits))
	return Color.WHITE.lerp(Color(0.62, 0.60, 0.72), dmg * 0.55)

## 武器判定命中（与 EnemyBase 同签名，被挥砍/落雷/弹丸/灵蝶波及）
## 只数"打到了几下"：amount 不参与耐久结算，因此匣子既不会被高伤一发秒掉，
## 也不会因为灼烧/剧毒这类 DoT 打不到它而卡死（DoT 走 apply_burn 等方法，匣子没有）。
func take_damage(amount: float, knockback: Vector2, is_crit: bool = false) -> void:
	if dying:
		return
	remaining_hits -= 1
	# 匣子不是威胁，不值得震屏与顿帧：只给"木裂"这一层反馈（高频事件按重要性稀缺发放）
	AudioManager.play_sfx("chest_hit", 0.9)
	_flash()
	_jiggle(knockback)
	_pips.left = remaining_hits
	_pips.queue_redraw()
	if remaining_hits <= 0:
		_destroy()

func _flash() -> void:
	if _flash_tw != null and _flash_tw.is_valid():
		_flash_tw.kill()
	_flash_tw = create_tween()
	_flash_tw.tween_property(_visual, "modulate", Color(FLASH_MOD, FLASH_MOD, FLASH_MOD * 0.9, 1.0), 0.02)
	_flash_tw.tween_property(_visual, "modulate", _resting_modulate(), 0.10)

## 受击微反冲：造型朝击退方向偏一下再回位（匣子本体不位移，位移的是画）
func _jiggle(knockback: Vector2) -> void:
	if _jiggle_tw != null and _jiggle_tw.is_valid():
		_jiggle_tw.kill()
	var dir := knockback.normalized() if knockback.length_squared() > 1.0 else Vector2.UP
	_jiggle_tw = create_tween()
	_jiggle_tw.tween_property(_visual, "position", dir * JIGGLE_PX, 0.045)
	_jiggle_tw.tween_property(_visual, "position", Vector2.ZERO, 0.11).set_trans(Tween.TRANS_SINE)

func _destroy() -> void:
	if dying or is_queued_for_deletion():
		return
	dying = true
	AudioManager.play_sfx("chest_open", 0.9)
	# 破匣爆开演出：碎板飞溅 + 尘环 + 锁牌弹出（纯 _draw 一次性节点，挂在池层原位，
	# 不延后 queue_free —— 匣子多活一拍会撑破「chests」组的计数判据）
	ChestBurstFx.play(get_parent(), global_position, tier, BASE_SCALE * SIZE_MULT * _tier_scale)
	if tier == BalanceChest.TIER_JADE:
		# 玉匣是全场最高档匣子，破开给一次专属镜头语言（青碧金环 + 缩放冲击 + 击杀级轻顿，
		# 全走限流原语，受 display 设置总闸约束）。木/铜保持原样：每回合 2~4 口匣子，全发会把高光糊成常态
		# （「震屏只给特殊场景」口径）。环画在 parent 池层，不延后 queue_free ——
		# 匣子多活一拍会撑破「chests」组的计数判据。
		# 受击侧旧注释「匣子不值得震屏与顿帧」只管逐下锤的木裂反馈，不管破匣这一口高光。
		JuiceEffect.spawn_shockwave(get_parent(), global_position, 72.0, GameStyle.JADE, 0.32)
		GameFeel.zoom_punch(GameManager, 0.05, 0.18)
		GameFeel.kill_hit_stop(GameManager)
	var reward: Dictionary = GameBalance.chest_reward(tier)
	# 玉匣的头奖就是那件道具；每局送满上限后退回铜匣量级，不许空口白牙（口径见 BalanceChest）
	if bool(reward.get("grant_item", false)) and not GameManager.chest_grant_item():
		reward = GameBalance.chest_jade_fallback_reward()
	# 开箱收益乘区：悟道「宝箱掉落」+道具「满匣诀」放大这一口的金币颗数/金币/回复量
	reward = GameBalance.chest_reward_scaled(reward, GameManager.chest_reward_mult)
	var stones := int(reward.get("stones", 0))
	if stones > 0:
		GameManager.add_spirit_stones(stones)
	# 葫芦概率 = 奖励表基准（简单档口径）× 危险度乘区：越难葫芦越稀少
	var heal_chance := float(reward.get("heal_chance", 0.0)) * GameBalance.danger_heal_chance_mult(GameManager.danger_level)
	if GameManager.rng.randf() < heal_chance:
		_drop_heal(float(reward.get("heal_pct", 0.0)))
	else:
		_drop_gems(int(reward.get("gem_count", 0)), int(reward.get("gem_exp", 1)))
	queue_free()

## 回春葫芦：满血时不会被吃掉，压在灰相原地等玩家掉血（这套等待逻辑在 HealOrb 自己手里）
func _drop_heal(pct: float) -> void:
	if pct <= 0.0:
		return
	# 回复珠走对象池（2026-10-11，与宝石同一条路）
	var fruit := HealOrb.acquire_or_new(get_parent())
	fruit.global_position = global_position
	fruit.heal_pct = pct
	fruit.activate()
	var magnet: bool = GameManager.item_hook_sum("chest_magnet") > 0.0
	var player: Node2D = GameManager.player
	if magnet and player != null and is_instance_valid(player):
		fruit.magnet_to(player)

## 一捧金币：撒在匣心周围。持有「纳灵盘」时当场全部飞向玩家 —— 砸匣子不必再绕一趟走位
func _drop_gems(count: int, exp_each: int) -> void:
	var magnet: bool = GameManager.item_hook_sum("chest_magnet") > 0.0
	var player: Node2D = GameManager.player
	for i in range(count):
		# 宝石走对象池（2026-10-10 第 6 波卡顿优化）
		var gem := AstralGem.acquire_or_new(gem_scene, get_tree().current_scene)
		gem.global_position = global_position + Vector2(
			GameManager.rng.randf_range(-20.0, 20.0), GameManager.rng.randf_range(-20.0, 20.0))
		gem.is_gold = true
		gem.exp_value = exp_each
		gem.activate()
		if magnet and player != null and is_instance_valid(player):
			gem.magnet_to(player)

## 回合末还没砸开的匣子随余怪一起消散（不掉落）—— 与 EnemyBase.dissolve 同一口径。
## 每回合重刷 2~4 只，留着不收会把场地堆成箱子阵；而"要不要为它多花几发"本来就是这只匣子的玩法。
func dissolve() -> void:
	if dying:
		return
	dying = true
	if _entrance_tw != null and _entrance_tw.is_valid():
		_entrance_tw.kill()
	if _breathe != null and _breathe.is_valid():
		_breathe.kill()
	if _flash_tw != null and _flash_tw.is_valid():
		_flash_tw.kill()
	if _jiggle_tw != null and _jiggle_tw.is_valid():
		_jiggle_tw.kill()
	_box_shape.set_deferred("disabled", true)
	_pips.visible = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_visual, "modulate:a", 0.0, 0.4)
	tw.tween_property(_visual, "scale", _visual.scale * 0.6, 0.4)
	tw.chain().tween_callback(queue_free)
