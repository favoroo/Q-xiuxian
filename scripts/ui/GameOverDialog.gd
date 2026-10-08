class_name GameOverDialog
extends Control

@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleBand/TitleLabel
@onready var stats_label: Label = $CenterContainer/Panel/MarginContainer/VBox/StatsLabel
@onready var retry_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/RetryButton
@onready var endless_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/EndlessButton
@onready var title_band: PanelContainer = $CenterContainer/Panel/MarginContainer/VBox/TitleBand

func _ready() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    GameStyle.label(title_label, 26, GameStyle.PAPER, 0, GameStyle.INK, true)
    GameStyle.label(stats_label, 16, Color(0.85, 0.87, 0.94))
    GameStyle.button(retry_btn, GameStyle.YELLOW, GameStyle.PAPER, 18, GameStyle.INK_TEXT)
    GameStyle.button(endless_btn, GameStyle.BLUE, GameStyle.BLUE_EDGE, 16, GameStyle.PAPER)
    GameManager.game_over_triggered.connect(_on_game_over)
    retry_btn.pressed.connect(_on_retry_pressed)
    endless_btn.pressed.connect(_on_endless_pressed)

func _on_game_over(victory: bool) -> void:
    title_label.text = "渡 劫 成 功 ！" if victory else "道 消 身 殒"
    title_band.add_theme_stylebox_override("panel",
        GameStyle.block(GameStyle.BLUE if victory else GameStyle.BAD, GameStyle.SLANT_BAND, Vector2(4, 5)))
    var mins = int(GameManager.game_time) / 60
    var secs = int(GameManager.game_time) % 60
    stats_label.text = "镇守时长 %02d:%02d\n斩妖 %d 只\n最终境界 Lv.%d\n囊中灵石 %d 枚" % [
        mins, secs, GameManager.kills, GameManager.level, GameManager.spirit_stones
    ]
    endless_btn.visible = victory and not GameManager.endless_mode
    visible = true
    get_tree().paused = true
    modulate.a = 0.0
    var tw = create_tween()
    tw.tween_property(self, "modulate:a", 1.0, 0.25)

func _on_retry_pressed() -> void:
    get_tree().paused = false
    GameManager.reset_run()
    get_tree().reload_current_scene()

func _on_endless_pressed() -> void:
    visible = false
    AudioManager.play_sfx("level_up", 1.0)
    GameManager.continue_endless()
