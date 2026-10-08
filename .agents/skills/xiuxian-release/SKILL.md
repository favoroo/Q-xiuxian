---
name: xiuxian-release
description: 修仙幸存者游戏的 Git 提交存档、双平台推送与版本发布流程。当用户要求提交/commit/存档/git提交、推送/push/推送到平台/推送到云端/双端推送、发布/release/发版/打tag/创建release、版本号加一/apk版本号加一/版本号+1/升级版本/版本递增、构建APK/打apk包时使用。涵盖 Godot 4.7 Android APK 导出构建、一键发布脚本 release.py、双端 Tag 与 Release API 创建、令牌配置与发布后检查清单。位于 .agents/skills/xiuxian-release/SKILL.md。
---

# 修仙幸存者 Git 提交与双端版本发布

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

### 1. 一键脚本编排

脚本：`.agents/skills/xiuxian-release/release.py`（纯 Python 标准库）。

```text
① 自动算版本号并写回:  python3 .agents/skills/xiuxian-release/release.py bump --write
   —— 读 Version.gd → 查 tag → 不存在直接用当前版本(预升未发布);已存在则 +1 写回 Version.gd 与 export_presets.cfg
② 执行构建:           python3 .agents/skills/xiuxian-release/release.py build --version X.Y.Z
③ 提交改动:           git add -A && git commit -m "feat(release): 发布修仙幸存者 vX.Y.Z"
④ 撰写 Release 说明存为临时文件，执行发布:
   python3 .agents/skills/xiuxian-release/release.py publish --version X.Y.Z --notes-file /tmp/notes.md
⑤ 向用户汇报发布验证清单（含两端 URL、APK 附件状态与 SHA-256）
```

- `build` 阶段：校验版本一致性 → Godot headless 导出 Release APK → SHA-256 计算 → 证书指纹核验 → 原子写 `build/release-meta.json`。
- `publish` 阶段：等待构建元数据就绪 → 预检（工作树干净、tag 不存在）→ 创建 annotated tag → **并行**推送双端 → **并行**创建双端 Release → **并行**上传 APK → 幂等可重试 → 双端验证 → 自动清理双端老版本附件（保留最近 20 个）。

### 2. 令牌获取（严禁写入任何仓库文件）

脚本按以下顺序自动获取令牌，绝不落盘：
1. 环境变量：`GITHUB_TOKEN`（或 `GH_TOKEN`）、`GITEE_TOKEN`；
2. macOS Keychain（git 凭据库）：`printf 'protocol=https\nhost=github.com\n\n' | git credential fill`（Gitee 同理取 `password`）；
3. 都取不到时提示用户配置。

### 3. Release 说明规范

**应用内更新弹窗显示说明**，文案务必精炼：**总条目 ≤5 条，每条 ≤25 字**。

```markdown
## 修仙幸存者 vX.Y.Z

### 新增内容
- 优化灵田战斗波次与出怪手感
- 支持应用内热更新检查与静默下载

### 问题修复
- 修复若干已知界面交互异常

**SHA-256**: `<shasum -a 256 输出>`
```

### 4. 发布后检查清单（脚本 publish 阶段自动完成）

- [ ] GitHub Release 页面可见，APK 附件已上传（state=uploaded）
- [ ] Gitee Release 页面可见，APK 附件已上传
- [ ] 两端 Tag 一致（`v<version>`）、两端 APK 文件名一致
- [ ] 两端 `/releases/latest` 均指向新 Tag（游戏内更新检测依赖）
- [ ] 双端历史附件已按配额修剪（保留最近 20 版）
