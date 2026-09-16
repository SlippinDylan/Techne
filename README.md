<div align="center">
  <img src="docs/images/readme/app-icon.png" width="160" height="160" alt="Techne app icon">
  <h1>Techne</h1>
  <p>A native macOS workspace for local development services, WeChat Mini Programs, and Android APK deployment.</p>
  <p>
    <a href="docs/README.zh-CN.md">简体中文</a> ·
    <a href="docs/README.zh-TW.md">繁體中文</a> ·
    <strong>English</strong> ·
    <a href="docs/README.ja.md">日本語</a> ·
    <a href="docs/README.ru.md">Русский</a>
  </p>
</div>

## What It Is

Techne brings recurring local-development work into one native macOS app: tracked project Git state, running web servers and isolated Chrome debugging sessions, WeChat Mini Program commands, Android deployment, and operation logs. It keeps your existing project tooling in place while reducing terminal and app switching.

## Features

<table>
  <tr>
    <td width="32%">
      <strong>Development environment</strong><br><br>
      Track projects and their Git state, discover local development servers, and launch isolated Chrome profiles with remote-debugging ports for each server.
    </td>
    <td width="68%"><img src="docs/images/readme/development-environment.png" alt="Techne development environment with project and server status"></td>
  </tr>
  <tr>
    <td>
      <strong>WeChat Mini Program builds</strong><br><br>
      Save a Mini Program project's build, clean, and stop commands, run them from one place, switch branches, and follow command output in the log panel.
    </td>
    <td><img src="docs/images/readme/mini-program-build.png" alt="Techne WeChat Mini Program build workspace"></td>
  </tr>
  <tr>
    <td>
      <strong>Android APK deployment</strong><br><br>
      Select an APK, check the connected device, install it with ADB, and retain deployment output for troubleshooting.
    </td>
    <td><img src="docs/images/readme/android-deployment.png" alt="Techne Android APK deployment workspace"></td>
  </tr>
</table>

## Status

> **Active development**
>
> The core workflows are implemented. Every push and pull request validates release automation, runs `TechneTests`, and builds an unsigned Release app. Version-gated Apple Development signing and DMG publishing are configured; the current release manifest has publishing disabled.

## Platform and System Requirements

| Property | Value |
|---|---|
| Deployment target | macOS 26.0 (Tahoe) or later |
| Source build | macOS 26.0 or later and Xcode 26 or later |
| Release architecture | Apple Silicon (`arm64`) |
| App type | Native, non-sandboxed macOS app with a menu-bar entry |
| Distribution | Version-gated GitHub Releases with an Apple Development-signed, non-notarized DMG when publishing is enabled |

## Installation and Releases

Each GitHub Release contains one `Techne-<version>.dmg`. Open it and drag `Techne.app` into `Applications`. Releases are signed with an Apple Development certificate and are not notarized. Before the first launch, remove the download quarantine attribute as described in the release notes:

```bash
sudo xattr -rd com.apple.quarantine /Applications/Techne.app
```

Every push and pull request runs release-automation checks, `TechneTests`, and an unsigned Release build. Release configuration lives in [`Config/Release/manifest.json`](Config/Release/manifest.json). The release workflow signs, packages, and publishes a DMG only after main CI succeeds, `release` is `true`, the version is unpublished, and [`CHANGELOG.md`](CHANGELOG.md) contains one unique, non-empty section with the exact same version.

Supported versions are `x.y.z`, `x.y.z-alpha.n`, and `x.y.z-beta.n`. Alpha and beta suffixes are used by the release, tag, DMG, and Changelog; the app's `CFBundleShortVersionString` uses the matching numeric `x.y.z` value.

The release workflow uses these GitHub Actions repository secrets:

- `CERTIFICATES_P12`: Base64-encoded Apple Development P12
- `CERTIFICATES_PASSWORD`: P12 export password
- `FEISHU_WEBHOOK`: Feishu custom bot webhook
- `FEISHU_SECRET`: Feishu custom bot signing secret

## Key Design Decisions

- **One local workspace**: project Git state, development-server discovery, Chrome debugging, Mini Program commands, Android deployment, and logs stay in the same app.
- **Filesystem-driven Git updates**: FSEvents monitors each tracked Git workspace so branch and working-tree changes made outside Techne are reflected without a manual refresh.
- **Isolated browser sessions**: each managed Chrome instance receives its own temporary profile directory and can use a remote-debugging port, avoiding cross-project browser-state conflicts.
- **Reusable command templates**: project types can start from saved command configurations, while each project retains the commands it needs for its own workflow.
- **Auditable operations**: key actions write timestamped logs, and Android deployment checks device connection and install results instead of treating command completion alone as success.

## Data Locations

Application state is stored in:

```bash
~/Library/Application Support/studio.slippindylan.Techne/
```

Temporary information for managed browser instances is stored in:

```bash
~/.techne-browsers/
```

## License

Copyright © 2025–2026 SlippinDylan Studio. Techne is licensed under the [Apache License 2.0](LICENSE).
