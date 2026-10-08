class_name TestCheck
extends RefCounted

## headless 跑法共用的零依赖断言 helper（SmokeRunner / PoolCheck / UnitRunner 都用它）。
## 约定：逐条打 [PASS]/[FAIL]，最后由 runner 打 "<XXX>_RESULT: ..." 并按失败数决定退出码，
## 这样命令行、发布脚本、将来的 CI 都能用同一套判据，不需要引入任何测试插件。

var failures: Array[String] = []
var passed: int = 0

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
	if all_passed():
		print("%s: ALL PASS（%d 项）" % [prefix, passed])
	else:
		print("%s: %d FAILURES: %s" % [prefix, failures.size(), str(failures)])
	return all_passed()
