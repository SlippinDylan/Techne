<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Techne 应用图标">
  <h1>Techne</h1>
</div>

<div align="center">
  <p>把本地项目、开发服务、微信小程序命令和 Android APK 部署放在一起的原生 macOS 应用。</p>
  <p>
    <strong>简体中文</strong> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

## Techne 能做什么

Techne 适合反复处理同一批本地项目的开发者。项目只需手动添加一次，之后就能查看 Git 分支和工作区、运行项目实际声明的命令、查找其监听中的开发服务，或直接打开浏览器。端口扫描只会关联已经管理的项目，不会把未知项目自动加入列表。

主要工作流包括：

- Techne 会根据清单和脚本识别 Web 项目及需要编译的微信小程序，并在启动前自动准备缺失的依赖。
- 原生微信小程序通过微信开发者工具 CLI 打开和关闭，不需要 Shell 启动命令。
- Android 部署可选择 APK、查找已连接设备、通过 ADB 安装，并显示命令输出。

## 应用内功能

<table>
  <tr>
    <td width="32%">
      <strong>项目、Git 与服务</strong><br><br>
      查看当前分支和未提交文件；工作区干净时可切换分支；启动、停止或重启服务。Techne 会查找与已管理 Node、Bun 或 Deno 项目关联的本地监听服务。
    </td>
    <td width="68%"><img src="images/readme/development-environment.png" alt="Techne 中的项目和服务状态"></td>
  </tr>
  <tr>
    <td>
      <strong>微信小程序</strong><br><br>
      运行项目声明的 Taro、UniApp 或 Mpx 开发脚本，也可在微信开发者工具中打开原生小程序。新增页面未被识别时，可让开发者工具重建文件监听。
    </td>
    <td><img src="images/readme/mini-program-build.png" alt="Techne 微信小程序构建工作区"></td>
  </tr>
  <tr>
    <td>
      <strong>Android APK 部署</strong><br><br>
      选择 APK 和已连接的 Android 设备。Techne 读取包名，通过 ADB 重装 APK、核对包更新时间，然后启动应用。
    </td>
    <td><img src="images/readme/android-deployment.png" alt="Techne Android APK 部署工作区"></td>
  </tr>
</table>

## 安装

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask techne@beta
```

### DMG

从 [Techne Releases](https://github.com/SlippinDylan/Techne/releases) 下载 DMG，打开后将 `Techne.app` 拖到 `Applications`。已发布的 DMG 面向 Apple Silicon Mac。

当前版本使用 Apple Development 证书签名，但未经过 Apple 公证。macOS 因此可能阻止首次打开，或显示无法验证开发者的提示。如果 DMG 来自官方 Releases、应用已移到 `Applications`，且你决定继续使用，可移除下载隔离属性：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Techne.app
```

## 快速开始

1. 打开 Techne，手动添加一个本地项目，选择开发服务或微信小程序项目。
2. Techne 会读取项目中的清单、脚本、包管理器信息和锁文件。无法识别可运行项目时，Techne 会拒绝添加，不会猜测命令。
3. 启动项目。npm、pnpm、Yarn 或 Bun 项目缺少依赖时会自动安装；清单或锁文件后来发生变化时会再次准备。命令通过已配置的 zsh、Bash 或 fish 登录 shell 执行。
4. 按需停止或重启。普通停止和重启不会清理构建缓存，也不会关闭受管理的浏览器窗口。
5. Web 项目可选择已安装的浏览器打开检测到的服务。
6. Android 部署页中连接设备、选择 APK，然后部署。

关闭主窗口后，项目会继续在菜单栏后台运行；从菜单栏选择“退出 Techne”时，应用会先安全停止受管理的项目进程再退出。Techne 启动时会恢复仍然存活的 Shell 项目状态；点击启动会先替换该项目目录下已有的进程组，避免重复运行。

### 语言

Techne 支持英文、简体中文和繁体中文，默认跟随 macOS。你也可以在“设置 > 通用”中指定语言，并按提示重启 Techne 使更改生效。

### 浏览器与独立 profile

Techne 会检测已安装的 Safari、Google Chrome、Chrome Beta、Chromium、Microsoft Edge、Brave 和 Arc。Safari 按普通方式打开地址。Chrome、Chrome Beta、Chromium、Edge、Brave 和 Arc 使用 Chromium 内核：每个受管理实例都有独立 profile、新窗口和远程调试端口，端口从 `9222` 起自动寻找可用值。这样不会复用日常浏览器或其他受管理实例的 cookie 与站点存储。

### Web 与微信小程序项目

对于通过命令行启动的项目，Techne 只运行仓库实际声明的脚本。它能识别常见 Web 开发脚本，以及 Taro、UniApp、Mpx 的微信目标，并支持 npm、pnpm、Yarn 和 Bun。依赖会在识别到的 workspace 根目录安装，开发命令仍在所选项目目录执行。

根目录存在有效 `project.config.json` 的原生小程序通过已安装的微信开发者工具 CLI 打开、关闭和恢复文件监听。需要编译的小程序在生成开发者工具项目目录后，也会使用该目录执行文件监听恢复。Techne 不内置 Node.js、包管理器、框架 CLI 或微信开发者工具；项目需要的运行时和工具仍须安装，并能被登录 shell 找到。

### Android APK 部署

安装 Android SDK Platform-Tools，使 `adb` 在 `PATH` 中可用；连接已开启 USB 调试的 Android 设备；再安装 Android SDK Build Tools。Techne 用 `aapt2` 或 `aapt` 读取 APK 包名，先从 `PATH` 查找，再查找 `~/Library/Android/sdk/build-tools`。

## 系统要求

| 项目 | 要求 |
|---|---|
| macOS | macOS 26 Tahoe 或更高版本 |
| 硬件 | 已发布 DMG 仅支持 Apple Silicon |
| Git 功能 | `git` 在 `PATH` 中，供状态和分支操作使用 |
| 已管理服务关联 | macOS 自带的 `lsof`；Techne 扫描 3000–9999 的 TCP 监听端口，只关联已经添加的项目 |
| 浏览器启动 | 至少安装一个受支持浏览器 |
| Web 与编译型小程序 | Node.js、项目所用包管理器和框架工具能被登录 shell 找到；项目依赖可由 Techne 准备 |
| 原生微信小程序 | 已安装微信开发者工具，且应用包内包含 CLI |
| Android 部署 | `adb`、Android SDK Build Tools（`aapt2` 或 `aapt`）和已开启 USB 调试的设备 |

## 数据位置

项目记录、命令配置和日志存放在：

```bash
~/Library/Application Support/studio.slippindylan.Techne/
```

受管理 Chromium 实例的 profile 和跟踪文件存放在：

```bash
~/.techne-browsers/
```

## 从源码构建

需要 macOS 26 或更高版本，以及 Xcode 26 或更高版本。克隆仓库后，在 Xcode 打开 `Techne.xcodeproj` 并运行 `Techne` scheme；也可以在终端执行：

```bash
git clone https://github.com/SlippinDylan/Techne.git
cd Techne
xcodebuild -project Techne.xcodeproj -scheme Techne -configuration Debug build
```

上面列出的外部工具仅在使用对应功能时需要。

## 许可证

Copyright © 2025–2026 SlippinDylan Studio。Techne 使用 [Apache License 2.0](../LICENSE) 授权。
