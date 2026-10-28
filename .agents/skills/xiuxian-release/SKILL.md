---
name: xiuxian-release
description: 剑士游戏的 Git 提交存档、双平台推送与版本发布流程。当用户要求提交/commit/存档/git提交、推送/push/推送到平台/推送到云端/双端推送、发布/release/发版/打tag/创建release、版本号加一/apk版本号加一/版本号+1/升级版本/版本递增、构建APK/打apk包时使用。涵盖 Godot 4.7 Android APK 导出构建、一键发布脚本 release.py、双端 Tag 与 Release API 创建、令牌配置与发布后检查清单。位于 .agents/skills/xiuxian-release/SKILL.md。
---

# 剑士 Git 提交与双端版本发布

## Git 提交与双平台同步

- **提交与存档原则（绝对禁止未授权自动操作）**：
  - **严禁自动执行 `git commit`（存档）**！日常代码修改和验证完成后，留在工作区，方便用户自行查看 Diff、测试与确认。
  - **严禁自动执行 `git push`（推送到云端）**！
  - 只有当用户明确指示「提交/存档/commit」时，才执行本地 `git commit`；
  - 只有当用户明确指示「推送/push/推送到云端/发布」时，才执行向远端推送。
- **提交格式**：`<type>(<scope>): <description>`，Type：`feat` / `fix` / `refactor` / `style` / `docs` / `test` / `chore`
- **双平台同步要求**：代码、Git Tag 及 Release 产物必须**同时同步至 GitHub 与 Gitee 两端**：
  - **GitHub 远端**：`origin` (`https://github.com/favoroo/Q-xiuxian.git`)
  - **Gitee 远端**：`gitee` (`https://gitee.com/favo9/q-xiuxian.git`)
  - 代码与标签一次连接同时推：
    ```bash
    git push origin main vX.Y.Z &
    git push gitee main vX.Y.Z &
    wait
    ```

---

## 版本发布流程

当用户明确要求「发布版本 / release / 发版 / 版本号+1 / 构建APK」时执行。

### 0. 前置约定

| 项 | 规范 |
|----|------|
| 构建命令 | 调用 `python3 .agents/skills/xiuxian-release/release.py build --version X.Y.Z`，内部通过 Godot CLI headless 导出 Release APK |
| APK 命名 | `q-xiuxian-v<version>-arm64-v8a.apk`（如 `q-xiuxian-v0.0.1-arm64-v8a.apk`），**两端文件名完全一致** |
| 产物目录 | `build/` |
| Tag 命名 | `v<version>`（如 `v0.0.1`），使用 annotated tag |
| 版本号递增 | **每次发布/打包 APK，版本号必须递增 +1**，禁止同版本覆盖发布。由 `release.py bump` 自动判断：读 `Version.gd` 当前版本 X → 查 tag `vX` → 不存在直接用 X；已存在则 +1 到 X+1 并写回。 |
| 版本来源 | `scripts/autoload/Version.gd` 的 `APP_VERSION` 与 `export_presets.cfg` 的 `version/name`、`version/code` 保持严格一致 |
| 两端一致性 | GitHub 与 Gitee 必须使用相同 Tag、相同 APK 文件名、同为正式 Release（非 draft / prerelease） |
| 更新服务 | `scripts/autoload/UpdateManager.gd` 优先读 Gitee `/releases/latest`，备选 GitHub，并配合国内加速代理 |
| 附件保留策略 | **发布后自动清理双端老 APK 附件**：GitHub 保留最近 10 个（`--keep-gh`）、Gitee 保留最近 3 个（`--keep-gitee`），控制仓库体积与 Gitee 1GB 附件配额 |

### 1. 一键脚本编排

脚本：`.agents/skills/xiuxian-release/release.py`（纯 Python 标准库）。

```text
⓪ 发布前门禁（三条 headless 全绿才允许进 ①，任一失败先修再发）:
   G=/Applications/Godot.app/Contents/MacOS/Godot
   $G --headless --path . res://tests/UnitRunner.tscn    # 数值单测
   $G --headless --path . res://tests/PoolCheck.tscn     # 帧缓存 / 对象池
   $G --headless --path . res://tests/SmokeRunner.tscn   # 全流程冒烟
   —— 判据由 tests/check.gd 出：退出码 0 且末行 *_RESULT: ALL PASS。
   —— 本轮动过 class_name 脚本或 assets/ 素材时，先跑一次 `$G --headless --path . --editor --quit`
      让全局类名与新资源完成导入，否则会出现「素材没注册」的假失败。
① 自动算版本号并写回:  python3 .agents/skills/xiuxian-release/release.py bump --write
   —— 读 Version.gd → 查 tag → 不存在直接用当前版本(预升未发布);已存在则 +1 写回 Version.gd 与 export_presets.cfg
② 执行构建:           python3 .agents/skills/xiuxian-release/release.py build --version X.Y.Z
③ 提交改动:           git add -A && git commit -m "feat(release): 发布剑士 vX.Y.Z"
④ 撰写 Release 说明存为临时文件，执行发布:
   python3 .agents/skills/xiuxian-release/release.py publish --version X.Y.Z --notes-file /tmp/notes.md
   —— 写法见 §3；publish 会校验条数/字数/禁用词，不合规直接拒绝。
④.5 同步游戏内更新记录：在 scripts/data/ChangelogData.gd 顶部追加同版本条目
   （version/date/title/items），items 与本条说明同源、≤4 条；publish 会检查顶条版本。
⑤ 向用户汇报发布验证清单（含两端 URL、APK 附件状态与 SHA-256）
```

- `build` 阶段：校验版本一致性 → Godot headless 导出 Release APK → SHA-256 计算 → 证书指纹核验 → 原子写 `build/release-meta.json`。
- `publish` 阶段：等待构建元数据就绪 → 预检（工作树干净、tag 不存在）→ 创建 annotated tag → **并行**推送双端 → **并行**创建双端 Release → **并行**上传 APK → 幂等可重试 → 双端验证 → 自动清理双端老版本附件（GitHub 保留最近 10 个 / Gitee 保留最近 3 个）。

### 2. 令牌获取（严禁写入任何仓库文件）

脚本按以下顺序自动获取令牌，绝不落盘：
1. 环境变量：`GITHUB_TOKEN`（或 `GH_TOKEN`）、`GITEE_TOKEN`；
2. macOS Keychain（git 凭据库）：`printf 'protocol=https\nhost=github.com\n\n' | git credential fill`（Gitee 同理取 `password`）；
3. 都取不到时提示用户配置。

### 3. Release 说明规范（玩家视角）

**唯一判据：只写玩家进游戏能看见、听见或手感到的变化。** 代码结构、性能余量、内部工具、测试、日志、宣传站一律不写——玩家不关心代码怎么改，只关心玩起来有什么不同。

硬约束：

- 总条目 ≤5 条，每条 ≤25 字（中文计，含标点）。
- 只用三段：`### 新增内容` / `### 调整` / `### 问题修复`。数值增强削弱进「调整」，不要塞进「问题修复」。
- 每条写「玩家看到什么变了」，不写「代码怎么改的」；第一条放最值得玩家知道的变化。
- 末尾 `**SHA-256**` 行保留（游戏内弹窗会自动隐藏）。
- `publish` 调用 `validate_notes()` 校验条数、字数与禁用词，不合规直接拒绝发布；确需跳过加 `--skip-notes-check`。

禁用词（出现即说明写成了开发者视角）：

`池化` `对象池` `节流` `信号` `节点` `await` `渲染器` `工厂` `口径` `探针` `HUD` `合批` `分帧` `重构` `缓存` `日志` `接口` `测试` `站点`

改写示例：

| 别写（开发者视角） | 写成（玩家视角） |
|---|---|
| 静默回血信号节流，HUD 回血演出加量级闸 | 回血提示更克制，不再频繁闪动 |
| 敌群桶分配改池化回收，零稳态分配 | 大量敌人同屏时更流畅 |
| 对话框多帧 await 后补三重验活防孤儿节点 | 修复对话框偶发残留不消失 |
| 机关台穿透加成口径漏判修复 | 修复机关台穿透加成偶尔不生效 |
| 站点图标与移动端视觉优化 | （游戏外改动，不进更新说明） |

模板：

```markdown
## 剑士 vX.Y.Z

### 新增内容
- 每 5 关一次超级悟道五选一
- 金币阁可刷出 ★2 成品武器

### 调整
- 聚灵阵改为单祭坛，每回合金币启动

### 问题修复
- 修复战斗地面消失导致画面过暗

**SHA-256**: `<shasum -a 256 输出>`
```

### 4. 发布检查清单

脚本自动完成：

- [ ] Release 说明通过 `validate_notes()`（≤5 条 / ≤25 字 / 无禁用词）
- [ ] GitHub Release 页面可见，APK 附件已上传（state=uploaded）
- [ ] Gitee Release 页面可见，APK 附件已上传
- [ ] 两端 Tag 一致（`v<version>`）、两端 APK 文件名一致
- [ ] 两端 `/releases/latest` 均指向新 Tag（游戏内更新检测依赖）
- [ ] 双端历史附件已按配额修剪（GitHub 最近 10 版 / Gitee 最近 3 版）

发布者手工确认：

- [ ] 游戏内「更新记录」已追加本版本（`ChangelogData.gd` 顶条版本 == `v<version>`，脚本只告警不拦截）
- [ ] 说明里没有内部黑话、没有游戏外改动（站点/仓库/测试）
