class_name SpiritChest
extends Node2D

## 藏宝匣：竞技场内随机刷新的可破坏宝箱（Brotato 树木的修仙版）
## 挨够 GameBalance.CHEST_BREAK_HITS 下砸开：60% 掉回春葫芦（回 15% 气血），40% 掉 3 颗金灵石
## 掉出的葫芦在满血时不会被吃掉，会压在灰相留在原地等玩家掉血（见 HealOrb）
## 挂在 4 号层（enemies）让武器判定能碰到；加入 chests 组 = 「可砸但不是威胁」的标记：
## 索敌按两段式走（见 GameBalance.assign_targets_with_chests）—— 场上还有活妖时法器不会
## 甩开妖来砸匣子，只有闲着的法器与多出来的弹道才流向它。
## 耐久按「几下」计而不按血量：伤害数值随星级/属性涨几十倍，若匣子跟着敌方 hp 曲线走，
## 后期会变成打不动的石头或一碰就没，两种都读不出「砸」这个动作。

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

const BASE_SCALE := Vector2(0.5, 0.5)
## 读数离匣心的高度：prop_chest.png 画布 128×124 铺满不透明像素，×0.5 后上沿在匣心上方 31px，
## 这条要在它之上（量出来的，不是估的）—— 摆在 26 会正正压在匣盖上，等于没有。
const PIP_LIFT := 40.0
const JIGGLE_PX := 3.2        ## 受击瞬间精灵微反冲位移
const FLASH_MOD := 2.2        ## 受击闪白倍率（modulate 超过 1 即提亮，无需着色器）

var gem_scene: PackedScene = preload("res://scenes/entities/AstralGem.tscn")
var gold_gem_tex: Texture2D = preload("res://assets/art/gem_gold.png")

## 与 EnemyBase 同名：ThunderBurst 按 get("dying") 判断这一件是否已结算过
var dying: bool = false
var max_hits: int = GameBalance.CHEST_BREAK_HITS
var remaining_hits: int = GameBalance.CHEST_BREAK_HITS

var _sprite: Sprite2D
var _pips: HitPips
var _box: Area2D
var _box_shape: CollisionShape2D
var _flash_tw: Tween
var _jiggle_tw: Tween
var _breathe: Tween

func _ready() -> void:
	add_to_group("chests")

	_box = Area2D.new()
	_box.collision_layer = 4
	_box.collision_mask = 0
	add_child(_box)
	_box_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 17.0
	_box_shape.shape = circle
	_box.add_child(_box_shape)

	_sprite = Sprite2D.new()
	_sprite.texture = preload("res://assets/art/prop_chest.png")
	_sprite.scale = Vector2.ZERO
	add_child(_sprite)

	_pips = HitPips.new()
	_pips.position = Vector2(0.0, -PIP_LIFT)
	_pips.total = max_hits
	_pips.left = remaining_hits
	_pips.kept_color = GameStyle.JADE
	_pips.spent_color = GameStyle.NAVY2
	_pips.edge_color = GameStyle.INK
	add_child(_pips)

	# 砸落登场 + 匣内灵气吞吐
	var tw := create_tween()
	tw.tween_property(_sprite, "scale", BASE_SCALE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_breathe = create_tween().set_loops()
	_breathe.tween_property(_sprite, "scale", BASE_SCALE * 1.04, 1.1).set_trans(Tween.TRANS_SINE)
	_breathe.tween_property(_sprite, "scale", BASE_SCALE, 1.1).set_trans(Tween.TRANS_SINE)

## 武器判定命中（与 EnemyBase 同签名，被挥砍/落雷/弹丸/灵蝶波及）
## 只数"打到了几下"：amount 不参与耐久结算，因此匣子既不会被高伤一发秒掉，
## 也不会因为灼烧/剧毒这类 DoT 打不到它而卡死（DoT 走 apply_burn 等方法，匣子没有）。
func take_damage(amount: float, knockback: Vector2, is_crit: bool = false) -> void:
	if dying:
		return
	remaining_hits -= 1
	# 匣子不是威胁，不值得震屏与顿帧：只给"木裂"这一层反馈（高频事件按重要性稀缺发放）
	AudioManager.play_sfx("enemy_hit", 0.85, randf_range(1.22, 1.40))
	JuiceEffect.spawn_hit_sparks(get_parent(), global_position, knockback, is_crit)
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
	_flash_tw.tween_property(_sprite, "modulate", Color(FLASH_MOD, FLASH_MOD, FLASH_MOD * 0.9, 1.0), 0.02)
	_flash_tw.tween_property(_sprite, "modulate", Color.WHITE, 0.10)

## 受击微反冲：精灵朝击退方向偏一下再回位（匣子本体不位移，位移的是画）
func _jiggle(knockback: Vector2) -> void:
	if _jiggle_tw != null and _jiggle_tw.is_valid():
		_jiggle_tw.kill()
	var dir := knockback.normalized() if knockback.length_squared() > 1.0 else Vector2.UP
	_jiggle_tw = create_tween()
	_jiggle_tw.tween_property(_sprite, "position", dir * JIGGLE_PX, 0.045)
	_jiggle_tw.tween_property(_sprite, "position", Vector2.ZERO, 0.11).set_trans(Tween.TRANS_SINE)

func _destroy() -> void:
	if dying or is_queued_for_deletion():
		return
	dying = true
	JuiceEffect.spawn_death_burst(get_parent(), global_position, false)
	AudioManager.play_sfx("gem_pickup", 0.8)
	if GameManager.rng.randf() < 0.6:
		var fruit := HealOrb.new()
		fruit.global_position = global_position
		fruit.heal_pct = 0.15
		get_parent().call_deferred("add_child", fruit)
	else:
		for i in range(3):
			var gem := gem_scene.instantiate() as AstralGem
			gem.global_position = global_position + Vector2(
				GameManager.rng.randf_range(-20.0, 20.0), GameManager.rng.randf_range(-20.0, 20.0))
			gem.is_gold = true
			gem.exp_value = 5
			gem.get_node("Sprite2D").texture = gold_gem_tex
			gem.get_node("PointLight2D").color = Color(1.0, 0.82, 0.35)
			get_parent().call_deferred("add_child", gem)
	queue_free()

## 波末还没砸开的匣子随余怪一起消散（不掉落）—— 与 EnemyBase.dissolve 同一口径。
## 每波重刷 2~4 只，留着不收会把场地堆成箱子阵；而"要不要为它多花几发"本来就是这只匣子的玩法。
func dissolve() -> void:
	if dying:
		return
	dying = true
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
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.4)
	tw.tween_property(_sprite, "scale", _sprite.scale * 0.6, 0.4)
	tw.chain().tween_callback(queue_free)
