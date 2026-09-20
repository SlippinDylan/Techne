<div align="center">
  <img src="docs/images/readme/app-icon.png" width="160" height="160" alt="Techne app icon">
  <h1>Techne</h1>
</div>

<div align="center">
  <p>A native macOS app for keeping local projects, development servers, WeChat Mini Program commands, and Android APK deployment close at hand.</p>
  <p>
    <a href="docs/README.zh-CN.md">简体中文</a> ·
    <a href="docs/README.zh-TW.md">繁體中文</a> ·
    <strong>English</strong> ·
    <a href="docs/README.ja.md">日本語</a> ·
    <a href="docs/README.ru.md">Русский</a>
  </p>
</div>

## What Techne does

Techne is for developers who keep returning to the same local projects. Add a project explicitly once, then check its Git branch and working tree, run its declared commands, find its listening development server, or open a browser without hunting through terminals. Port scanning can reconcile servers with projects you already manage, but it never adds unknown projects to the list.

Its main project workflows are:

- Web and compiled Mini Program projects are analyzed from their manifests and scripts. Techne can prepare missing dependencies before starting them.
- Native WeChat Mini Programs open and close through the WeChat DevTools CLI without requiring a shell start command.
- Android deployment selects an APK, finds a connected device, installs the APK through ADB, and shows the command output.

## In the app

<table>
  <tr>
    <td width="32%">
      <strong>Projects, Git, and servers</strong><br><br>
      Track a project's current branch and uncommitted files, switch branches when the working tree is clean, and start, stop, or restart its service. Techne finds local listening development servers associated with managed Node, Bun, or Deno projects.
    </td>
    <td width="68%"><img src="docs/images/readme/development-environment.png" alt="Techne development environment with project and server status"></td>
  </tr>
  <tr>
    <td>
      <strong>WeChat Mini Programs</strong><br><br>
      Run declared Taro, UniApp, or Mpx development scripts, or open a native Mini Program in WeChat DevTools. A recovery action asks DevTools to rebuild file watching when newly added pages stop appearing.
    </td>
    <td><img src="docs/images/readme/mini-program-build.png" alt="Techne WeChat Mini Program build workspace"></td>
  </tr>
  <tr>
    <td>
      <strong>Android APK deployment</strong><br><br>
      Choose an APK and a connected Android device. Techne reads the package name, reinstalls the APK with ADB, verifies the package update time, then launches the app.
    </td>
    <td><img src="docs/images/readme/android-deployment.png" alt="Techne Android APK deployment workspace"></td>
  </tr>
</table>

## Install

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask techne@beta
```

### DMG

Download a DMG from the [Techne Releases page](https://github.com/SlippinDylan/Techne/releases), open it, then drag `Techne.app` to `Applications`. The published DMGs are for Apple Silicon Macs.

Current releases are signed with an Apple Development certificate but are not notarized by Apple. macOS may therefore block the first launch or show a developer-verification warning. If you downloaded the DMG from the official Releases page, moved the app to `Applications`, and want to proceed, remove its download quarantine attribute:

```bash
sudo xattr -rd com.apple.quarantine /Applications/Techne.app
```

## Quick start

1. Open Techne and explicitly add a local project. Choose a development-service project or a WeChat Mini Program project.
2. Techne reads the project's real manifest, scripts, package-manager metadata, and lockfiles. It rejects a directory when it cannot identify a runnable project instead of inventing a command.
3. Start the project. For npm, pnpm, Yarn, or Bun projects, missing dependencies are installed automatically; later manifest or lockfile changes trigger preparation again. Commands run through the configured zsh, Bash, or fish login shell.
4. Stop or restart when needed. Normal stop and restart do not clean build caches or close managed browser windows.
5. For a web project, select an installed browser to open its detected server.
6. For Android, open the deployment view, connect a device, select an APK, and deploy it.

Closing the main window leaves projects running in the menu bar. Choosing Quit Techne from the status-item menu safely stops managed project processes before the app exits. When Techne opens, it reconciles surviving shell-based project processes; starting a project first replaces any existing process groups scoped to that project.

### Language

Techne supports English, Simplified Chinese, and Traditional Chinese. It follows the macOS language by default. You can choose a specific language under Settings > General; restart Techne when prompted to apply the change.

### Browsers and isolated profiles

Techne detects Safari, Google Chrome, Chrome Beta, Chromium, Microsoft Edge, Brave, and Arc when they are installed. Safari opens the address normally. Chrome, Chrome Beta, Chromium, Edge, Brave, and Arc are Chromium-based: Techne launches each managed instance in a separate profile directory, opens a new window, and assigns an available remote-debugging port beginning at `9222`. This keeps cookies and site storage separate from your normal browser profile and from other managed instances.

### Web and WeChat Mini Program projects

For shell-based projects, Techne only runs scripts declared by the repository. It recognizes common Web development scripts and WeChat targets used by Taro, UniApp, and Mpx, and supports npm, pnpm, Yarn, and Bun. Dependency installation runs at the detected workspace root while the development command still runs in the selected project directory.

Native Mini Programs with a valid root `project.config.json` use the installed WeChat DevTools CLI for open, close, and file-watching recovery. Compiled Mini Programs use their generated DevTools project directory when it is available. Techne does not bundle Node.js, a package manager, a framework CLI, or WeChat DevTools; the tools required by the project must be installed and available to the login shell.

### Android APK deployment

Install Android SDK Platform-Tools so `adb` is available in `PATH`, connect an Android device with USB debugging enabled, and install Android SDK Build Tools. Techne uses `aapt2` or `aapt` to read the APK package name. It first looks in `PATH`, then in `~/Library/Android/sdk/build-tools`.

## Requirements

| Need | Details |
|---|---|
| macOS | macOS 26 Tahoe or later |
| Hardware | Apple Silicon for the published DMG |
| Git workflows | `git` available in `PATH` for status and branch operations |
| Managed server matching | macOS `lsof`; Techne scans listening TCP ports 3000–9999 and only associates them with projects already added |
| Browser launching | At least one supported browser installed for that feature |
| Web and compiled Mini Programs | Node.js and the project's package manager/framework tools available in the login shell; dependencies themselves may be prepared by Techne |
| Native WeChat Mini Programs | WeChat DevTools installed with its CLI available inside the application bundle |
| Android deployment | `adb`, Android SDK Build Tools (`aapt2` or `aapt`), and a USB-debugging-enabled device |

## Data locations

Project records, command configurations, and logs are stored under:

```bash
~/Library/Application Support/studio.slippindylan.Techne/
```

Managed Chromium instances keep their profile directories and tracking files under:

```bash
~/.techne-browsers/
```

## Build from source

Source builds require macOS 26 or later and Xcode 26 or later. Clone the repository, open `Techne.xcodeproj` in Xcode, and run the `Techne` scheme. From Terminal:

```bash
git clone https://github.com/SlippinDylan/Techne.git
cd Techne
xcodebuild -project Techne.xcodeproj -scheme Techne -configuration Debug build
```

The external tools listed above are only needed for the features that use them.

## License

Copyright © 2025–2026 SlippinDylan Studio. Techne is licensed under the [Apache License 2.0](LICENSE).
