class_name GameOverDialog
extends Control

@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleLabel
@onready var stats_label: Label = $CenterContainer/Panel/MarginContainer/VBox/StatsLabel
@onready var retry_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/RetryButton

func _ready() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    GameManager.game_over_triggered.connect(_on_game_over)
    retry_btn.pressed.connect(_on_retry_pressed)

func _on_game_over(victory: bool) -> void:
    title_label.text = "✦ 晨曦祝圣·试炼完成 ✦" if victory else "✦ 轮回落幕·重返星界 ✦"
    var mins = int(GameManager.game_time) / 60
    var secs = int(GameManager.game_time) % 60
    stats_label.text = "存活时长：%02d:%02d\n讨伐生灵：%d\n达到阶位：阶位 %d\n共鸣星界辉晶：%d" % [
        mins, secs, GameManager.kills, GameManager.level, GameManager.astral_shards
    ]
    visible = true
    get_tree().paused = true
    modulate.a = 0.0
    var tw = create_tween()
    tw.tween_property(self, "modulate:a", 1.0, 0.25)

func _on_retry_pressed() -> void:
    get_tree().paused = false
    GameManager.reset_run()
    get_tree().reload_current_scene()
