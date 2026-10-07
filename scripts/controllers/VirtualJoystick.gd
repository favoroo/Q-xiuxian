class_name DawnJoystick
extends Control

signal joystick_updated(output: Vector2)

@export var max_radius: float = 64.0
@export var deadzone: float = 0.1

@onready var base: TextureRect = $Base
@onready var knob: TextureRect = $Base/Knob

var touch_id: int = -1
var is_active: bool = false
var output: Vector2 = Vector2.ZERO

func _ready() -> void:
    modulate.a = 0.0
    base.visible = false

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed and touch_id == -1:
            _start_joystick(event.position, event.index)
        elif not event.pressed and event.index == touch_id:
            _stop_joystick()
    elif event is InputEventScreenDrag:
        if event.index == touch_id:
            _update_joystick(event.position)
    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed and touch_id == -1:
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
