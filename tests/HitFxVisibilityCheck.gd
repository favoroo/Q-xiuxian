extends Node

## 命中特效「视口兜底」判据（2026-10-11，用户口径：「必须要有敌人才会有这个特效，
## 即使敌人隐形了（屏上看不见）也不能有这个特效」）。
##
## 凭空白色刀光的四个口子（前三个在别的判据/本次修复里钉）：
##   ① 屏外藏宝匣被法器锁定打击，SpiritChest.take_damage 发火花无屏外门控；
##   ② 落雷电柱从屏内器口一路画到屏外落点，屏内段=凭空一道白光（WeaponAimCheck 未覆盖，
##      由 FloatingWeapon._spawn_lightning 的 is_in_viewport 门控修）；
##   ③ 近战月牙只看命中数，扫中屏外边缘目标时亮在屏内（WeaponAimCheck 第 4 条补段钉死）；
##   ④ EnemyBase._offscreen 是 10Hz 采样（最多 100ms 陈旧）+ 64px 边缘带，拦不住刚出屏的。
## 本次修复 = JuiceEffect.spawn_hit_sparks / spawn_death_burst 与 DamageNumber.spawn
## 三处入口用实时画布变换做视口终审：位置不在可见矩形内（收 8px 防边缘露半截）一律不生成。
##
## 本判据不建真实敌人/匣子（场景依赖重），直接打三个入口本身，断言：
##   - 屏内位置照常生成（门控不许误杀正常反馈）；
##   - 屏外位置一律不生成（四个口子的公共兜底成立）；
##   - 拾取流光不吃门控（跟随玩家拾取，永远屏内，口径独立）；
##   - 放完后全部归池，无节点泄漏。
##
## 运行: godot --headless --path . res://tests/HitFxVisibilityCheck.tscn
## 反例（判据的牙齿，改动后跑本场景必须报红）：
##   ① 把 JuiceEffect._pos_in_viewport 整体改成 return true ⇒ 屏外/贴边火花与屏外爆散报红；
##   ② 只把 grow(-8.0) 放宽成 grow(8.0) ⇒ 贴边 4px 条报红（收边口径松了 16px）；
##   ③ 把 DamageNumber.spawn 的视口兜底删掉 ⇒ 屏外跳字条报红。

var _c := TestCheck.new()
var _world: Node2D

func _ready() -> void:
	GameManager.reset_run()
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	call_deferred("_run")

func _run() -> void:
	var rect := get_viewport().get_visible_rect()
	var inside := rect.get_center()
	# 测试场景无相机 ⇒ 画布变换恒等，visible_rect 即世界可见范围；取矩形外右下方一点
	var outside := rect.position + rect.size + Vector2(220.0, 180.0)

	# —— 受击火花（白色斩痕+扇形火花，截图里「凭空刀光」的本体）——
	_c.equals(_visible_count("JuiceEffectPool"), 0, "开场池内无可见特效")
	JuiceEffect.spawn_hit_sparks(_world, inside, Vector2.RIGHT, false)
	_c.equals(_visible_count("JuiceEffectPool"), 1, "屏内命中火花照常生成（门控不误杀）")
	JuiceEffect.spawn_hit_sparks(_world, outside, Vector2.RIGHT, false)
	_c.equals(_visible_count("JuiceEffectPool"), 1, "屏外位置发火花不生成（匣子/敌人屏外命中的公共兜底）")
	# 贴边带：中心落在可见矩形内 4px 的也不生成（收 8px 防火花半径在边缘露半截；同时钉住收边口径）
	var edge := rect.position + Vector2(4.0, 4.0)
	JuiceEffect.spawn_hit_sparks(_world, edge, Vector2.RIGHT, false)
	_c.equals(_visible_count("JuiceEffectPool"), 1, "贴边 4px 内的火花不生成（grow(-8) 收边口径有牙齿）")
	JuiceEffect.spawn_hit_sparks(_world, inside, Vector2.RIGHT, true)
	_c.equals(_visible_count("JuiceEffectPool"), 2, "屏内暴击火花照常生成")

	# —— 死亡爆散：尸体塌缩 0.14s 就没、爆散要放 0.4s，屏外击杀的爆散最像「空地凭空特效」——
	JuiceEffect.spawn_death_burst(_world, inside, false, 0.0, false)
	_c.equals(_visible_count("JuiceEffectPool"), 3, "屏内死亡爆散照常生成")
	JuiceEffect.spawn_death_burst(_world, outside, true, 1.2, true)
	_c.equals(_visible_count("JuiceEffectPool"), 3, "屏外死亡爆散不生成（精英/暴击斩杀同口径）")

	# —— 跳字：截图里无敌人处的「52!」——调用方 _offscreen 的陈旧窗口由入口终审补上——
	if bool(SettingsManager.get_val(&"display", &"damage_numbers", true)):
		var before := _visible_count("DamageNumberPool")
		DamageNumber.spawn(_world, inside, 52, true)
		var after_in := _visible_count("DamageNumberPool")
		DamageNumber.spawn(_world, outside, 52, true)
		_c.check(after_in == before + 1, "屏内跳字照常生成")
		_c.check(_visible_count("DamageNumberPool") == after_in, "屏外跳字不生成（凭空数字口子封死）")
	else:
		_c.equals(_visible_count("DamageNumberPool"), 0, "跳字显示关闭时一律不生成（设置口径优先）")

	# —— 拾取流光不吃门控：跟随玩家拾取（宝石/回复珠必须在玩家脚边拿），永远屏内 ——
	JuiceEffect.spawn_pickup_pop(_world, outside, true)
	_c.equals(_visible_count("JuiceEffectPool"), 4, "拾取流光不吃视口门控（口径独立于命中/爆散两类）")

	# —— 放完归池：火花 0.28s / 爆散 0.45s / 跳字 0.9s，1.2s 后必须全部休眠 ——
	await get_tree().create_timer(1.2).timeout
	_c.equals(_visible_count("JuiceEffectPool"), 0, "1.2s 后特效全部归池（无节点泄漏）")
	_c.equals(_visible_count("DamageNumberPool"), 0, "1.2s 后跳字全部归池（无节点泄漏）")

	if _c.report("HITFXVISIBILITY_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## 按宿主名找池，数 visible==true 的在用节点（_begin/_start 置 true，_release 置回 false）；
## 宿主尚未创建（一次都没 spawn 过）按 0 计
func _visible_count(pool_name: String) -> int:
	var pool := get_tree().root.find_child(pool_name, true, false)
	if pool == null:
		return 0
	var n := 0
	for child in pool.get_children():
		if child is Node2D and child.visible:
			n += 1
	return n
