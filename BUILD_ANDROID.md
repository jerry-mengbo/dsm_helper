# 群晖助手（dsm_helper）Android 构建说明

本文档对应当前源码（versionName `0.0.155` / versionCode `155`），包含构建环境、后台备份、大文件上传的实现说明。

## 一、构建产物

| 项目 | 值 |
| --- | --- |
| 文件 | `dist/dsm_helper-0.0.155-release.apk` |
| 大小 | 约 30 MB（29.8 MiB） |
| 包名 | `fit.flutter.dsm_helper` |
| 版本 | versionName `0.0.155` / versionCode `155` |
| 架构 | `arm64-v8a`（仅 64 位 ARM，`android/app/build.gradle` 中限定） |
| 最低系统 | Android 5.0（API 21），targetSdk 33 |
| 签名 | 本机生成的 release key（见第四节） |
| SHA-256 | `8a0421868ece890cd4ec7eeeacf2ec83b13202f67ff45c27f7b1a0d8ffe4b63f` |

> **签名冲突提醒**：官方包签名是 `CN=flutter.fit`，本包是 `CN=DSM Helper`，不能覆盖安装。
> 安装前先卸载手机上的旧版，否则会提示 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。卸载会清空 App 本地数据。

安装：

```bash
adb install -r dist/dsm_helper-0.0.155-release.apk
```

## 二、0.0.155 本次更新

### 1. 相册备份支持息屏/后台继续

- 新增 Android 前台服务 `BackupService`（`android/app/src/main/kotlin/fit/flutter/dsm_helper/BackupService.kt`）。
- 点击“开始备份”后启动前台服务，持有 `PARTIAL_WAKE_LOCK` 和 Wi-Fi 高性能锁，并显示常驻进度通知。
- 锁屏、按 Home 键、切换 App 后上传继续；备份完成、暂停或异常时自动停止服务并释放锁。
- 首次开始备份会：
  - 申请 Android 13+ 通知权限（不授权也能备份，但看不到进度通知）；
  - 提示把 App 加入“忽略电池优化”白名单（Android 12+ 后台限制较严，建议允许）。
- 通知栏会显示当前文件名和百分比，点击通知回到 App。

实现链路：`lib/pages/backup/backup.dart` → `lib/util/background_backup.dart` → `MainActivity` 的
`fit.flutter.dsm_helper/background_backup` MethodChannel → `BackupService`。

> 注意：从最近任务里**上滑杀掉 App** 会停止服务（`android:stopWithTask="true"`）。锁屏、按 Home、
> 切换应用不受影响。部分国产系统的省电策略仍可能杀后台，需要把 App 设为“允许后台运行/自启动”。

### 2. 大文件上传不再崩溃

针对 4GB 边界做了多处修复：

- 上传改为**流式读取**：`MultipartFile.fromFile` 从磁盘分块读取，不会把 4GB/10GB 文件读进内存。
- 服务器返回**非 JSON 错误页、空响应、HTTP 413/5xx** 时，统一转换成失败结果并提示，不再因
  `json.decode` 抛异常导致闪退。
- 对 ≥2GB 的文件不再发送 `size` / `mtime` 表单字段。部分 DSM 版本会把这两个可选字段按 32 位整数
  解析，4GB 附近会溢出；改由 HTTP `Content-Length` 让服务器判断大小。
- 相册备份读取原图时增加空值兜底：`originFile` 在大文件/部分 Android 机型上会返回 `null`，
  现在会回退到 `asset.file`，仍失败则跳过并提示，不会空指针崩溃。
- 10GB 文件的进度回调做了节流（UI 200ms、通知 1s），避免大量 `setState` 卡顿。

### 3. 已存在文件自动跳过

- 每个文件上传前先用 `SYNO.FileStation.List` 的 `getinfo` 查询目标目录下是否已有同名文件；
- 已存在就不再发送文件内容，直接返回 `skipped`，备份/上传结束后提示“跳过 N 个已存在文件”；
- 相册备份中被跳过的文件也会更新 `last_backup_time`，下次“继续备份”不会反复重传；
- 只按文件名判断，不比较大小/内容；如果 NAS 上的文件损坏或想覆盖，先删除远端同名文件再上传。

> 每个文件只多一次很小的元数据请求，不会重新传输文件内容；对 4GB/10GB 大文件收益最明显。

### 4. 版本号

`pubspec.yaml`：`version: 0.0.155+155`。

## 三、一键构建

```bash
cd /Users/mima4ge1/Desktop/code/dsm_helper/dsm_helper
./build_android.sh          # 增量构建
./build_android.sh --clean  # 清理后完整构建（改依赖/资源后用）
```

脚本会设置 `JAVA_HOME`、`ANDROID_HOME`、`PATH`，执行 `flutter pub get` 和
`flutter build apk --release`，最后把 APK 复制到 `dist/` 并打印 SHA-256。

手动构建：

```bash
export JAVA_HOME=/Users/mima4ge1/Desktop/code/toolchain/jdk11/Contents/Home
export ANDROID_HOME=/Users/mima4ge1/Desktop/code/toolchain/android-sdk
export PATH=/Users/mima4ge1/Desktop/code/toolchain/flutter/bin:$JAVA_HOME/bin:$PATH
export GRADLE_OPTS="-Djava.net.useSystemProxies=false"
cd /Users/mima4ge1/Desktop/code/dsm_helper/dsm_helper
flutter pub get
flutter build apk --release
```

## 四、本机工具链与签名

工具链在 `/Users/mima4ge1/Desktop/code/toolchain/`，不污染系统目录：

| 组件 | 版本 / 路径 |
| --- | --- |
| Flutter | 3.7.12 stable（arm64），`toolchain/flutter` |
| Dart | 2.19.6（随 Flutter） |
| JDK | Temurin 11.0.33+10，`toolchain/jdk11/Contents/Home` |
| Android SDK | platform 33；build-tools 28.0.3 / 29.0.2 / 30.0.3 / 31.0.0 / 32.0.0 / 33.0.2 |
| Gradle | 7.3（wrapper），AGP 4.1.0，Kotlin 1.8.0 |
| Rosetta 2 | 已安装（Flutter 3.7 的 Android AOT 工具是 x86_64） |

本机全局配置（删掉会导致重新构建变慢或失败）：

- `~/.gradle/gradle.properties`：关闭系统代理、缩短超时、把 aapt2 指向 build-tools 33 的通用二进制。
- `~/.gradle/init.gradle`：仅对 `dsm_helper` 生效，优先使用阿里云 Maven 镜像。

签名配置 `android/key.properties`：

```properties
storePassword=<你的签名密码>
keyPassword=<你的签名密码>
keyAlias=dsm_helper
storeFile=../keystore/release.jks
```

> 这是本地测试签名。要发布请换成自己的 keystore 并备份；换签名后无法覆盖安装旧版本。

## 五、为成功构建做的工程改动

业务代码之外，以下配置是仓库里缺失或需要适配本机的：

| 文件 | 改动 | 原因 |
| --- | --- | --- |
| `pubspec.yaml` | `wave: ^0.2.2` → `wave: 0.2.2` | wave 0.2.5 把 `lib/config.dart` 移到了 `lib/src/config.dart`，旧代码编译失败 |
| `android/key.properties` / `android/keystore/release.jks` | 新建 | 仓库未提供 release keystore |
| `android/local.properties` | 新建 | 指向本机 Flutter / Android SDK |
| `android/gradlew`、`android/gradle/wrapper/gradle-wrapper.jar` | 新建 | 仓库中被 gitignore，wrapper 不完整 |
| `android/gradle/wrapper/gradle-wrapper.properties` | distributionUrl 改为腾讯镜像 | 官方 Gradle 下载慢 |
| `pubspec.lock` | 生成 | 锁定依赖版本（被 gitignore，仅本地有效） |

0.0.155 新增/修改的源码：

| 文件 | 作用 |
| --- | --- |
| `android/app/src/main/kotlin/fit/flutter/dsm_helper/BackupService.kt` | 前台服务、通知、WakeLock/WiFiLock |
| `android/app/src/main/kotlin/fit/flutter/file_station/MainActivity.kt` | MethodChannel、启动/停止服务、电池优化设置 |
| `android/app/src/main/AndroidManifest.xml` | 前台服务及权限声明 |
| `lib/util/background_backup.dart` | Dart 侧服务桥接 |
| `lib/pages/backup/backup.dart` | 备份循环、后台服务、空值兜底、进度节流 |
| `lib/util/function.dart` | 流式上传、错误兜底、413 提示 |
| `lib/util/api.dart` | 异步 MultipartFile、大文件省略 size/mtime、上传前查重 |
| `lib/pages/file/upload.dart` | 文件上传失败不再中断整个队列 |

## 六、大文件上传与 4GB 崩溃的原因

4GB 是一个常见的“边界值”，可能来自三处：

1. **App 侧异常未捕获**：服务器对超大请求返回 HTML 错误页/空响应，旧代码直接
   `json.decode(response.data)`，抛 `FormatException` 导致界面崩溃。已改为安全解析并提示。
2. **相册文件读取失败**：`AssetEntity.originFile` 返回 `null`，旧代码直接 `.path` 空指针。已加兜底。
3. **NAS 侧请求体限制**：DSM 的 nginx/反向代理、或 `size`/`mtime` 的 32 位解析，会在 4GB 处
   拒绝请求（HTTP 413 或连接被重置）。App 已对 ≥2GB 文件省略这两个字段，并流式发送 10GB+
   文件；但如果 NAS 本身限制单请求大小，仍需要在 NAS 上放开。

如果升级后大文件仍失败，先看 App 提示：

- **HTTP 413 / “文件超过 NAS 的上传大小限制”**：改 NAS 的 nginx 配置，例如在
  `http` 或 `server` 段加 `client_max_body_size 0;`（0 表示不限制），然后重载 nginx；
  如果前面还有反向代理/域名转发，也要同步调大。
- **连接被重置/超时**：检查 Wi-Fi 是否稳定、NAS 是否开了反向代理超时限制；10GB 上传耗时较长，
  建议保持前台服务并允许忽略电池优化。
- **目标文件夹是 FAT32 外接盘**：FAT32 单文件上限就是 4GB，换 Btrfs/ext4 存储空间。

> 说明：单请求上传是 DSM `SYNO.FileStation.Upload` API 的限制，它没有官方的分片/断点续传接口；
> 因此 App 能保证的是“10GB 不崩溃、错误可读、有后台服务保活”，NAS 端的请求体上限仍需服务器配置配合。

## 七、改源码后重新打包

| 想改什么 | 改哪里 |
| --- | --- |
| 应用名称 | `android/app/src/main/AndroidManifest.xml` 的 `android:label`（iOS 对应 `ios/Runner/Info.plist`） |
| 版本号 | `pubspec.yaml` 的 `version: 0.0.155+155`（`+` 前 versionName，后 versionCode） |
| 应用图标 | `android/app/src/main/res/mipmap-*/ic_launcher.png` |
| 界面 / 功能 | `lib/pages/` 对应页面 |
| 接口请求 | `lib/util/api.dart` |
| 中文文案 | `lib/util/strings.dart` |
| 主题配色 | `lib/themes/` |
| 启动逻辑、广告、微信 SDK | `lib/main.dart` |
| 包名 | `android/app/build.gradle` 的 `applicationId` + `AndroidManifest.xml` 的 `package` + `MainActivity` 包名/目录 |

改完执行 `./build_android.sh`；改依赖后执行 `./build_android.sh --clean`。

### 去掉开屏广告 / 微信 SDK（可选）

`lib/main.dart` 的 `pangle.init(...)`、`pangle.loadSplashAd(...)` 是穿山甲广告；`registerWxApi(...)`、
`fluwx` 是微信登录/分享。不需要可删代码并从 `pubspec.yaml` 去掉 `pangle_flutter` / `fluwx`，然后
`./build_android.sh --clean`。

## 八、常见问题

1. **`AAPT2 ... Daemon startup failed`**
   AGP 4.1 自带 aapt2 是 x86_64。已通过全局 `android.aapt2FromMavenOverride` 指向 build-tools 33
   的通用 aapt2；也可 `softwareupdate --install-rosetta --agree-to-license`。

2. **`Flutter requires the Rosetta translation environment`**
   Flutter 3.7 的 Android `gen_snapshot` 是 x86_64，必须装 Rosetta（本机已装）。

3. **Gradle 一直停在 `Running Gradle task 'assembleRelease'...`**
   检查 `~/.gradle/gradle.properties`、`~/.gradle/init.gradle` 是否还在；本机代理会让
   `dl.google.com` 卡死，配置已改为直连 + 阿里云镜像。

4. **`Failed to find Build Tools revision 29.0.2`**
   老插件固定了 build-tools 版本，本机已装齐 28~33。缺失时：
   ```bash
   $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "build-tools;29.0.2"
   ```

5. **`INSTALL_FAILED_UPDATE_INCOMPATIBLE`**
   先卸载官方版（丢本地数据），或换成官方签名。

6. **`wave` 的 `config.dart` 找不到**
   不要把 `wave` 升级回 `^0.2.2`，保持 `wave: 0.2.2`。

7. **构建日志里的 lint `ClassNotFoundException: ...Vendor`**
   AGP 4.1 与新 AndroidX 的 lint 检查不兼容，属于告警，不影响 APK。

8. **提示 `Building without sound null safety`**
   项目是 Dart 2.x 非空安全代码，正常；不要升到 Dart 3 / Flutter 3.10+。

9. **后台备份仍被系统杀掉**
   在系统设置里给“群晖助手”开启：允许后台活动、自启动、关闭省电限制；Android 13+ 允许通知；
   不要把 App 从最近任务上滑删除。

## 九、目录说明

```
dsm_helper/
├── lib/
│   ├── pages/backup/backup.dart      # 相册备份
│   ├── util/background_backup.dart   # 前台服务桥接
│   ├── util/function.dart            # 上传/请求封装
│   └── util/api.dart                 # DSM API
├── android/
│   ├── app/src/main/kotlin/fit/flutter/dsm_helper/BackupService.kt
│   ├── keystore/release.jks          # 本机签名
│   └── key.properties                # 签名配置（勿公开）
├── dist/                             # 构建产物
└── build_android.sh                  # 一键构建
```

官方原包仍保留在 `../app-release.apk`，可用于对比或提取原签名信息。
