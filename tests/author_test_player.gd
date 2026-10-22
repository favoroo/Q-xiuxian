extends Node2D
class_name AuthorTestPlayer

## 临时探针用的假玩家：只满足 WeaponInventory.add_weapon 的鸭类型需求

var max_health: float = 100.0
var current_health: float = 100.0
var base_speed: float = 220.0
var equipped: Array = []

func add_weapon_instance(id: String, star: int) -> void:
	equipped.append({"id": id, "star": star})

func get_weapon_count() -> int:
	return equipped.size()

func sync_drones() -> void:
	pass

func get_equipped_weapons_data() -> Array:
	return equipped

func heal(_v: float) -> void:
	pass
