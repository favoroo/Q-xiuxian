class_name UnitTestsBase
extends Node

## 单测模块基类：从 tests/unit_runner.gd 拆出（2026-10-11）。
## 模块必须是 Node：个别用例要 add_child 造真节点（敌弹/镜头/道统立绘）跑树上下文，
## runner 会把每个模块挂到自己下面。各模块共享 runner 传入的同一份 TestCheck 账本，
## 最终由 runner 统一 report —— 契约（UNIT_RESULT: ALL PASS / 退出码 0|1）不变。

const EPS := 0.0001

var _c: TestCheck

func _init(checker: TestCheck) -> void:
	_c = checker
