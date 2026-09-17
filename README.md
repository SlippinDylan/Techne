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

Techne is for developers who keep returning to the same local projects. Add a project once, then check its Git branch and working tree, run its own commands, find listening development servers, or open a browser for a server without hunting through terminals.

It also keeps two separate workflows in the same app:

- WeChat Mini Program projects run the commands you configure for installing dependencies, starting, building, cleaning, and stopping.
- Android deployment selects an APK, finds a connected device, installs the APK through ADB, and shows the command output.

## In the app

<table>
  <tr>
    <td width="32%">
      <strong>Projects, Git, and servers</strong><br><br>
      Track a project's current branch and uncommitted files, switch branches when the working tree is clean, and start or stop its configured service. Techne finds local listening development servers associated with Node, Bun, or Deno processes.
    </td>
    <td width="68%"><img src="docs/images/readme/development-environment.png" alt="Techne development environment with project and server status"></td>
  </tr>
  <tr>
    <td>
      <strong>WeChat Mini Programs</strong><br><br>
      Save commands per project instead of relying on a fixed build system. Built-in command templates include npm and pnpm examples for WeChat Mini Programs.
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

1. Open Techne and add a local project. Choose a development-service project or a WeChat Mini Program project.
2. Select a command template or enter the commands that already work for that project. Techne runs them in the project directory through your login Bash shell.
3. For a web project, start its service and refresh the development environment. Select an installed browser to open a detected server.
4. For Android, open the deployment view, connect a device, select an APK, and deploy it.

### Browsers and isolated profiles

Techne detects Safari, Google Chrome, Chrome Beta, Chromium, Microsoft Edge, Brave, and Arc when they are installed. Safari opens the address normally. Chrome, Chrome Beta, Chromium, Edge, Brave, and Arc are Chromium-based: Techne launches each managed instance in a separate profile directory, opens a new window, and assigns an available remote-debugging port beginning at `9222`. This keeps cookies and site storage separate from your normal browser profile and from other managed instances.

### WeChat Mini Program commands

Techne does not bundle a Mini Program toolchain. Install the dependencies required by the project, then set commands that work in that repository. The included examples are:

```bash
npm run dev:mp-weixin
npm run build:mp-weixin
pnpm dev:mp-weixin
pnpm build:mp-weixin
```

You can replace these with the project's own npm, pnpm, or other shell commands. The required package manager and any project-specific tools must be available in your login shell's `PATH`.

### Android APK deployment

Install Android SDK Platform-Tools so `adb` is available in `PATH`, connect an Android device with USB debugging enabled, and install Android SDK Build Tools. Techne uses `aapt2` or `aapt` to read the APK package name. It first looks in `PATH`, then in `~/Library/Android/sdk/build-tools`.

## Requirements

| Need | Details |
|---|---|
| macOS | macOS 26 Tahoe or later |
| Hardware | Apple Silicon for the published DMG |
| Git workflows | `git` available in `PATH` for status and branch operations |
| Development-server discovery | macOS `lsof`; Techne scans listening TCP ports 3000–9999 |
| Browser launching | At least one supported browser installed for that feature |
| Mini Program and project commands | The project's dependencies and command-line tools available in the login shell |
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
