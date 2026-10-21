class_name TestCheck
extends RefCounted

## headless 跑法共用的零依赖断言 helper（SmokeRunner / PoolCheck / UnitRunner 都用它）。
## 约定：逐条打 [PASS]/[FAIL]，最后由 runner 打 "<XXX>_RESULT: ..." 并按失败数决定退出码，
## 这样命令行、发布脚本、将来的 CI 都能用同一套判据，不需要引入任何测试插件。

var failures: Array[String] = []
var passed: int = 0

## 判据「记满账」下限：report() 时 passed 少于此数即补记一条 failure。
## 为什么要有：GDScript 的 SCRIPT ERROR 不中断函数，中途炸了会静默跳过剩余断言，
## 若一条都没记，report() 会打「ALL PASS（0 项）」——假绿。默认 0 表示不设限，
## 重判据自行用 set_min_checks(n) 声明期望条数（条数掉一半 = 中途炸了）。
var min_checks: int = 0

func set_min_checks(n: int) -> void:
	min_checks = n

## 无条件记一条失败。用于「本不该走到这里」的分支（例如某武器没纳入任何分档）。
## 必须存在：此前 balance_sim_check 调它却无此方法，抛 SCRIPT ERROR 吞掉了同函数后续 13 条断言。
func fail(label: String) -> bool:
	failures.append(label)
	print("[FAIL] " + label)
	return false

func check(cond: bool, label: String) -> bool:
	if cond:
		passed += 1
		print("[PASS] " + label)
	else:
		failures.append(label)
		print("[FAIL] " + label)
	return cond

## 浮点等值断言：把期望值与实际值一起打出来，失败时不用再去猜是哪个数错了
func near(actual: float, expected: float, eps: float, label: String) -> bool:
	return check(absf(actual - expected) <= eps, "%s（期望 %.4f，实得 %.4f）" % [label, expected, actual])

func equals(actual, expected, label: String) -> bool:
	return check(actual == expected, "%s（期望 %s，实得 %s）" % [label, str(expected), str(actual)])

func all_passed() -> bool:
	return failures.is_empty()

## 汇总行：runner 拿它的返回值决定退出码
func report(prefix: String) -> bool:
	if passed < min_checks:
		failures.append("判据空转：仅执行 %d 条断言，低于声明下限 %d（疑似中途异常/提前 return）" % [passed, min_checks])
	if all_passed():
		print("%s: ALL PASS（%d 项）" % [prefix, passed])
	else:
		print("%s: %d FAILURES: %s" % [prefix, failures.size(), str(failures)])
	return all_passed()
