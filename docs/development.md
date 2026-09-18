# Techne 开发与验证

本文记录本地开发、测试、发布自动化和开发产物清理规则。用户安装与使用方式见 [README.md](../README.md)，系统边界见 [architecture.md](architecture.md)。

## 环境

- macOS 26 或更高版本
- Xcode 26 或更高版本
- Apple Silicon 用于与发布产物一致的本地验证
- Node.js，用于发布清单和 GitHub 自动化测试

Swift Package Manager 会解析 Sparkle、SwiftGitX 和 libgit2。Node.js、包管理器、微信开发者工具、ADB 和 Android Build Tools 只在验证对应产品能力时需要。

## 打开项目

在 Xcode 中打开 `Techne.xcodeproj`，选择 `Techne` scheme。命令行构建也使用同一 project 和 scheme。

项目最低部署版本是 macOS 26。不要通过降低 deployment target 规避 API 可用性问题。

## 测试

修改后先运行直接相关的测试：

```bash
xcodebuild test \
  -project Techne.xcodeproj \
  -scheme Techne \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build-local-tests \
  -only-testing:TechneTests/<SuiteName> \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

跨模块、持久化、进程、窗口或发布前变更运行完整测试：

```bash
xcodebuild test \
  -project Techne.xcodeproj \
  -scheme Techne \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build-local-tests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

测试必须使用临时目录或注入的 `PersistenceRoot`。不得读取、覆盖或清理用户真实的 Application Support 数据。

## 构建

常规 Debug 构建：

```bash
xcodebuild build \
  -project Techne.xcodeproj \
  -scheme Techne \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build-local-debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

需要验证发布配置时使用 unsigned Release 构建：

```bash
xcodebuild build \
  -project Techne.xcodeproj \
  -scheme Techne \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build-local-release \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

常规任务不要重复启动应用或依赖开发者本地正在运行的 watch 流程。UI 改动完成构建和相关测试后交给用户视觉验收，除非用户明确要求运行应用或分析截图。

## 自动化检查

发布和 CI 脚本使用 Node.js 原生测试：

```bash
bash -n Scripts/create-dmg.sh
Scripts/create-dmg.sh --help >/dev/null
node .github/scripts/release-manifest.mjs validate
node --test .github/scripts/*.test.mjs
```

`.github/workflows/ci.yml` 对纯 README、LICENSE、AGENTS 和 docs 改动跳过 macOS 构建，但仍运行轻量自动化检查。其他改动在 macOS 26 runner 上执行完整测试和 unsigned Release 构建，并验证架构、最低系统版本、Sparkle 配置和应用产物。

## 发布配置

`Config/Release/manifest.json` 是发布版本和发布开关的唯一编辑入口：

```json
{
  "version": "x.y.z-beta.n",
  "release": false
}
```

版本支持 stable、alpha 和 beta。启用发布前，`CHANGELOG.md` 必须存在完全匹配的版本标题和有效日期。不要手工修改由自动化推导的 tag、DMG 名称、Marketing Version、更新频道或预发布状态。

Release workflow 只处理 `main` 分支上已经通过 CI 的 commit。它构建 arm64 应用、使用 Apple Development 证书签名、生成 DMG 并发布 GitHub Release。发布完成后，它通过 repository dispatch 触发独立的 `publish-distribution-metadata.yml`，由后者更新 Homebrew Cask 和 Sparkle appcast；Release workflow 不等待该同步任务完成。

证书、密码和签名密钥只存放在 GitHub Secrets，不写入仓库、日志或 Memory。

## 数据位置

应用状态：

```text
~/Library/Application Support/studio.slippindylan.Techne/
```

受管理 Chromium 实例：

```text
~/.techne-browsers/
```

这两个目录包含用户数据，不属于普通构建缓存。测试和开发清理不得删除它们。

## 开发产物清理

仓库内的下列目录可安全重新生成：

```text
.build/
build/
DerivedData/
.deriveddata/
build-local-*/
```

只有用户明确要求清理时才删除。执行前先用 `du` 统计目标，确认实际路径属于当前仓库；清理后再次统计并报告每项与总释放空间。

仓库外的 `/tmp`、`/private/tmp` 和 `/private/var/folders` 可能包含其他项目或系统进程的数据。只有目标能通过绝对路径、项目名、构建元数据或当前进程可靠归因于 Techne，且内容可重新生成时才可删除。无法确认归属时保留并报告。

禁止清理：

- `App/`、`Tests/`、`Config/`、`.github/`、`Scripts/` 和 `docs/`
- `.git/`、Xcode project、scheme、entitlements、Info.plist 和 Package.resolved
- Application Support、`.techne-browsers` 或用户选择的项目目录
- 用途不明的系统缓存和其他应用数据

## 完成检查

```bash
git diff --check
git status --short
```

确认测试或构建结果与本次最终改动对应；如果验证后又修改了代码，重新运行受影响的检查。不要把 `build-local-*`、测试结果、临时日志或调试输出加入提交。
