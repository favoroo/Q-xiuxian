class_name DamageNumber
extends Node2D

static func spawn(parent: Node, pos: Vector2, amount: int, is_crit: bool = false, custom_text: String = "") -> void:
    var holder = Node2D.new()
    holder.global_position = pos + Vector2(randf_range(-10.0, 10.0), -16.0)
    holder.z_index = 50
    parent.add_child(holder)
    
    var label = Label.new()
    label.text = custom_text if custom_text != "" else str(amount)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    
    var settings = LabelSettings.new()
    if custom_text != "":
        settings.font_size = 15
        settings.font_color = Color(0.98, 0.92, 0.48)
        settings.outline_size = 4
        settings.outline_color = Color(0.24, 0.18, 0.12, 0.9)
    elif is_crit:
        settings.font_size = 18
        settings.font_color = Color(1.0, 0.85, 0.25)
        settings.outline_size = 4
        settings.outline_color = Color(0.35, 0.18, 0.08, 0.95)
    else:
        settings.font_size = 14
        settings.font_color = Color(1.0, 0.99, 0.94)
        settings.outline_size = 3
        settings.outline_color = Color(0.2, 0.26, 0.32, 0.85)
    
    label.label_settings = settings
    label.position = Vector2(-30.0, -12.0)
    label.custom_minimum_size = Vector2(60.0, 24.0)
    holder.add_child(label)
    
    var tw = holder.create_tween()
    tw.set_parallel(true)
    tw.tween_property(holder, "global_position:y", holder.global_position.y - 28.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tw.tween_property(holder, "scale", Vector2(1.18, 1.18) if is_crit else Vector2(1.05, 1.05), 0.12)
    tw.chain().tween_property(holder, "modulate:a", 0.0, 0.22)
    tw.chain().tween_callback(holder.queue_free)
