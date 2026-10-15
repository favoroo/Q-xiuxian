class_name ProcStatus
extends RefCounted

## 武器侧五行异常施加的唯一入口（从武器三件套 5 处复制的三行块收口）。
##
## 严禁改成类型化引用 EnemyBase：武器/弹丸脚本硬引用敌人基类会触发循环类依赖，
## 把 preload(BladeProjectile.tscn) 打成空 PackedScene（弹丸静默 null）。
## 这里保持纯字符串 has_method 鸭类型，与既有判定同规约。
## proc 开关恒假时 has_method 不会执行，零成本。

## 对单个敌人按开关施加灼烧/减速/毒伤三系异常。
## dps 值由调用方按自身口径算好传入（近战按当刀伤害×比例、弹丸按面板 dps）。
static func apply(enemy: Object, burn: bool, burn_dps: float, burn_dur: float,
		chill: float, chill_dur: float, poison: bool, poison_dps: float, poison_dur: float) -> void:
	if burn and enemy.has_method("apply_burn"):
		enemy.apply_burn(burn_dps, burn_dur)
	if chill > 0.0 and enemy.has_method("apply_chill"):
		enemy.apply_chill(chill, chill_dur)
	if poison and enemy.has_method("apply_poison"):
		enemy.apply_poison(poison_dps, poison_dur)
