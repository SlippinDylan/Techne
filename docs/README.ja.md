<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Techne のアプリアイコン">
  <h1>Techne</h1>
  <p>ローカル開発環境、WeChat ミニプログラムのビルド、Android デプロイを一つにまとめ、メニューバーからも操作できるネイティブ macOS アプリです。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <strong>日本語</strong> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

## Techne について

Techne は、フロントエンドのローカル開発で発生する作業を一か所にまとめます。プロジェクトと Git の状態管理、起動中の dev server の検出、隔離された Chrome デバッグインスタンスの起動、WeChat ミニプログラムのビルド、ADB による Android App のデプロイに対応しています。よく使うプロジェクトを追加すれば、サービスの起動、ブランチ切り替え、ログ確認、デプロイを同じ画面から行えます。

## 機能

<table>
  <tr>
    <td width="32%">
      <strong>開発環境とデバッグ</strong><br><br>
      プロジェクトをまとめて管理し、Git ブランチ、未コミットの変更、サービスの状態を表示します。ローカルの dev server を自動検出し、隔離 profile とリモートデバッグポートを使った Chrome をサービスごとに起動できます。
    </td>
    <td width="68%"><img src="images/readme/development-environment.png" alt="Techne の開発環境とデバッグ画面"></td>
  </tr>
  <tr>
    <td>
      <strong>WeChat ミニプログラムのビルド</strong><br><br>
      ミニプログラムのプロジェクトパスと、ビルド、クリーン、停止コマンドを保存できます。ワンクリックでビルド、キャッシュのクリーン、ブランチ切り替えを実行し、ログパネルで出力をリアルタイムに確認できます。
    </td>
    <td><img src="images/readme/mini-program-build.png" alt="Techne の WeChat ミニプログラムビルド画面"></td>
  </tr>
  <tr>
    <td>
      <strong>Android App のデプロイ</strong><br><br>
      APK を選択してデバイスを接続すると、<code>adb install</code> とログ取得を実行できます。デバイス接続確認、インストール進捗、タイムスタンプ検証にも対応しています。
    </td>
    <td><img src="images/readme/android-deployment.png" alt="Techne の Android App デプロイ画面"></td>
  </tr>
</table>

## 開発状況

> **開発を継続しています**

主要なワークフローは実装済みです。すべての push と Pull Request で、自動化スクリプトテスト、`TechneTests`、未署名の Release ビルドを実行します。現在のリリースマニフェストは、main CI の成功後に `0.1.0-beta.1` を公開する設定です。

## 動作環境

| 項目 | 内容 |
|---|---|
| 最低 OS | macOS 26.0 Tahoe |
| ソースからのビルド | macOS 26.0 以降と Xcode 26 以降 |
| リリースアーキテクチャ | Apple Silicon（`arm64`） |
| アプリ形式 | サンドボックスを使用しないネイティブ macOS アプリ。メニューバーから操作可能 |
| ローカル開発 | ローカル開発サービスの検出と、隔離された Chrome デバッグインスタンスの起動に対応 |
| 配布形式 | Apple Development 署名済み、未公証の DMG を GitHub Releases で配布 |

## インストールとリリース

各 GitHub Release には `Techne-<バージョン>.dmg` が 1 つ含まれます。DMG を開き、`Techne.app` を `Applications` にドラッグしてください。現在のリリースは Apple Development 証明書で署名されていますが、Apple の公証は受けていません。初回起動前にダウンロード隔離属性を削除してください。

```bash
sudo xattr -rd com.apple.quarantine /Applications/Techne.app
```

リリース設定は [`Config/Release/manifest.json`](../Config/Release/manifest.json) にあります。`main` への push の CI が成功し、`release` が `true`、そのバージョンが未公開で、[CHANGELOG.md](../CHANGELOG.md) に完全一致する一意かつ空でないバージョンセクションがある場合に限り、Release workflow が DMG を署名、パッケージ化、公開します。

バージョン形式は `x.y.z`、`x.y.z-alpha.n`、`x.y.z-beta.n` に対応しています。Alpha／Beta の接尾辞は Release、tag、DMG、CHANGELOG に使用され、App の `CFBundleShortVersionString` には対応する数字のみの `x.y.z` を使用します。

## 主な設計方針

- プロジェクトを中心にローカル開発フローを管理し、Git の状態、サービスの状態、よく使う操作を同じ画面にまとめます。
- 隔離された Chrome profile でデバッグインスタンスを起動し、複数のフロントエンドプロジェクト間で cookie やストレージが干渉しないようにします。
- ミニプログラムのビルド、クリーン、停止コマンドと、プロジェクト種別ごとのコマンドテンプレートを集約します。
- 起動、停止、ビルド、デプロイ、ブランチ切り替えなどの主要操作を時系列ログに記録し、カテゴリで絞り込めます。

## データの保存先

アプリケーションの状態は次の場所に保存されます。

```bash
~/Library/Application Support/studio.slippindylan.Techne/
```

ブラウザデバッグインスタンスの一時情報は次の場所に保存されます。

```bash
~/.techne-browsers/
```

## ライセンス

Copyright © 2025–2026 SlippinDylan Studio. Techne は [Apache License 2.0](../LICENSE) で公開されています。
