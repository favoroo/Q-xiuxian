extends Node
func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	print("WINDOW=", DisplayServer.window_get_size(), " VP=", get_viewport().get_visible_rect().size, " IMG=", img.get_size())
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
