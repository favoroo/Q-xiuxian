class_name GameOverDialog
extends Control

@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleBand/TitleLabel
@onready var stats_label: Label = $CenterContainer/Panel/MarginContainer/VBox/StatsLabel
@onready var retry_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/RetryButton

func _ready() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    P5Style.label(title_label, 26, P5Style.WHITE, 0, P5Style.INK, true)
    P5Style.label(stats_label, 16, Color(0.88, 0.86, 0.9))
    P5Style.button(retry_btn, P5Style.YELLOW, P5Style.WHITE, 18, P5Style.BLACK)
    GameManager.game_over_triggered.connect(_on_game_over)
    retry_btn.pressed.connect(_on_retry_pressed)

func _on_game_over(victory: bool) -> void:
    title_label.text = "越 狱 成 功 ！" if victory else "又 被 抓 回 去 了"
    var mins = int(GameManager.game_time) / 60
    var secs = int(GameManager.game_time) % 60
    stats_label.text = "逃跑时长 %02d:%02d\n击倒狱警 %d 名\n最终等级 Lv.%d\n收集硬币 %d 枚" % [
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
