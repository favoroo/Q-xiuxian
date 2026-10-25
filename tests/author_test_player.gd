extends Node2D
class_name AuthorTestPlayer

## 临时探针用的假玩家：只满足 WeaponInventory.add_weapon 的鸭类型需求

var max_health: float = 100.0
var current_health: float = 100.0
var base_speed: float = 220.0
var equipped: Array = []

func add_weapon_instance(id: String, star: int) -> void:
	# node 必须是**每件一个**独立实例：merge_weapon 靠节点引用区分 keeper 与被吃掉的副本，
	# 全指向 self 会让 keeper 判定把三件全跳过（副本数量不足，合成整条断掉）
	var marker := Node.new()
	marker.name = "FakeWeaponNode"
	add_child(marker)
	equipped.append({"id": id, "star": star, "node": marker})

## 三合一的消耗通道：真 Player 按**节点引用**移除被吃掉的两件副本。
## 不给这一条，merge_weapon 走到「副本数量不足」就整条链路断掉 —— 作者模式商店的
## 合成/升星完全测不到（2026-10-25 探针：点了三合一键只报 warning，星数没变）。
func remove_weapon_instance(node: Node) -> void:
	for i in range(equipped.size() - 1, -1, -1):
		if equipped[i].get("node") == node:
			equipped.remove_at(i)
			if node != null and is_instance_valid(node):
				node.queue_free()
			return

## 三合一 keeper 升星：真 Player 重跑 setup 把新星级刷进武器节点
func upgrade_weapon_instance(node: Node, new_star: int) -> void:
	for e in equipped:
		if e.get("node") == node:
			e["star"] = new_star
			return

func get_weapon_count() -> int:
	return equipped.size()

func sync_drones() -> void:
	pass

func get_equipped_weapons_data() -> Array:
	return equipped

func heal(v: float) -> void:
	# 与 Player.heal 同口径：只回缺口（作者面板「补满生命」判据要读回血量）
	current_health = minf(max_health, current_health + maxf(0.0, v))

## 生命上限增减（作者悟道测试台要重放 max_hp）：
## 算式照 Player.increase/decrease_max_hp，去掉跳字/挤压/信号（headless 无画面）
func increase_max_hp(amount: float, heal_amount: float) -> void:
	max_health += amount
	current_health = minf(max_health, current_health + heal_amount)

func decrease_max_hp(amount: float) -> void:
	max_health = maxf(1.0, max_health - amount)
	current_health = minf(current_health, max_health)
