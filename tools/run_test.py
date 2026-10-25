#!/usr/bin/env python3
"""
tools/run_test.py — 剑士自动化测试与防挂起运行器

功能：
1. 运行单个或批量测试，支持别名（如 UnitRunner、SmokeRunner）
2. 进程组级别超时强杀（预防 Godot 无头进程挂起或变成僵尸进程）
3. 提取结果关键词与错误堆栈，清晰输出测试摘要
4. 支持一键清理后台遗留的无头 Godot 僵尸进程 (--clean-zombies)
5. 支持一键跑通 6 大核心基线测试 (--core，总耗时 ~18s，严禁混入长程浸泡)
6. 独立支持长程浸泡回归测试 (--soak，涵盖 20 波长局，超时上限 240s)
7. 环境预检防死锁：拦截无 .godot 导入缓存的裸目录（如 git worktree），支持 --auto-import
8. 全量回归：扫描 tests/*.tscn 全跑，跳过现场预览类 (--all)
9. 秒级门禁：仅跑 UnitRunner 数值单测 (--quick，pre-commit 钩子用)

用法示例：
  python3 tools/run_test.py UnitRunner
  python3 tools/run_test.py --core      # 6 大核心基线（日常改动必跑）
  python3 tools/run_test.py --quick     # 秒级数值单测
  python3 tools/run_test.py --soak      # 长程浸泡长局测试
  python3 tools/run_test.py --all       # 全量判据回归
  python3 tools/run_test.py --clean-zombies
"""

import argparse
import glob
import os
import signal
import subprocess
import sys
import time

GODOT_PATH = os.environ.get("G", "/Applications/Godot.app/Contents/MacOS/Godot")

CORE_TESTS = [
    "res://tests/UnitRunner.tscn",
    "res://tests/SmokeRunner.tscn",
    "res://tests/PoolCheck.tscn",
    "res://tests/LayoutCheck.tscn",
    "res://tests/FontCoverageCheck.tscn",
    "res://tests/BalanceSimCheck.tscn",
]

# --all 全量回归时跳过的场景：需要真实出声/出图的现场预览（headless 下无意义），以及明确不适合批量跑的
ALL_SKIP_PATTERNS = ("Preview", "AudioGallery")
# 名字不带 Preview 但同样 headless 跑不了的：WeaponHeadFusionCheck 要真实窗口出图（文件头有说明），
# WeaponProbe 是"一件法器一进程"的手动实测台（非判据，必须带 -- --only <weapon> 参数），
# ChestLookProbe 是把匣子三段画到 /tmp/chest_stages.png 的出图台（无像素时自己打 NO PIXELS 退 1）。
# ToneCapture（真机抓拍，文件头自标「非判据」）与 AudioGameOverProbe / AudioSoakProbe
# （2026-10-25 音频满幅自愈的诊断遗产：前者是挂起复现器、后者是 380s 浸泡）在 --all 里只会白等超时。
ALL_SKIP_NAMES = {"WeaponHeadFusionCheck.tscn", "WeaponProbe.tscn", "ChestLookProbe.tscn",
	"ToneCapture.tscn", "AudioGameOverProbe.tscn", "AudioSoakProbe.tscn"}

# 真在干活的慢判据：默认 35s 会把「跑完了但跑得久」误判成挂起。上限按实测给（括号里是本轮实测）。
SLOW_TEST_LIMITS = {
    "SmokeRunner": 60.0,          # 全流程冒烟（实测 ~8.2s，给 60s 留 7 倍裕量）
    "ManualHotzoneCheck": 140.0,  # 173 张卡 × 12 取样点 = 2076 次真实点按（实测 ~85s）
    "ProjectileProbe": 60.0,      # B 段真跑 18 秒尸潮（time_scale=1，实测 ~34s）
    "SoakCheck": 240.0,           # 连续 20 波长局 + 重开一局再战 3 波（实测 ~122s）
}


def discover_all_tests():
    """扫描 tests/*.tscn 全部判据场景，返回 (targets, skipped_names)"""
    tests_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tests")
    scenes = sorted(glob.glob(os.path.join(tests_dir, "*.tscn")))
    targets, skipped = [], []
    for p in scenes:
        name = os.path.basename(p)
        if name in ALL_SKIP_NAMES or any(k in name for k in ALL_SKIP_PATTERNS):
            skipped.append(name)
            continue
        targets.append("res://tests/" + name)
    return targets, skipped

def clean_zombies() -> int:
    """清理后台遗留的无头 Godot 僵尸进程"""
    try:
        out = subprocess.check_output(
            ["ps", "-eo", "pid,command"], text=True
        )
    except Exception as e:
        print(f"[ERROR] 无法查询进程: {e}")
        return 1

    killed = 0
    for line in out.splitlines():
        if GODOT_PATH in line and "--headless" in line and "run_test.py" not in line:
            parts = line.strip().split()
            if parts:
                pid = int(parts[0])
                try:
                    os.kill(pid, signal.SIGKILL)
                    killed += 1
                except ProcessLookupError:
                    pass
                except Exception as ex:
                    print(f"[WARN] 终止进程 {pid} 失败: {ex}")
    print(f"[CLEANUP] 已清理 {killed} 个挂起的无头 Godot 进程。")
    return 0

def resolve_scene_path(name: str, project_path: str = ".") -> str:
    """把测试名/路径解析成 res:// 场景路径。解析不到返回空串（由调用方报错）。

    关键：候选必须真存在于 project_path 下，否则 Godot 加载失败时退出码仍是 0，
    run_single_test 会误报 PASS（CHANGELOG:410 记录的假绿）。
    """
    def _local(res_path: str) -> str:
        return os.path.join(project_path, res_path.replace("res://", ""))

    if name.startswith("res://"):
        return name if os.path.exists(_local(name)) else ""
    if name.endswith(".tscn"):
        if os.path.exists(name):
            return "res://" + os.path.relpath(name, project_path)
        if os.path.exists(os.path.join(project_path, "tests", name)):
            return "res://tests/" + name
    cand = [
        f"res://tests/{name}.tscn",
        f"res://tests/{name}Check.tscn",
        f"res://tests/{name}Runner.tscn",
        f"res://tests/{name}Probe.tscn",
        f"res://tests/{name}Preview.tscn",
    ]
    for c in cand:
        if os.path.exists(_local(c)):
            return c
    # 命名兜底：脚本 snake_case / 场景 PascalCase 两套并存时，手敲任一形式都能解析。
    # 归一化 = 去下划线 + 小写，使 hud_btn_drag_check ↔ HudBtnDragCheck 互相匹配。
    tests_dir = os.path.join(project_path, "tests")
    if os.path.isdir(tests_dir):
        norm = name.lower().replace("_", "")
        matches = [fn for fn in os.listdir(tests_dir)
                   if fn.endswith(".tscn") and fn[:-5].lower().replace("_", "") == norm]
        if len(matches) == 1:
            return "res://tests/" + matches[0]
    return ""

def check_project_environment(project_path: str, auto_import: bool = False) -> bool:
    """预检 Godot 工程环境，防止在缺少 .godot 缓存的裸目录（如 git worktree）中运行导致死锁"""
    proj_cfg = os.path.join(project_path, "project.godot")
    if not os.path.exists(proj_cfg):
        print(f"❌ [PRECHECK ERROR] 路径 '{project_path}' 不是有效的 Godot 工程（缺少 project.godot）。")
        return False

    imported_dir = os.path.join(project_path, ".godot", "imported")
    if not os.path.exists(imported_dir) or not os.listdir(imported_dir):
        print(f"⚠️  [PRECHECK WARN] 路径 '{project_path}' 缺少 .godot 导入缓存！")
        print("    Godot 在无头模式下若缺少资源/类名索引，会抛出 Parse Error 并挂死空转（不自动退出）。")
        if auto_import:
            print("    正在自动执行编辑器预扫描导入 ($G --headless --editor --quit)...")
            try:
                subprocess.run(
                    [GODOT_PATH, "--headless", "--path", project_path, "--editor", "--quit"],
                    timeout=45.0,
                    check=True,
                )
                print("    ✅ 导入缓存构建完成。")
                return True
            except Exception as e:
                print(f"    ❌ 自动导入失败: {e}")
                return False
        else:
            print("    【拦截保护】请先在目标目录执行编辑器扫描建立缓存，或带上 --auto-import 参数:")
            print(f"    $G --headless --path '{project_path}' --editor --quit")
            return False
    return True

def run_single_test(scene_res: str, extra_args: list[str] = None, timeout: float = 35.0, project_path: str = ".") -> bool:
    if not os.path.exists(GODOT_PATH):
        print(f"[ERROR] Godot 可执行文件未找到: {GODOT_PATH}")
        return False

    # 场景不存在的前置校验：Godot 加载失败时退出码仍是 0，会误报 PASS（见 CHANGELOG:410）
    local_scene = os.path.join(project_path, scene_res.replace("res://", ""))
    if not os.path.exists(local_scene):
        print(f"❌ [FAIL] 场景不存在: {scene_res}（解析到 {local_scene}）")
        return False

    cmd = [GODOT_PATH, "--headless", "--path", project_path, scene_res]
    if extra_args:
        cmd.extend(extra_args)

    print(f"\n▶ 正在运行: {scene_res} (超时上限: {timeout:.0f}s)...")
    t0 = time.time()
    proc = None
    stdout_data = ""
    stderr_data = ""
    timed_out = False

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,  # 独立进程组，保证可彻底强杀子进程
        )
        stdout_data, stderr_data = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        if proc:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except Exception:
                pass
            stdout_data, stderr_data = proc.communicate()
    finally:
        dt = time.time() - t0

    if timed_out:
        print(f"❌ [TIMEOUT] 测试运行超时 ({dt:.2f}s > {timeout}s)，已安全终止进程。")
        print("💡 [根因提醒] Godot --headless 遇到 Parse Error 或资源缺失时不会自动调用 quit()，导致进程死循环。已由看门狗强杀止损。")
        if stderr_data:
            print("--- STDERR 摘要 ---")
            print("\n".join(stderr_data.splitlines()[-10:]))
        return False

    exit_code = proc.returncode if proc else -1
    result_lines = [l for l in stdout_data.splitlines() if "RESULT" in l]
    combined = stderr_data + "\n" + stdout_data
    error_lines = [
        l for l in combined.splitlines()
        if "SCRIPT ERROR" in l or "ERROR:" in l or "[HEADLESS_GUARD]" in l
    ]

    # 致命错误：脚本崩溃（SCRIPT ERROR）与场景/资源加载失败时，Godot 往往仍以退出码 0 收场，
    # 只看退出码会把「跑崩了」当 PASS（StatShadow 缺字段那种假绿正是如此）。
    # 例外：selftest 故意用错形参制造 SCRIPT ERROR 来验证判据有牙齿（hud_btn_drag_check），
    #       故带 --selftest 时放行 SCRIPT ERROR。
    is_selftest = bool(extra_args) and any("--selftest" in str(a) for a in extra_args)
    fatal_markers = ["Failed loading", "Failed to load", "Cannot open file"]
    fatal = [l for l in combined.splitlines() if any(m in l for m in fatal_markers)]
    if not is_selftest:
        fatal += [l for l in combined.splitlines() if "SCRIPT ERROR" in l]

    if exit_code == 0 and fatal:
        print(f"❌ [FAIL] 退出码 0 但运行期报致命错误（假绿），耗时 {dt:.2f}s")
        for err in fatal[:6]:
            print(" ", err)
        return False

    if exit_code == 0 and result_lines:
        print(f"✅ [PASS] 耗时 {dt:.2f}s | 输出: {result_lines[-1]}")
        return True
    elif exit_code == 0:
        print(f"✅ [EXIT 0] 耗时 {dt:.2f}s (未输出 explicit RESULT 标牌)")
        return True
    else:
        print(f"❌ [FAIL] 退出码 {exit_code}，耗时 {dt:.2f}s")
        # 断言失败时场景自己的 [FAIL] 行全在 stdout 里；不打出来，CI 只看到资源泄漏
        # 之类的无关 ERROR，判据等于黑盒（2026-10-25 CI 排查踩过）。
        fail_lines = [l for l in stdout_data.splitlines() if "[FAIL]" in l]
        if fail_lines:
            print("--- 失败断言 ---")
            for l in fail_lines[:12]:
                print(" ", l)
        if result_lines:
            print("--- RESULT 汇总 ---")
            for l in result_lines[-2:]:
                print(" ", l)
        if error_lines:
            print("--- 错误诊断 ---")
            for err in error_lines[:6]:
                print(" ", err)
        elif stderr_data:
            print("--- STDERR 摘要 ---")
            for l in stderr_data.splitlines()[-6:]:
                print(" ", l)
        return False

def main():
    parser = argparse.ArgumentParser(description="剑士安全测试运行工具")
    parser.add_argument("tests", nargs="*", help="要运行的测试名称或场景路径")
    parser.add_argument("--core", action="store_true", help="运行 6 大核心基线测试")
    parser.add_argument("--soak", action="store_true", help="运行长局浸泡回归测试 (SoakCheck)")
    parser.add_argument("--all", action="store_true", help="扫描 tests/*.tscn 全量回归（跳过需真实出声出图的 Preview/Gallery）")
    parser.add_argument("--quick", action="store_true", help="秒级门禁：仅跑 UnitRunner 数值单测（pre-commit 用）")
    parser.add_argument("--clean-zombies", action="store_true", help="清理后台挂起的无头 Godot 进程")
    parser.add_argument("--timeout", type=float, default=35.0, help="单项测试超时秒数（默认 35s，慢测试自动按表放宽）")
    parser.add_argument("--path", type=str, default=".", help="目标 Godot 工程目录（默认当前目录）")
    parser.add_argument("--auto-import", action="store_true", help="如果缺少 .godot 导入缓存，自动跑编辑器扫描预构建")

    args, unknown = parser.parse_known_args()

    if args.clean_zombies:
        sys.exit(clean_zombies())

    # 环境预检：防止在缺少 .godot 导入缓存的裸目录（如临时 worktree）中运行导致死锁
    if not check_project_environment(args.path, auto_import=args.auto_import):
        sys.exit(1)

    targets = []
    if args.quick:
        targets.append("res://tests/UnitRunner.tscn")
    if args.core:
        targets.extend(CORE_TESTS)
    if args.soak:
        targets.append("res://tests/SoakCheck.tscn")
    if args.all:
        all_targets, skipped = discover_all_tests()
        targets.extend(all_targets)
        if skipped:
            print(f"[SKIP] --all 跳过 {len(skipped)} 个现场预览场景: {', '.join(skipped)}")

    for t in args.tests:
        resolved = resolve_scene_path(t, args.path)
        if not resolved:
            print(f"❌ [FAIL] 找不到测试场景: {t}（检查名字或大小写）")
            sys.exit(1)
        targets.append(resolved)

    if not targets:
        parser.print_help()
        sys.exit(0)

    all_ok = True
    total_start = time.time()
    for t_scene in targets:
        # 慢判据按表留宽上限（其余仍吃 --timeout 默认值，防挂起的那道闸不松）
        t_limit = args.timeout
        for name, limit in SLOW_TEST_LIMITS.items():
            if name in t_scene:
                t_limit = max(t_limit, limit)
        ok = run_single_test(t_scene, unknown, timeout=t_limit, project_path=args.path)
        if not ok:
            all_ok = False

    tot_dt = time.time() - total_start
    print(f"\n==========================================")
    print(f"执行完毕：总计 {len(targets)} 项测试，总耗时 {tot_dt:.2f}s | 状态: {'ALL PASS ✅' if all_ok else 'FAILED ❌'}")
    print(f"==========================================")
    sys.exit(0 if all_ok else 1)

if __name__ == "__main__":
    main()
