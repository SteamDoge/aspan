<div align="center">

<img src="apps/aspan/assets/app_icon.png" alt="ASpan" width="88">

# ASpan

**Your cycles, balances and expiry dates, in one place.**

An offline app for time and resource tracking, built with Flutter and Rust.

[![Release](https://img.shields.io/github/v/release/SteamDoge/aspan?include_prereleases&style=flat-square&label=release)](https://github.com/SteamDoge/aspan/releases) [![Downloads](https://img.shields.io/github/downloads/SteamDoge/aspan/total?style=flat-square&logo=github)](https://github.com/SteamDoge/aspan/releases) [![License](https://img.shields.io/badge/license-AGPL--3.0--only-00AEEF?style=flat-square)](LICENSE)<br>
![Android](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white) ![Windows](https://img.shields.io/badge/Windows-0078D4?logo=windows&logoColor=white)

**[Download](#download)** &nbsp;·&nbsp; **[Features](#features)** &nbsp;·&nbsp; **[Getting started](#getting-started)** &nbsp;·&nbsp; **[Build from source](#build-from-source)** &nbsp;·&nbsp; **[Issues](https://github.com/SteamDoge/aspan/issues)**

**English** · [简体中文](README.zh-CN.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/preview-dark.png">
  <img src="docs/images/preview-light.png" alt="The ASpan Home, Projects and Me pages, shown in light and dark themes" width="900">
</picture>

<sub>Home · Projects · Me. Screenshots use sample data and come from UI tests; they are not device acceptance results.</sub>

</div>

## Is ASpan for you?

Subscription renewals, document expiry dates, prepaid passes and home maintenance checks tend to live in different places: a calendar, a notes app, several other apps. It's hard to see what is due and how much is left. ASpan keeps them in one local app:

- **See what needs attention**: the Home page lists the items due in the current period.
- **Track dates and amounts together**: balances, counts and expiry dates sit next to each cycle.
- **Keep a record of every change**: top-ups, charges and corrections all leave an entry you can review.
- **No account, no network**: your data stays on your device.

It's for you if you want recurring tasks and remaining amounts in one place. If you need system notifications, reminders at an exact time or sync between devices, it doesn't do that yet. The interface is currently in Simplified Chinese only. Runs on Android 7.0+ and Windows 10/11 x64.

## Features

- **One place for everyday cycles**: subscriptions and bills, to-dos, birthdays, maintenance checks, prepaid passes and document expiry dates; 23 built-in templates, and you can save your own.
- **Dates and resources side by side**: one-off, daily, weekly, monthly, yearly and reset-on-completion cycles, with balances, counts and expiry dates; see progress in the current period and the in-app reminder plan.
- **Stay organized**: group rules by project and tag, search all rules, and show related rules together while each keeps its own history.
- **A record of every change**: confirming, topping up or charging adds an entry; corrections keep the original entry and the fix, and forecasts never write to the ledger.
- **Data stays on your device**: export and restore a full JSON backup; the backup is checked before restoring, and a checkpoint is kept from before the restore.
- **Fits phones and desktops**: four color schemes, light and dark modes you can switch on their own, a floating navigation bar on narrow screens and a sidebar on wide ones.
- **Open source**: original code under **AGPL-3.0-only**; third-party licenses and notices are kept intact.

The reminder plan is only shown inside the app. **System notifications, exact times, time zones/DST and automatic posting are not implemented yet.** There is no in-app way to roll back to a restore checkpoint yet. The interface is only available in Simplified Chinese. No feature needs an internet connection.

## Download

Current version: [**rc0.0.5**](https://github.com/SteamDoge/aspan/releases/tag/rc0.0.5) (0.0.5-rc.1+9). See [all releases](https://github.com/SteamDoge/aspan/releases) for changes and packages.

| Platform | Download | Which one |
| --- | --- | --- |
| Android 7.0+ (API 24+) | [![APK ARM64](https://img.shields.io/badge/APK-ARM64-168039?logo=android)](https://github.com/SteamDoge/aspan/releases/download/rc0.0.5/ASpan-rc0.0.5-android-arm64-v8a.apk) | Most phones |
| Android x86_64 | [![APK x86_64](https://img.shields.io/badge/APK-x86__64-45BF55?logo=android)](https://github.com/SteamDoge/aspan/releases/download/rc0.0.5/ASpan-rc0.0.5-android-x86_64.apk) | x86_64 devices and emulators |
| Windows 10/11 x64 | [![Portable x64](https://img.shields.io/badge/Portable-x64-2D7D9A)](https://github.com/SteamDoge/aspan/releases/download/rc0.0.5/ASpan-rc0.0.5-windows-x64.zip) | Extract the whole folder and run `aspan.exe` |

<sub>Extract the whole Windows portable package and keep the DLLs and `data/`. It is not code-signed, so Windows may warn you on first run. There are no ARMv7, Windows ARM64, macOS, Linux or iOS packages yet. ARM64 physical devices, the final Windows GUI and the full device matrix have not been verified; see the [release](https://github.com/SteamDoge/aspan/releases/tag/rc0.0.5) for details. Check packages against [SHA256SUMS](https://github.com/SteamDoge/aspan/releases/download/rc0.0.5/SHA256SUMS).</sub>

## Getting started

**1 · Install.** On Android, install the APK for your device. On Windows, extract the portable ZIP and keep the DLLs and `data/` next to `aspan.exe`; copying only the EXE won't work.

**2 · Add a rule.** On the **Projects** (项目) page, create a rule or pick a template, then check its dates, cycle and resource settings.<br><sub>A template keeps the dates it was saved with, so check them before use.</sub>

**3 · Handle the current period.** On the **Home** (主页) page, see what is due and confirm, top up, charge or skip it.

**4 · Back up.** On the **Me** (我的) page, change the look, manage templates and export a full backup regularly.

Export a backup before upgrading. An Android build signed with the old Debug key can't be upgraded in place by a new one. Uninstalling the Android app usually deletes its data, so don't uninstall in place of making a backup.

## Build from source

<details>
<summary>Show requirements, build commands and tests</summary>

### Requirements

This version was verified with **Flutter 3.47.7** (Dart 3.13.5), **Rust 1.98.1** and **PowerShell 7**. Dependency versions are locked in `Cargo.lock` and `apps/aspan/pubspec.lock`; the first dependency restore needs network access or a complete cache. The scripts build Windows and Android on a Windows host.

- Windows: Visual Studio with the Desktop development with C++ workload, the Windows SDK and the Rust MSVC toolchain. The scripts create plugin junctions, so the system must allow symbolic links or junctions.
- Android: JDK 21, the Android SDK, NDK **28.2.13676358** and the Rust targets `aarch64-linux-android` and `x86_64-linux-android`; the project pins AGP 9.1.0, Kotlin 2.4.0 and Gradle 9.3.1, and the Gradle distribution SHA-256 is fixed.
- Put `flutter` and `cargo` on the PATH of the current process, or pass `-Flutter` to the scripts. You can also set the `flutter`, `java` and `androidSdk` paths in the git-ignored `.tools/toolchains.json`; no SDK goes into the repository.

### Build

```powershell
git clone https://github.com/SteamDoge/aspan.git
cd aspan

# Development run: builds the Rust native library, then starts the Windows app
pwsh -File scripts/run.ps1

# Windows package
pwsh -File scripts/build.ps1 -Platform windows

# Android packages (Debug signing)
pwsh -File scripts/build.ps1 -Platform android -Configuration Debug `
  -AndroidSdk 'YOUR_ANDROID_SDK_DIR' -Java 'YOUR_JDK_DIR'
```

The Windows output is in `apps/aspan/build/windows/x64/runner/Release/`; keep the DLLs and `data/` from the whole folder. The Android output is in `apps/aspan/build/app/outputs/flutter-apk/`, split into ARM64 and x86_64. Running `flutter run` directly skips preparing the Rust library, so use `scripts/run.ps1`. Run checks and builds of the same Flutter project one at a time.

### Android signing

Before a Release build, create and safely store your own signing key, then add the git-ignored `apps/aspan/android/key.properties`:

```properties
storeFile=C:/YOUR_PATH/your-release-key.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

Use an absolute path for `storeFile`, then change `-Configuration Debug` to `Release` in the command above. These placeholders are not real credentials. Never commit this file or the key. A package signed with one certificate can't be installed over one signed with another; export a backup in the app first if you want to keep your data.

### Tests

Full check (Rust format, tests, Clippy and native library build; Dart format, Flutter analysis and tests):

```powershell
pwsh -File scripts/check.ps1
```

Or step by step (the script also handles plugin junctions and dependency restore, so prefer it):

```powershell
cargo fmt --all -- --check
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo build -p aspan-runtime --locked
$env:ASPAN_RUST_LIB = (Resolve-Path target/debug/aspan_bridge.dll).Path
Push-Location apps/aspan
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
Pop-Location
```

Run the Windows integration tests with `pwsh -File scripts/native-check.ps1`. They use separate temporary data and never touch personal data.

</details>

## Project structure

| Path | Responsibility |
| --- | --- |
| `apps/aspan` | Flutter UI and platform integration; calls the Rust native library through `dart:ffi` |
| `crates/core` | Date cycles, rules, fixed-precision resources, idempotent posting, corrections and integrity checks |
| `crates/runtime` | SQLite transactions, JSON C ABI, backups and CLI |
| `scripts` | Checks, running, local builds and release candidate packaging and verification |
| `licenses` | Third-party license texts |

## Privacy

ASpan doesn't go online. It needs no account, collects no usage statistics or crash reports, and has no feature that sends data anywhere. Rules, entries and settings are stored in a SQLite database on your device; only the JSON backups you export yourself leave the app.

<sub>On Windows, data is stored at `ASpan/v1/aspan.sqlite3` in the system's application support folder; on Android, it is in the app's private storage. Backup imports are limited to 50 MiB.</sub>

## Feedback and contributing

Report problems or ideas in [GitHub Issues](https://github.com/SteamDoge/aspan/issues). Include the app version, platform, architecture, steps to reproduce and what you expected; remove personal data from logs and screenshots first. Focused pull requests are welcome: start new original source files with `SPDX-License-Identifier: AGPL-3.0-only` and the copyright line, and run `pwsh -File scripts/check.ps1` before submitting.

If ASpan is useful to you, a ⭐ helps others find it.

## License

The original code of this project is licensed under **AGPL-3.0-only**; the full official GNU text is in [LICENSE](LICENSE). There are no extra non-commercial or no-modification restrictions. If you distribute a modified version, or offer one to users over a network, follow the license's source-code obligations.

Third-party code, dependencies, Flutter project templates, the engine, fonts and assets keep their own licenses and copyright notices (see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [licenses/](licenses/)); this project's license does not change them. Each binary distribution still needs its bundled components and runtime library notices checked.
