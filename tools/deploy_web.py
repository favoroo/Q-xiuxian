#!/usr/bin/env python3
# 剑士 Web 版部署脚本：导出 HTML5 → 推送到 gh-pages 分支 → 打印访问 URL
# 仅用 Python 标准库，无第三方依赖。用法见 .agents/skills/web-deploy/SKILL.md

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = REPO_ROOT / 'build' / 'web'
SITE_DIR = REPO_ROOT / 'site' / 'dist'
GODOT_BIN = '/Applications/Godot.app/Contents/MacOS/Godot'

# GitHub Pages 地址（项目页面，非用户页面）
GITHUB_OWNER, GITHUB_REPO = 'favoroo', 'Q-xiuxian'
PAGES_URL = f'https://{GITHUB_OWNER.lower()}.github.io/{GITHUB_REPO}/'
SITE_URL = f'{PAGES_URL}site/'

T0 = time.time()


def log(msg: str) -> None:
    print(f'[{time.time() - T0:7.1f}s] {msg}', flush=True)


def die(msg: str, code: int = 1) -> None:
    print(f'✗ 错误: {msg}', file=sys.stderr, flush=True)
    sys.exit(code)


def run(cmd: list, **kw) -> subprocess.CompletedProcess:
    kw.setdefault('cwd', REPO_ROOT)
    kw.setdefault('capture_output', True)
    kw.setdefault('text', True)
    return subprocess.run(cmd, **kw)


def export_web() -> None:
    """调用 Godot CLI 导出 Web 版到 build/web/"""
    if not Path(GODOT_BIN).exists():
        die(f'Godot 执行程序不存在: {GODOT_BIN}')

    # 清理旧产物
    if BUILD_DIR.exists():
        shutil.rmtree(BUILD_DIR)
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    log('开始调用 Godot 导出 Web 版...')
    cmd = [
        GODOT_BIN,
        '--headless',
        '--export-release',
        'Web',
        str(BUILD_DIR / 'index.html'),
    ]
    r = run(cmd)
    if r.returncode != 0:
        detail = ((r.stderr or '') + '\n--- stdout ---\n' + (r.stdout or ''))[-3000:]
        die(f'Godot CLI 导出 Web 版失败:\n{detail}')

    if not (BUILD_DIR / 'index.html').exists():
        die(f'未找到导出的 index.html: {BUILD_DIR / "index.html"}')

    # 统计产物大小
    total_size = sum(f.stat().st_size for f in BUILD_DIR.rglob('*') if f.is_file())
    file_count = sum(1 for f in BUILD_DIR.rglob('*') if f.is_file())
    log(f'导出完成: {file_count} 个文件, {total_size / 1024 / 1024:.1f} MB')


def deploy_to_ghpages(skip_site: bool = False, allow_dirty: bool = False) -> None:
    """将 build/web/ 内容及宣传站 site/dist/ 推送到 gh-pages 孤儿分支

    2026-10-14 事故修复：旧实现用 `git checkout --orphan gh-pages` + `git rm -rf .`
    在主工作树上轮换分支 —— `git rm -rf .` 会把所有已跟踪文件（连同未提交改动）从磁盘
    删光，且 .gitignore 一并被删，后续 `git add -A` 把 keystore/api.env 等机密文件全数
    提交并推上公开仓库；若中途崩溃，主分支工作树就永远停在 gh-pages（本次事故实况）。
    现改为独立 git worktree 承载 gh-pages：主工作树全程不被触碰，无 `--force` 恢复路径，
    脏树直接拒绝部署。
    """
    # 脏树（未提交改动/未跟踪文件）禁部署：worktree 指向同一套对象库，提交虽不会
    # 串到 main，但部署中途人工操作主树、或 push 失败后半途收尾，都容易再把状态搞混
    r = run(['git', 'status', '--porcelain'])
    if r.stdout.strip():
        if allow_dirty:
            log('警告: 工作树有未提交改动，但已指定 --allow-dirty，继续在独立 worktree 中部署...')
        else:
            die('工作树有未提交改动（git status 非空），先 commit 或 stash 再部署。\n'
                + r.stdout[:1500])

    r = run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'])
    original_branch = r.stdout.strip()
    log(f'当前分支: {original_branch}')

    # gh-pages worktree：固定放在 .gh-pages-work（gitignore 覆盖），随用随建随删
    worktree_path = REPO_ROOT / '.gh-pages-work'
    r = run(['git', 'worktree', 'list', '--porcelain'])
    wt_exists = any(line == f'worktree {worktree_path}' for line in r.stdout.splitlines())
    if wt_exists:
        run(['git', 'worktree', 'remove', '--force', str(worktree_path)])

    # 每次部署都重建孤儿分支，使 gh-pages 始终只有 1 个提交（80MB 导出产物不累积历史）
    ghpages_exists = run(['git', 'rev-parse', '--verify', 'refs/heads/gh-pages']).returncode == 0
    if ghpages_exists:
        log('删除旧 gh-pages 分支，重建孤儿分支...')
        run(['git', 'branch', '-D', 'gh-pages'])
    else:
        log('创建 gh-pages 孤儿分支（独立 worktree）...')
    run(['git', 'worktree', 'add', '--orphan', '-b', 'gh-pages', str(worktree_path)])

    try:
        # 复制 Web 导出产物到 worktree 根
        log('复制 Web 导出产物到 gh-pages worktree 根目录...')
        for item in BUILD_DIR.iterdir():
            if item.is_file():
                shutil.copy2(item, worktree_path / item.name)
            else:
                shutil.copytree(item, worktree_path / item.name)

        # 复制宣传站（site/dist）到 worktree 的 site/ 子目录
        if not skip_site:
            if SITE_DIR.exists() and (SITE_DIR / 'index.html').exists():
                log('复制宣传站（site/dist）到 gh-pages worktree site/ 子目录...')
                dest_site = worktree_path / 'site'
                if dest_site.exists():
                    shutil.rmtree(dest_site)
                shutil.copytree(SITE_DIR, dest_site)
                site_size = sum(f.stat().st_size for f in dest_site.rglob('*') if f.is_file())
                site_files = sum(1 for f in dest_site.rglob('*') if f.is_file())
                log(f'宣传站复制完成: {site_files} 个文件, {site_size / 1024 / 1024:.1f} MB')
            else:
                log('未找到 site/dist/index.html，跳过宣传站部署')

        # 提交并推送（cwd 指到 worktree，绝不在主树上做任何事）
        run(['git', 'add', '-A'], cwd=worktree_path)
        commit_msg = f'feat(web): 部署 Web 版与宣传站 {time.strftime("%Y-%m-%d %H:%M")}'
        r = run(['git', 'commit', '-m', commit_msg, '--allow-empty'],
                cwd=worktree_path)
        if r.returncode != 0 and 'nothing to commit' not in (r.stdout or ''):
            log(f'git commit 输出: {r.stdout}')

        log('推送到 origin gh-pages（覆盖远端历史）...')
        r = run(['git', 'push', 'origin', 'gh-pages', '--force-with-lease'])
        if r.returncode != 0:
            if 'up-to-date' in (r.stderr or '') or 'up to date' in (r.stderr or ''):
                log('gh-pages 已是最新，无需推送')
            else:
                die(f'git push 失败: {r.stderr}')

    finally:
        # 只拆 worktree，主工作树自始至终没被碰过，无需任何恢复动作
        log('清理 gh-pages worktree...')
        run(['git', 'worktree', 'remove', '--force', str(worktree_path)])
        run(['git', 'worktree', 'prune'])
        log(f'主分支保持: {original_branch}')


def main():
    parser = argparse.ArgumentParser(
        description='剑士 Web 版与宣传站一键部署到 GitHub Pages')
    parser.add_argument('--skip-export', action='store_true',
                        help='跳过 Godot 导出步骤（使用已有的 build/web/ 产物）')
    parser.add_argument('--skip-site', action='store_true',
                        help='跳过宣传站（site/dist）部署')
    parser.add_argument('--allow-dirty', action='store_true',
                        help='允许在工作树有未提交改动时部署（在独立 worktree 中安全执行）')
    args = parser.parse_args()

    # 若需要同步宣传站，先同步导出游戏最新数据
    if not args.skip_site:
        export_site_script = REPO_ROOT / 'tools' / 'export_site_data.py'
        if export_site_script.exists():
            log('自动同步游戏最新数据到 site/dist/data.js...')
            r = run([sys.executable, str(export_site_script)])
            if r.returncode != 0:
                print(f'⚠ 导出站点数据告警:\n{r.stderr or r.stdout}', file=sys.stderr)

    if not args.skip_export:
        export_web()

    deploy_to_ghpages(skip_site=args.skip_site, allow_dirty=args.allow_dirty)

    print('\n' + '=' * 60)
    print(f'🎉 部署成功！')
    print(f'• 游戏本体: {PAGES_URL}')
    if not args.skip_site:
        print(f'• 宣传站点: {SITE_URL}')
    print(f'• 首次生效需等待 1-2 分钟（GitHub Pages 缓存刷新）')
    print(f'• 后续更新重跑本脚本即可，URL 不变')
    print('=' * 60 + '\n')
    print(f'• 首次生效需等待 1-2 分钟（GitHub Pages 缓存刷新）')
    print(f'• 后续更新重跑本脚本即可，URL 不变')
    print('=' * 60 + '\n')


if __name__ == '__main__':
    main()
