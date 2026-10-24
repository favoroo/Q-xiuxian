class_name CombatPrewarm
extends RefCounted

## 战斗前资源预热（2026-10-21 启动卡顿专项）
##
## 问题：项目原先完全没有预加载/池预热（全项目搜不到 load_threaded_request / prewarm）。
## 开局第一波怪必然走 scene.instantiate() + 程序化外观全套装配（ProceduralEnemyView +
## HollowKnightEnemyRenderer + config），首次敌人死亡/首次火焰才编译 dissolve/heat_distort
## shader —— 这些首次成本集中砸在开局头几秒，表现为「刚开打卡一下」。
##
## 做法：在「选完武器 → 战斗正式开打」之间，用一次性的预热把最重的一次性成本提前付掉：
##   1) 敌人对象池：每种早期怪预建 N 只入池（instantiate 走 EnemyBase.acquire_or_new，
##      出厂快照当刻拍好）。死亡回收时自然复用，不再 new。
##   2) 弹丸池：预建若干 BladeProjectile 停泊在池宿主下，首发射击不再 instantiate。
##   3) shader 预热：dissolve / heat_distort 提前 load（同步编译发生在此刻，而非首次死亡）。
##
## 分帧驱动：每次 step() 处理「一个种类」或「弹丸批」或「shader」这一整步，单步只付
## 一小块成本，避免预热自己造成一次尖刺。移动端（OS.has_feature("mobile")）数量减半。
##
## 注意（踩坑记）：预热必须「批量 acquire → 逐个 add_child → 统一 recycle」。
## 若逐个 acquire→recycle 循环，acquire_or_new 每轮都会把上一步回池的那只又借出来，
## 池里永远只攒得下 1 只（PrewarmCheck 抓到过）。批量 acquire 才能让池真正积累 N 只。

const WARM_ENEMY_MIN := 1     ## 每种怪预热下限（移动端）
const WARM_ENEMY_MAX := 2     ## 每种怪预热上限（桌面）
const WARM_PROJECTILES := 6   ## 预建弹丸数（桌面；移动端减半）

## 早期出场怪（前几波会刷的：slime 永远出场，xiexiu/leibeast/flower 前几波陆续登场）
const EARLY_MOB_KEYS: Array = ["slime", "xiexiu", "leibeast", "flower"]

var _enemy_scenes: Array[PackedScene] = []
var _enemies_per_kind: int = WARM_ENEMY_MAX
var _proj_budget: int = WARM_PROJECTILES
var _projectile_scene: PackedScene = null
var _parent: Node = null

var _cursor: int = 0          ## 进度游标：0=shader，1=弹丸批，2..=各怪种
var _finished: bool = false
var _half: bool = false

func _init(parent: Node) -> void:
	_parent = parent
	_half = OS.has_feature("mobile")
	_enemies_per_kind = WARM_ENEMY_MIN if _half else WARM_ENEMY_MAX
	_proj_budget = int(WARM_PROJECTILES * 0.5) if _half else WARM_PROJECTILES
	# 收集早期怪种场景（沿用 EnemyData 权威表，不另抄路径）
	for key in EARLY_MOB_KEYS:
		var row: Dictionary = EnemyData.MOBS.get(key, {})
		var sp := String(row.get("scene_path", ""))
		if not sp.is_empty() and ResourceLoader.exists(sp):
			var packed := load(sp) as PackedScene
			if packed == null:
				# exists 过了但 as 转换失败 = 循环依赖把 PackedScene 打成空（坑 12 同源），预热会静默失效
				push_warning("CombatPrewarm: 怪种 %s 场景加载为空：%s" % [key, sp])
				continue
			_enemy_scenes.append(packed)
	_projectile_scene = load("res://scenes/weapons/BladeProjectile.tscn") as PackedScene
	if _projectile_scene == null:
		push_warning("CombatPrewarm: BladeProjectile.tscn 加载为空（多为循环类依赖），弹丸预热失效")

## 总步数（shader 1 + 弹丸批 1 + 每种怪 1）
func total_steps() -> int:
	return 2 + _enemy_scenes.size()

func is_finished() -> bool:
	return _finished

## 推进一小步。返回 true 表示还有剩余步骤。
func step() -> bool:
	if _finished:
		return false
	match _cursor:
		0:
			_pwarm_shaders()
		1:
			_pwarm_projectiles()
		_:
			var idx := _cursor - 2
			if idx < _enemy_scenes.size():
				_pwarm_one_kind(_enemy_scenes[idx])
	_cursor += 1
	if _cursor > total_steps() - 1:
		_finished = true
	return not _finished

## 同步把剩余全部步骤跑完（用于没有分帧窗口的路径，如判据）。
func run_all() -> void:
	var guard := 0
	while not _finished and guard < 10000:
		step()
		guard += 1

# ---------------- 内部实现 ----------------

func _pwarm_shaders() -> void:
	# load 一瞬触发 shader 同步编译（Godot canvas_item shader 不进磁盘 shader cache），
	# 提前付掉「首次敌人死亡 / 首次火焰」的编译卡顿。
	if ResourceLoader.exists("res://assets/shaders/dissolve.gdshader"):
		load("res://assets/shaders/dissolve.gdshader")
	if ResourceLoader.exists("res://assets/shaders/heat_distort.gdshader"):
		load("res://assets/shaders/heat_distort.gdshader")

## 批量预建弹丸：先全部 acquire 出来（此时池空，逐只 instantiate），再统一回池。
func _pwarm_projectiles() -> void:
	if _projectile_scene == null or _parent == null:
		return
	var batch: Array = []
	for i in range(_proj_budget):
		var p := BladeProjectile.acquire_or_new(_projectile_scene, _parent)
		if p == null:
			break
		batch.append(p)
	# 统一回池：activate → _recycle 完整生命周期（activate 复位 _pooled 并登记，_recycle 整备回池）
	for p in batch:
		if is_instance_valid(p):
			p.activate()
			p._recycle()

## 批量预建一个怪种：先全部 acquire 出来（池空则 instantiate 触发 _ready 装配），
## 逐个 add_child 让 _ready 装配跑完，最后统一 _recycle 回池。
func _pwarm_one_kind(scene: PackedScene) -> void:
	if scene == null or _parent == null:
		return
	var batch: Array[EnemyBase] = []
	for i in range(_enemies_per_kind):
		var e := EnemyBase.acquire_or_new(scene)
		if e == null:
			continue
		batch.append(e)
	for e in batch:
		if is_instance_valid(e):
			# add_child → _enter_tree 登记 + _ready 一次性装配（视图/renderer/config）→ activate()
			_parent.add_child(e)
	for e in batch:
		if is_instance_valid(e):
			# _recycle：_exit_tree 注销登记、退 enemies 组、停表、回池（三件套同拍）
			EnemyBase._recycle(e)
