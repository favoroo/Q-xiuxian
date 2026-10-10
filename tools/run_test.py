#!/usr/bin/env python3
"""
tools/run_test.py — 修仙幸存者自动化测试与防挂起运行器

功能：
1. 运行单个或批量测试，支持别名（如 UnitRunner、SmokeRunner）
2. 进程组级别超时强杀（预防 Godot 无头进程挂起或变成僵尸进程）
3. 提取结果关键词与错误堆栈，清晰输出测试摘要
4. 支持一键清理后台遗留的无头 Godot 僵尸进程 (--clean-zombies)
5. 支持一键跑通 6 大核心基线测试 (--core)

用法示例：
  python3 tools/run_test.py UnitRunner
  python3 tools/run_test.py --core
  python3 tools/run_test.py --clean-zombies
"""

import argparse
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

def resolve_scene_path(name: str) -> str:
    if name.startswith("res://"):
        return name
    if name.endswith(".tscn"):
        if os.path.exists(name):
            return "res://" + os.path.relpath(name)
        if os.path.exists(os.path.join("tests", name)):
            return "res://tests/" + name
    cand = [
        f"res://tests/{name}.tscn",
        f"res://tests/{name}Check.tscn",
        f"res://tests/{name}Runner.tscn",
        f"res://tests/{name}Probe.tscn",
        f"res://tests/{name}Preview.tscn",
    ]
    for c in cand:
        local_p = c.replace("res://", "")
        if os.path.exists(local_p):
            return c
    return f"res://tests/{name}.tscn"

def run_single_test(scene_res: str, extra_args: list[str] = None, timeout: float = 20.0) -> bool:
    if not os.path.exists(GODOT_PATH):
        print(f"[ERROR] Godot 可执行文件未找到: {GODOT_PATH}")
        return False

    cmd = [GODOT_PATH, "--headless", "--path", ".", scene_res]
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
        if stderr_data:
            print("--- STDERR 摘要 ---")
            print("\n".join(stderr_data.splitlines()[-10:]))
        return False

    exit_code = proc.returncode if proc else -1
    result_lines = [l for l in stdout_data.splitlines() if "RESULT" in l]
    error_lines = [
        l for l in (stderr_data + "\n" + stdout_data).splitlines()
        if "SCRIPT ERROR" in l or "ERROR:" in l or "[HEADLESS_GUARD]" in l
    ]

    if exit_code == 0 and result_lines:
        print(f"✅ [PASS] 耗时 {dt:.2f}s | 输出: {result_lines[-1]}")
        return True
    elif exit_code == 0:
        print(f"✅ [EXIT 0] 耗时 {dt:.2f}s (未输出 explicit RESULT 标牌)")
        return True
    else:
        print(f"❌ [FAIL] 退出码 {exit_code}，耗时 {dt:.2f}s")
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
    parser = argparse.ArgumentParser(description="修仙幸存者安全测试运行工具")
    parser.add_argument("tests", nargs="*", help="要运行的测试名称或场景路径")
    parser.add_argument("--core", action="store_true", help="运行 6 大核心基线测试")
    parser.add_argument("--clean-zombies", action="store_true", help="清理后台挂起的无头 Godot 进程")
    parser.add_argument("--timeout", type=float, default=25.0, help="单项测试超时秒数（默认 25s）")

    args, unknown = parser.parse_known_args()

    if args.clean_zombies:
        sys.exit(clean_zombies())

    targets = []
    if args.core:
        targets.extend(CORE_TESTS)

    for t in args.tests:
        targets.append(resolve_scene_path(t))

    if not targets:
        parser.print_help()
        sys.exit(0)

    all_ok = True
    total_start = time.time()
    for t_scene in targets:
        # 为 SmokeRunner 额外留宽超时上限
        t_limit = max(args.timeout, 45.0) if "SmokeRunner" in t_scene else args.timeout
        ok = run_single_test(t_scene, unknown, timeout=t_limit)
        if not ok:
            all_ok = False

    tot_dt = time.time() - total_start
    print(f"\n==========================================")
    print(f"执行完毕：总计 {len(targets)} 项测试，总耗时 {tot_dt:.2f}s | 状态: {'ALL PASS ✅' if all_ok else 'FAILED ❌'}")
    print(f"==========================================")
    sys.exit(0 if all_ok else 1)

if __name__ == "__main__":
    main()
