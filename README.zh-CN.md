<div align="center">
  <img src="docs/images/readme/app-icon.png" width="160" height="160" alt="Techne 应用图标">
  <h1>Techne</h1>
  <p>面向本地开发服务、微信小程序和 Android APK 部署的原生 macOS 工作台。</p>
  <p>
    <strong>简体中文</strong> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

## Techne 是什么

Techne 把本地开发中反复出现的杂事收进一个原生 macOS 应用：查看项目 Git 状态和运行中的 Web 服务、启动隔离的 Chrome 调试实例、执行微信小程序命令、部署 Android 应用，以及翻查操作日志。原有工具链不用变，也不必频繁切换终端和其他应用。

## 功能

<table>
  <tr>
    <td width="32%">
      <strong>开发环境</strong><br><br>
      集中管理项目及其 Git 状态，发现本地开发服务，并为每个服务启动带远程调试端口的独立 Chrome 配置文件。
    </td>
    <td width="68%"><img src="docs/images/readme/development-environment.png" alt="Techne 开发环境中的项目与服务状态"></td>
  </tr>
  <tr>
    <td>
      <strong>微信小程序构建</strong><br><br>
      保存小程序项目的构建、清理和停止命令，在同一处执行、切换分支，并在日志面板查看命令输出。
    </td>
    <td><img src="docs/images/readme/mini-program-build.png" alt="Techne 微信小程序构建工作区"></td>
  </tr>
  <tr>
    <td>
      <strong>Android APK 部署</strong><br><br>
      选择 APK，检查已连接设备，通过 ADB 安装，并保留部署输出以便排查问题。
    </td>
    <td><img src="docs/images/readme/android-deployment.png" alt="Techne Android APK 部署工作区"></td>
  </tr>
</table>

## 状态

> **持续开发中**
>
> 核心工作流已实现。每次 push 和 Pull Request 都会校验发布自动化、运行 `TechneTests`，并构建未签名的 Release 应用。按版本发布的 Apple Development 签名与 DMG 发布流程已经配置；当前发布清单关闭了发布。

## 平台与系统要求

| 属性 | 值 |
|---|---|
| 最低系统版本 | macOS 15.0（Sequoia）及以上 |
| 从源码构建 | macOS 15.0 及以上，Xcode 26 及以上 |
| 当前构建架构 | `arm64` 和 `x86_64`（Apple Silicon 和 Intel） |
| 应用形态 | 带菜单栏入口的原生 macOS 应用 |
| 分发方式 | 启用发布时，通过 GitHub Releases 提供按版本发布、Apple Development 签名但未经公证的 DMG |

## 安装与发布

每个 GitHub Release 只包含一个 `Techne-<版本号>.dmg`。打开 DMG 后，将 `Techne.app` 拖到 `Applications`。发布版本使用 Apple Development 证书签名，未经 Apple 公证。首次打开前，请按发布说明移除下载隔离属性：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Techne.app
```

每次 push 和 Pull Request 都会运行发布自动化检查、`TechneTests` 和未签名的 Release 构建。发布配置位于 [`Config/Release/manifest.json`](Config/Release/manifest.json)。只有 main 分支的 CI 成功、`release` 为 `true`、版本尚未发布，并且 [`CHANGELOG.md`](CHANGELOG.md) 存在唯一、非空且与版本完全同名的章节时，发布工作流才会签名、打包并发布 DMG。

支持的版本格式为 `x.y.z`、`x.y.z-alpha.n` 和 `x.y.z-beta.n`。Alpha 和 Beta 后缀用于 Release、tag、DMG 与 Changelog；应用的 `CFBundleShortVersionString` 使用对应的纯数字 `x.y.z`。

发布工作流使用以下 GitHub Actions 仓库密钥：

- `CERTIFICATES_P12`：Base64 编码的 Apple Development P12
- `CERTIFICATES_PASSWORD`：P12 导出密码
- `FEISHU_WEBHOOK`：飞书自定义机器人 Webhook
- `FEISHU_SECRET`：飞书自定义机器人的签名密钥

## 关键设计决策

- **一个本地工作台**：项目 Git 状态、开发服务发现、Chrome 调试、小程序命令、Android 部署和日志集中在同一应用。
- **由文件系统驱动的 Git 更新**：通过 FSEvents 监控每个已添加的 Git 工作区，外部工具造成的分支和工作区变更无需手动刷新即可同步。
- **隔离的浏览器会话**：每个受管理的 Chrome 实例使用独立临时配置目录，并可使用远程调试端口，避免项目之间的浏览器状态互相干扰。
- **可复用的命令模板**：项目类型可从已保存的命令配置开始，同时每个项目保留适合自身工作流的命令。
- **可追溯的操作记录**：关键操作写入带时间戳的日志；Android 部署会检查设备连接和安装结果，不只根据命令结束判断成功。

## 数据位置

应用状态保存在：

```bash
~/Library/Application Support/studio.slippindylan.Techne/
```

受管理浏览器实例的临时信息保存在：

```bash
~/.techne-browsers/
```

## 许可证

Copyright © 2025–2026 SlippinDylan Studio。Techne 使用 [Apache License 2.0](LICENSE) 授权。
