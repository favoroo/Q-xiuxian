extends Node

## Boss 闷音低通的结构不变量判据（2026-10-24 满幅事故整改的回归钉子）。
## 运行: godot --headless --path . res://tests/AudioMuffleCheck.tscn
## 背景：引擎播放器流热换与音频线程的竞态偶发 NaN 样本，被常驻低通的双二阶寄存器
## 捕获后永久满幅（真机=全局没声音、重启才恢复）。整改后必须永远成立：
##   ① 低通效果器存在但启动即旁路（常态链上无有状态组件）；
##   ② set_bgm_muffle(true) 同步接入，(false) 在补间后（0.8s+裕量）整器旁路；
##   ③ CLEAR 档位 ≤ 18000（不许再压回 Nyquist 退化区）；
##   ④ Master 上挂着满幅看门狗的 capture 采集口。

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	var bgm_idx := AudioServer.get_bus_index(AudioManager.BUS_BGM)
	var effect_idx := AudioManager._bgm_effect_idx
	_check(bgm_idx >= 0 and effect_idx >= 0, "BGM 低通效果槽位可定位")
	_check(AudioServer.get_bus_effect(bgm_idx, effect_idx) is AudioEffectLowPassFilter,
		"槽位上确实是低通")
	_check(not AudioServer.is_bus_effect_enabled(bgm_idx, effect_idx), "启动即旁路（非常驻）")
	var has_capture := false
	for i in range(AudioServer.get_bus_effect_count(0)):
		if AudioServer.get_bus_effect(0, i) is AudioEffectCapture:
			has_capture = true
	_check(has_capture, "Master 挂着看门狗 capture 采集口")

	AudioManager.set_bgm_muffle(true)
	_check(AudioServer.is_bus_effect_enabled(bgm_idx, effect_idx), "开闷音：效果器同步接入")
	_check(AudioManager._bgm_lowpass.cutoff_hz <= AudioManager.CLEAR_CUTOFF + 0.5,
		"开闷音后 cutoff 不越过 CLEAR 档")
	AudioManager.set_bgm_muffle(false)
	await get_tree().create_timer(1.1).timeout
	_check(not AudioServer.is_bus_effect_enabled(bgm_idx, effect_idx), "解闷音：补间后整器旁路")
	_check(AudioManager._bgm_lowpass.cutoff_hz <= 18000.0,
		"CLEAR 档 ≤ 18000（禁止回压 Nyquist 退化区）")
	_check(AudioManager._muffle_on == false, "闷音意图态复位")

	print("AUDIOMUFFLE_RESULT: " + ("ALL PASS" if _c.failures.is_empty() else "%d FAILURES: %s" % [_c.failures.size(), ", ".join(_c.failures)]))
	get_tree().quit(0 if _c.failures.is_empty() else 1)
