class_name Player
extends CharacterBody2D

@export var max_health: float = 120.0
var current_health: float = 120.0
var base_speed: float = 210.0
var invulnerable_time: float = 0.0

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var sun_orb_container: Node2D = $SunOrbContainer
@onready var weapon_holder: Node2D = $WeaponHolder
@onready var pickup_area: Area2D = $PickupArea
@onready var hit_flash_mat: ShaderMaterial = anim_sprite.material as ShaderMaterial

var sun_orb_angle: float = 0.0
var idle_bob_phase: float = 0.0
var facing: String = "s"  # 当前朝向（5 基准方向后缀，左系由 flip_h 表达）
var anim_base_scale: Vector2 = Vector2.ONE
var regen_tick: float = 0.0
var flash_tween: Tween = null
var floating_weapon_scene: PackedScene = preload("res://scenes/weapons/FloatingWeapon.tscn")
var sun_orb_scene: PackedScene = preload("res://scenes/weapons/SunOrb.tscn")

func _ready() -> void:
    current_health = max_health
    GameManager.player = self
    GameManager.player_hp_changed.emit(current_health, max_health)
    _setup_sprite_frames()
    anim_base_scale = anim_sprite.scale
    sync_drones()

func _setup_sprite_frames() -> void:
    var base_tex = load("res://assets/art/pawn_blue_8dir.png") as Texture2D
    var sf = SpriteFrames.new()
    # 5 个基准方向（左/左下/左上由 flip_h 补齐）：idle_<dir> 单帧 + run_<dir> 4 帧
    for dir in RunMotion.DIR_ROW:
        var row: int = RunMotion.DIR_ROW[dir]
        sf.add_animation("idle_" + dir)
        sf.set_animation_speed("idle_" + dir, 1.0)
        sf.set_animation_loop("idle_" + dir, true)
        sf.add_frame("idle_" + dir, _cell_tex(base_tex, 0, row))

        sf.add_animation("run_" + dir)
        sf.set_animation_speed("run_" + dir, 8.0)
        sf.set_animation_loop("run_" + dir, true)
        for c in range(1, 5):
            sf.add_frame("run_" + dir, _cell_tex(base_tex, c, row))

    anim_sprite.sprite_frames = sf
    anim_sprite.play("idle_s")

func _cell_tex(tex: Texture2D, col: int, row: int) -> AtlasTexture:
    var at = AtlasTexture.new()
    at.atlas = tex
    at.region = Rect2(col * 192, row * 192, 192, 192)
    return at

# ---------------- 武器管理 ----------------

## 开局不再默认给武器：由开局选器界面通过 GameManager.start_run 发放

func add_weapon_instance(def_id: String, star: int) -> void:
    var weapon = floating_weapon_scene.instantiate() as FloatingWeapon
    weapon.setup(def_id, star)
    weapon_holder.add_child(weapon)
    _recalculate_weapon_slots()

## 手动合成：保留的悬浮法器原地升星并播放强化动效
func upgrade_weapon_instance(node: Node, new_star: int) -> void:
    if node == null or not is_instance_valid(node) or not (node is FloatingWeapon):
        return
    var w := node as FloatingWeapon
    w.setup(w.weapon_def_id, new_star)
    var tw := create_tween()
    tw.tween_property(w, "scale", Vector2(1.45, 1.45), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.tween_property(w, "scale", Vector2.ONE, 0.14)

func remove_weapon_instance(node: Node) -> void:
    if node != null and is_instance_valid(node):
        node.queue_free()
    equipped_cleanup()
    _recalculate_weapon_slots()

func equipped_cleanup() -> void:
    for i in range(weapon_holder.get_child_count() - 1, -1, -1):
        var child = weapon_holder.get_child(i)
        if not is_instance_valid(child) or child.is_queued_for_deletion():
            weapon_holder.remove_child(child)
            child.free()

func get_weapon_count() -> int:
    equipped_cleanup()
    return weapon_holder.get_child_count()

func _recalculate_weapon_slots() -> void:
    var count = get_weapon_count()
    if count == 0:
        return
    # 大轨道让法器完全离开人物身体；这里只下发基础角/错开角/轨道半径，
    # 具体方位由 FloatingWeapon 每帧自行滑向目标（自动换位攻击周围的敌人）
    for i in range(count):
        var w = weapon_holder.get_child(i) as FloatingWeapon
        w.base_angle = float(i) * (TAU / float(count))
        w.spread_angle = (float(i) - float(count - 1) * 0.5) * deg_to_rad(28.0)
        w.orbit_extents = Vector2(80.0, 58.0)

func get_equipped_weapons_data() -> Array[Dictionary]:
    equipped_cleanup()
    var list: Array[Dictionary] = []
    for w in weapon_holder.get_children():
        if not is_instance_valid(w):
            continue
        var def := WeaponData.get_def(w.weapon_def_id)
        list.append({
            "id": w.weapon_def_id,
            "name": def.get("name", "?"),
            "star": w.star,
            "tag": def.get("tag", ""),
            "icon": def.get("icon", ""),
            "node": w,
        })
    return list

func sync_drones() -> void:
    # GameManager.drones 是上阵灵蝶的星级列表；数量对齐后逐只刷新数值（合成升星后伤害同步）
    var target: Array = GameManager.drones
    var current_count = sun_orb_container.get_child_count()
    if current_count < target.size():
        for i in range(target.size() - current_count):
            var orb = sun_orb_scene.instantiate()
            sun_orb_container.add_child(orb)
    elif current_count > target.size():
        for i in range(current_count - target.size()):
            sun_orb_container.get_child(0).queue_free()
    for i in range(sun_orb_container.get_child_count()):
        var orb = sun_orb_container.get_child(i) as SunOrb
        if orb != null and i < target.size():
            orb.setup(int(target[i]))

func heal(amount: float) -> void:
    if amount <= 0.0:
        return
    current_health = minf(max_health, current_health + amount)
    GameManager.player_hp_changed.emit(current_health, max_health)
    DamageNumber.spawn(get_parent(), global_position, int(amount), false, "+" + str(int(amount)))

# ---------------- 主循环 ----------------

func _physics_process(delta: float) -> void:
    if GameManager.is_game_over:
        return

    if invulnerable_time > 0.0:
        invulnerable_time -= delta
        anim_sprite.modulate.a = 0.55 if fmod(invulnerable_time, 0.12) > 0.06 else 1.0
    else:
        anim_sprite.modulate.a = 1.0

    # 灵愈心法：持续回血（0.5s 节流刷新 UI）
    if GameManager.hp_regen > 0.0 and current_health < max_health:
        current_health = minf(max_health, current_health + GameManager.hp_regen * delta)
        regen_tick += delta
        if regen_tick >= 0.5:
            regen_tick = 0.0
            GameManager.player_hp_changed.emit(current_health, max_health)

    # 1. Movement input
    var dir: Vector2 = Vector2.ZERO
    if GameManager.joystick != null and GameManager.joystick.has_method("get_direction"):
        dir = GameManager.joystick.get_direction()
    else:
        dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

    var speed = base_speed * GameManager.move_speed_mult
    velocity = dir * speed
    move_and_slide()

    # 界碑拦阻：灵田有边界，不允许跑出地图
    var lim: float = GameManager.MAP_HALF_EXTENT - 26.0
    global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

    # 2. Sprite 方向 & 动画（8 方向奔跑：5 基准方向 + flip_h，节奏动画见 RunMotion）
    var moving: bool = dir.length_squared() > 0.04
    if moving:
        var face: Array = RunMotion.facing(dir)
        if face[0] != "":
            facing = face[0]
            anim_sprite.flip_h = face[1]
        var run_anim: String = "run_" + facing
        if anim_sprite.animation != run_anim:
            anim_sprite.play(run_anim)
        RunMotion.apply(anim_sprite, anim_base_scale, true, anim_sprite.flip_h, absf(dir.x), delta)
    else:
        var idle_anim: String = "idle_" + facing
        if anim_sprite.animation != idle_anim:
            anim_sprite.play(idle_anim)
        idle_bob_phase += delta * 2.0
        anim_sprite.offset.y = sin(idle_bob_phase) * 1.6
        RunMotion.apply(anim_sprite, anim_base_scale, false, anim_sprite.flip_h, 0.0, delta)

    # 3. Pickup Area & Orbit Items
    pickup_area.scale = Vector2.ONE * GameManager.pickup_range_mult
    _process_sun_orbs(delta)

func _process_sun_orbs(delta: float) -> void:
    sync_drones()
    sun_orb_angle += delta * 2.8
    var count = sun_orb_container.get_child_count()
    if count == 0:
        return
    var radius = 78.0
    for i in range(count):
        var orb = sun_orb_container.get_child(i) as Node2D
        var a = sun_orb_angle + float(i) * (TAU / float(count))
        orb.position = Vector2(cos(a), sin(a)) * radius

func take_damage(amount: float) -> void:
    if invulnerable_time > 0.0 or GameManager.is_game_over:
        return

    # 罡气护体：护甲减伤
    var reduced := maxf(1.0, amount / (1.0 + GameManager.armor * 0.08))
    current_health = maxf(0.0, current_health - reduced)
    invulnerable_time = 0.55
    GameManager.player_hp_changed.emit(current_health, max_health)
    GameManager.shake_camera(5.0, 0.2)
    AudioManager.play_sfx("enemy_hit", 0.8)

    if hit_flash_mat != null:
        if flash_tween != null and flash_tween.is_valid():
            flash_tween.kill()
        flash_tween = create_tween()
        flash_tween.tween_property(hit_flash_mat, "shader_parameter/flash_modifier", 1.0, 0.03)
        flash_tween.tween_property(hit_flash_mat, "shader_parameter/flash_modifier", 0.0, 0.1)

    DamageNumber.spawn(get_parent(), global_position, int(reduced), false)

    if current_health <= 0.0:
        GameManager.trigger_game_over(false)

func increase_max_hp(amount: float, heal_amount: float) -> void:
    max_health += amount
    current_health = minf(max_health, current_health + heal_amount)
    GameManager.player_hp_changed.emit(current_health, max_health)
    DamageNumber.spawn(get_parent(), global_position, int(heal_amount), false, "+" + str(int(heal_amount)) + " HP")

func _on_pickup_area_area_entered(area: Area2D) -> void:
    if area.has_method("magnet_to"):
        area.magnet_to(self)
    elif area.get_parent() and area.get_parent().has_method("magnet_to"):
        area.get_parent().magnet_to(self)
