class_name DawnJoystick
extends Control

signal joystick_updated(output: Vector2)

@export var max_radius: float = 64.0
@export var deadzone: float = 0.1

## 长按类 UI 键的分组名：按在这些控件上时摇杆整次不接管。
## 为什么要登记：摇杆走全局 _input，比控件自己的 _gui_input 先收到同一次按下，
## 于是「按住按钮」会在按钮底下同时立起一根摇杆 —— 手指稍微滚过 deadzone 就发方向，
## 人被打断在阵法范围外，长按充能前功尽弃（聚灵阵激活键就是这个现场，用户 2026-10-09）。
## 按钮类控件由本节点自动入组（见 _ready 的两趟收口），这个分组只留给非按钮热区
## （如 GameHUD 的羁绊徽记：那是带 gui_input 的 Label，不是 BaseButton）。
const UI_PRESS_HOLD_GROUP := "ui_press_hold"
## 命中余量（像素）：斜切出来的视觉比控件矩形小，手指压在裁掉的角上也算按在键上
const UI_PRESS_HOLD_PAD := 8.0
## 遮罩豁免比例：宽和高都铺到这个成数视口的控件，是"背后那层暗底"而不是一颗键 ——
## 就算被误登记进 ui_press_hold 也不许让位，否则整屏变成走位禁区（比冲突更难查）。
## 取 0.98 而不是更小的数：暗底就是整屏（≥视口），而对话框/商店的卡体即使撑满大半屏
## （灵石阁曾经 1124×521 撑出屏外）仍是一颗要护住的键，不该被当成遮罩放行。
const UI_HOLD_BACKDROP_RATIO := 0.98

@onready var base: TextureRect = $Base
@onready var knob: TextureRect = $Base/Knob

var touch_id: int = -1
var is_active: bool = false
var output: Vector2 = Vector2.ZERO

## 纯函数：这一次按下是否命中长按键的矩形（外扩 pad）。判据直接喂 rect 与点位，不建场景树。
static func rect_claims_ui_hold(hold_rect: Rect2, pos: Vector2, pad: float = UI_PRESS_HOLD_PAD) -> bool:
    return hold_rect.grow(pad).has_point(pos)

## 纯函数：这块控件是不是「背后那层整屏暗底」而不是一颗键（见 UI_HOLD_BACKDROP_RATIO）。
static func is_backdrop_rect(rect: Rect2, viewport_size: Vector2, ratio: float = UI_HOLD_BACKDROP_RATIO) -> bool:
    return rect.size.x >= viewport_size.x * ratio and rect.size.y >= viewport_size.y * ratio

## 扫当前登记在案的长按键：只算真的还挂在树上、且看得见的那一颗
## （聚灵阵按钮出了范围就整块隐藏，那时右侧又该照常能拉动走位）。
## 灰掉（disabled）的按钮不接单，也就不许把这次走位抢走 —— 点它没反应，人就该照常被驱动。
## 整屏暗底按 is_backdrop_rect 豁免：登记错成遮罩时宁可放行，也不能把满屏变成走位禁区。
func is_press_on_ui_hold(pos: Vector2) -> bool:
    var vp := get_viewport_rect().size
    for node in get_tree().get_nodes_in_group(UI_PRESS_HOLD_GROUP):
        if not is_instance_valid(node):
            continue
        var c := node as Control
        if c == null or not c.is_visible_in_tree():
            continue
        var b := c as BaseButton
        if b != null and b.disabled:
            continue
        var rect := c.get_global_rect()
        if is_backdrop_rect(rect, vp):
            continue
        if rect_claims_ui_hold(rect, pos):
            return true
    return false

func _ready() -> void:
    modulate.a = 0.0
    base.visible = false
    # 收口：全项目所有按钮都算「长按键」，不靠每个界面自己登记 —— 逐颗登记早晚会有人忘，
    # 忘了就是「点按钮同时长出一根摇杆」。两趟缺一不可：
    # ① 入树时整树扫一遍，接住场景里比摇杆先存在的按钮（对话框、菜单、商店底板）；
    # ② node_added 接住之后任何时刻现造的（HUD 顶栏三颗、聚灵键、商店卡、详解关闭键都是代码造的，
    #    更新浮层还挂在 UpdateManager 而不是本层，所以不能只扫自己这个 CanvasLayer）。
    _adopt_buttons(get_tree().root)
    get_tree().node_added.connect(_on_ui_node_added)

## 按钮入组：组内成员随节点释放自动移除，重开一局不必清理
func _on_ui_node_added(node: Node) -> void:
    if node is BaseButton:
        node.add_to_group(UI_PRESS_HOLD_GROUP)

func _adopt_buttons(node: Node) -> void:
    for c in node.get_children():
        if c is BaseButton:
            c.add_to_group(UI_PRESS_HOLD_GROUP)
        _adopt_buttons(c)

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed and touch_id == -1 and not is_press_on_ui_hold(event.position):
            _start_joystick(event.position, event.index)
        elif not event.pressed and event.index == touch_id:
            _stop_joystick()
    elif event is InputEventScreenDrag:
        if event.index == touch_id:
            _update_joystick(event.position)
    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed and touch_id == -1 and not is_press_on_ui_hold(event.position):
                _start_joystick(event.position, 999)
            elif not event.pressed and touch_id == 999:
                _stop_joystick()
    elif event is InputEventMouseMotion:
        if touch_id == 999:
            _update_joystick(event.position)

func _start_joystick(pos: Vector2, id: int) -> void:
    touch_id = id
    is_active = true
    base.global_position = pos - base.size * 0.5
    knob.position = (base.size - knob.size) * 0.5
    base.visible = true
    
    var tw = create_tween()
    tw.tween_property(self, "modulate:a", 1.0, 0.12)
    output = Vector2.ZERO
    joystick_updated.emit(output)

func _update_joystick(pos: Vector2) -> void:
    if not is_active:
        return
    var center = base.global_position + base.size * 0.5
    var offset = pos - center
    var dist = offset.length()
    
    if dist > max_radius:
        offset = offset.normalized() * max_radius
    
    knob.position = (base.size - knob.size) * 0.5 + offset
    
    var normalized_dist = offset.length() / max_radius
    if normalized_dist < deadzone:
        output = Vector2.ZERO
    else:
        output = offset.normalized() * ((normalized_dist - deadzone) / (1.0 - deadzone))
    
    joystick_updated.emit(output)

func _stop_joystick() -> void:
    touch_id = -1
    is_active = false
    output = Vector2.ZERO
    joystick_updated.emit(output)
    
    var tw = create_tween()
    tw.tween_property(self, "modulate:a", 0.0, 0.15)
    tw.tween_callback(func(): base.visible = false)

func get_direction() -> Vector2:
    var key_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var wasd = Vector2(
        float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
        float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
    )
    var combined = key_dir + wasd
    if combined.length_squared() > 0.01:
        return combined.normalized()
    return output
