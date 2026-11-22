# DSM Helper

[中文](README.md) | [English](README_EN.md)

A mobile client for Synology DSM, featuring a soft neumorphic UI.

## Download

**Android APK (built from this repository, 0.0.155)**

- File: [dsm_helper-0.0.155-release.apk](release/dsm_helper-0.0.155-release.apk)
- SHA-256: `8a0421868ece890cd4ec7eeeacf2ec83b13202f67ff45c27f7b1a0d8ffe4b63f`
- Requirements: Android 5.0+ (API 21), arm64-v8a

> This APK uses a local test signing key and is **not** signed with the official key. Uninstall the official app before installing this build, otherwise Android will report a signature conflict. Uninstalling removes local app data.
>
> If the NAS rejects a large upload with HTTP 413, the request-body limit on the NAS side (DSM nginx / reverse proxy) is too small. Increase `client_max_body_size` on the NAS.

Official / historical builds: https://gitee.com/apaipai/dsm_helper/releases

## What's new in 0.0.155

- **Background photo backup**: a new Android foreground service plus WakeLock / Wi-Fi lock and a progress notification keeps album backups running when the screen is off or the app is in the background. The service stops automatically when the backup finishes, is paused, or fails.
- **Large file upload fixes**:
  - Uploads are streamed from disk, so 4GB/10GB files are never loaded into memory.
  - HTML error pages, empty responses and HTTP 413 are handled safely; the app no longer crashes in `json.decode`.
  - Files larger than 2GB no longer send the optional `size` / `mtime` fields that some DSM builds parse as 32-bit integers.
  - Album backup falls back to `asset.file` when `originFile` is null.
- **Skip existing files**: before uploading, the app checks the destination folder with `SYNO.FileStation.List` / `getinfo`. If a file with the same name already exists, it is skipped instead of being uploaded again. The backup time is updated for skipped files too.
- Version bumped to `0.0.155+155`.

See [README.md](README.md) for the full Chinese changelog.

## Features

- **Dashboard**: system status, storage, resource monitor, online users, scheduled tasks, recent logs, cache status, system messages and installed packages.
- **File Station**: browse, download, compress / extract, share, create file requests, rename, favorite, delete, create folders, manage shared links and search.
- **Downloads**: files downloaded from the NAS.
- **Control Panel**: shared folders, users and groups (read-only), information center, task scheduler, network, security and more.
- **Package Center**: installed / community packages, enable, disable, install and uninstall.
- **Resource Monitor**: CPU, memory, network, disk and storage performance; service and process task manager.
- **Virtual Machine Manager**: hosts, VMs and storage; start / stop VMs.
- **Docker**: containers and images; start / stop containers.
- **Download Station**: list, create and inspect download tasks.
- **Log Center**, **Photo Station**, **Storage Manager** and more.
- **Settings**: shutdown / reboot, SSH, light / dark / system theme, terminal, and album backup.

## Build from source

Requirements:

- Flutter 3.7.12 (Dart 2.19.6)
- JDK 11
- Android SDK 33 (build-tools 28–33)

```bash
./build_android.sh          # incremental release build
./build_android.sh --clean  # clean build
```

The output APK is copied to `dist/`. See [BUILD_ANDROID.md](BUILD_ANDROID.md) (Chinese) for the full toolchain setup, signing, background-service notes and troubleshooting.

## Project layout

```
lib/                  Flutter application source
  pages/              screens (dashboard, files, backup, settings, ...)
  util/               API client, HTTP/upload helpers, background service bridge
android/              Android project, foreground backup service, signing config
fplayer/              bundled video player plugin
assets/               images and icons
release/              prebuilt APK and checksums
```

## Privacy

DSM Helper manages personal cloud storage. The project is open source so you can audit the code and build it yourself. Only install builds from this repository or other sources you trust; do not install repackaged APKs from unknown sites.

## Community

- QQ group: 826559360
- QQ group: 112751763

## License

See [LICENSE](LICENSE).
