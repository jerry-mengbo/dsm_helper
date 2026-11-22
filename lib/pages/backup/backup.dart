import 'dart:convert';
import 'dart:io';

import 'package:cool_ui/cool_ui.dart';
import 'package:dio/dio.dart';
import 'package:dsm_helper/pages/common/select_ablum.dart';
import 'package:dsm_helper/util/function.dart';
import 'package:dsm_helper/widgets/file_icon.dart';
import 'package:dsm_helper/widgets/label.dart';
import 'package:dsm_helper/widgets/neu_back_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';
import 'package:neumorphic/neumorphic.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../file/select_folder.dart';
import '../../util/background_backup.dart';

class Backup extends StatefulWidget {
  // 防止离开页面后重新进入时重复启动备份任务。
  static bool running = false;

  @override
  _BackupState createState() => _BackupState();
}

class UploadItem {
  File file;
  int fileSize;
  int uploadSize;
  UploadStatus status;
  AssetType type;
  DateTime modifyTime;

  CancelToken cancelToken;
  UploadItem(this.file, this.modifyTime, this.type, {this.fileSize = 0, this.uploadSize = 0, this.status = UploadStatus.wait}) {
    cancelToken = CancelToken();
  }

  @override
  String toString() {
    return 'UploadItem{modifyTime: $modifyTime}';
  }
}

class _BackupState extends State<Backup> {
  List<AssetEntity> uploads = [];
  List<AssetPathEntity> albums = [];
  String backupFolder = "";
  DateTime lastBackupTime = DateTime.now().add(Duration(days: -5));
  UploadItem uploading;
  bool cancel = false;
  bool continueBackup = true;
  int _lastNotifyMs = 0;
  int _lastUiMs = 0;
  @override
  void initState() {
    getData();
    super.initState();
  }

  getData() async {
    String last = await Util.getStorage("last_backup_time");

    lastBackupTime = last.isNotBlank ? DateTime.fromMillisecondsSinceEpoch(int.parse(last)) : null;
    backupFolder = await Util.getStorage("backup_folder") ?? "";
    setState(() {});
    String backupAlbumStr = await Util.getStorage("backup_album");
    List backupAlbums = [];
    if (await PhotoManager.requestPermissionExtend() == PermissionState.authorized) {
      if (backupAlbumStr.isNotBlank) {
        backupAlbums = json.decode(backupAlbumStr);

        List<AssetPathEntity> list = await PhotoManager.getAssetPathList();
        list.forEach((album) {
          if (backupAlbums.contains(album.id)) {
            albums.add(album);
          }
        });
        setState(() {});
      }
    } else {
      Util.vibrate(FeedbackType.warning);
      Util.toast("请先允许${Util.appName}访问相册");
    }

    getAssetCount();
    // if (Platform.isAndroid) {
    //   String last = await Util.getStorage("last_backup_time");
    //
    //   lastBackupTime = last.isNotBlank ? DateTime.fromMillisecondsSinceEpoch(int.parse(last)) : null;
    //   backupFolder = await Util.getStorage("backup_folder") ?? "";
    //   setState(() {});
    //   Directory directory = Directory(backupSource);
    //   List<FileSystemEntity> list = directory.listSync();
    //   // print(await list.length);
    //
    //   list.forEach((element) {
    //     if (!element.path.split("/").last.startsWith(".")) {
    //       Directory(element.path).list(recursive: true).listen((event) {
    //         if (event is File) {
    //           String ext = event.path.split("/").last.split(".").last;
    //           if (!["back", "tmp"].contains(ext)) {
    //             DateTime lastModify = event.lastModifiedSync();
    //             setState(() {
    //               if (lastBackupTime != null) {
    //                 if (lastModify.isAfter(lastBackupTime)) {
    //                   uploads.add(UploadItem(event, ext == "mp4" ? UploadFileType.video : UploadFileType.picture, lastModify, fileSize: event.lengthSync()));
    //                 }
    //               } else {
    //                 uploads.add(UploadItem(event, ext == "mp4" ? UploadFileType.video : UploadFileType.picture, lastModify, fileSize: event.lengthSync()));
    //               }
    //             });
    //           }
    //         }
    //       });
    //     }
    //   });
    // } else {
    //
    // }
  }

  getAssetCount() async {
    uploads = [];
    albums.forEach((path) async {
      // path.filterOption.copyWith(orders: [OrderOption(type: OrderOptionType.createDate, asc: true)]);
      // var length = await path.assetCountAsync;
      // if (length > 0) {
      List<AssetEntity> assetList = await path.getAssetListRange(start: 0, end: 100000000);
      setState(() {
        uploads.addAll(assetList);
      });
      // }
    });
  }

  Widget _buildAlbumLabel(AssetPathEntity album) {
    return FutureBuilder<int>(
        future: album.assetCountAsync,
        builder: (context, snapshot) {
          return Label(
            "${album.name} (${snapshot.data})",
            Colors.lightBlueAccent,
            fill: true,
          );
        });
    // return Label(
    //   "${album.name} (${album.assetCountAsync})",
    //   Colors.lightBlueAccent,
    //   fill: true,
    // );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(context),
        title: Text("相册备份"),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 10, top: 8, bottom: 8),
            child: NeuButton(
              decoration: NeumorphicDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: EdgeInsets.all(10),
              bevel: 5,
              onPressed: () async {
                var hide = showWeuiLoadingToast(context: context);
                await PhotoManager.clearFileCache();
                hide();
                Util.toast("缓存清理完成");
              },
              child: Text(
                "清理缓存",
                style: TextStyle(color: Theme.of(context).textTheme.bodyText1.color),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(20),
        children: [
          if (uploading != null) ...[
            NeuCard(
              decoration: NeumorphicDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              curveType: CurveType.flat,
              child: Stack(
                children: [
                  Container(
                    width: (MediaQuery.of(context).size.width - 40) * (uploading.uploadSize / (uploading.fileSize == 0 ? 1 : uploading.fileSize)),
                    height: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.blue,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    child: Row(
                      children: [
                        uploading.type == AssetType.image
                            ? Image.file(
                                uploading.file,
                                height: 40,
                                width: 40,
                              )
                            : FileIcon(FileTypeEnum.movie),
                        SizedBox(
                          width: 20,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                uploading.file.path.split("/").last,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                                style: TextStyle(fontSize: 13),
                              ),
                              SizedBox(
                                height: 5,
                              ),
                              Text(
                                uploading.file.parent.path,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 20,
            ),
          ],
          NeuButton(
            onPressed: () {
              showCupertinoModalPopup(
                context: context,
                builder: (context) {
                  return SelectFolder(
                    multi: false,
                  );
                },
              ).then((res) {
                if (res != null && res.length == 1) {
                  setState(() {
                    backupFolder = res[0];
                    Util.setStorage("backup_folder", backupFolder);
                  });
                }
              });
            },
            decoration: NeumorphicDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "备份目的地",
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      backupFolder == "" ? "请选择目的地" : backupFolder,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 20,
          ),
          NeuButton(
            onPressed: () {
              showCupertinoModalPopup(
                context: context,
                builder: (context) {
                  return SelectAlbum(
                    multi: true,
                    selected: albums,
                  );
                },
              ).then((res) {
                print(res);
                if (res != null) {
                  setState(() {
                    albums = res;
                  });
                  List backupAlbums = albums.map((e) => e.id).toList();
                  Util.setStorage("backup_album", json.encode(backupAlbums));

                  getAssetCount();
                }
              });
            },
            decoration: NeumorphicDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: EdgeInsets.all(12),
            child: Container(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "备份源",
                    style: TextStyle(fontSize: 12),
                  ),
                  SizedBox(
                    height: 5,
                  ),
                  albums.length > 0
                      ? Wrap(
                          runSpacing: 10,
                          spacing: 10,
                          children: albums.map(_buildAlbumLabel).toList(),
                        )
                      : Text(
                          "未选择备份源",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 20,
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                continueBackup = true;
              });
            },
            child: NeuCard(
              decoration: NeumorphicDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: EdgeInsets.all(12),
              curveType: continueBackup ? CurveType.emboss : CurveType.flat,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "继续备份",
                          style: TextStyle(fontSize: 18),
                        ),
                        Text(
                          lastBackupTime != null ? lastBackupTime.format("Y-m-d H:i:s") : "从未备份过",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        Text(
                          "${uploads.where((AssetEntity upload) => (lastBackupTime == null || upload.modifiedDateTime.millisecondsSinceEpoch > lastBackupTime.millisecondsSinceEpoch) && upload.type == AssetType.image).length}张照片 ${uploads.where((upload) => (lastBackupTime == null || upload.modifiedDateTime.millisecondsSinceEpoch > lastBackupTime.millisecondsSinceEpoch) && upload.type == AssetType.video).length}个视频",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  if (continueBackup)
                    Icon(
                      CupertinoIcons.checkmark_alt,
                      color: Color(0xffff9813),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 20,
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                continueBackup = false;
              });
            },
            child: NeuCard(
              decoration: NeumorphicDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: EdgeInsets.all(12),
              curveType: continueBackup ? CurveType.flat : CurveType.emboss,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "全新备份",
                          style: TextStyle(fontSize: 18),
                        ),
                        Text(
                          "${uploads.where((upload) => upload.type == AssetType.image).length}张照片 ${uploads.where((upload) => upload.type == AssetType.video).length}个视频",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  if (!continueBackup)
                    Icon(
                      CupertinoIcons.checkmark_alt,
                      color: Color(0xffff9813),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 20,
          ),
          GestureDetector(
            onTap: () {
              Util.toast("暂不支持自动备份");
            },
            child: NeuCard(
              decoration: NeumorphicDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              curveType: CurveType.flat,
              bevel: 12,
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "自动备份",
                          style: TextStyle(fontSize: 18),
                        ),
                        Text(
                          "打开${Util.appName}后自动从上次备份位置继续备份",
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 20,
                    // child: Icon(
                    //   CupertinoIcons.checkmark_alt,
                    //   color: Color(0xffff9813),
                    // ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 20,
          ),
          uploading == null
              ? NeuButton(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  decoration: NeumorphicDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onPressed: () async {
                    if (backupFolder.isBlank) {
                      Util.vibrate(FeedbackType.warning);
                      Util.toast("请选择备份目的地");
                      return;
                    }
                    if (albums.length == 0) {
                      Util.vibrate(FeedbackType.warning);
                      Util.toast("请选择备份源");
                      return;
                    }
                    List<AssetEntity> tasks;
                    if (lastBackupTime != null && continueBackup) {
                      tasks = uploads.where((element) => element.modifiedDateTime.millisecondsSinceEpoch > lastBackupTime.millisecondsSinceEpoch).toList();
                    } else {
                      tasks = uploads;
                    }
                    //对待备份文件进行排序
                    tasks.sort((a, b) {
                      return a.modifiedDateTime.isAtSameMomentAs(b.modifiedDateTime)
                          ? 0
                          : a.modifiedDateTime.isBefore(b.modifiedDateTime)
                              ? -1
                              : 1;
                    });
                    if (tasks.length == 0) {
                      Util.toast("没有需要备份的文件");
                      return;
                    }
                    if (Backup.running) {
                      Util.toast("已有备份任务正在运行");
                      return;
                    }
                    Backup.running = true;

                    // Android: 申请通知权限并启动前台服务，保证息屏后继续上传
                    if (Platform.isAndroid) {
                      try {
                        if (await Permission.notification.isDenied) {
                          await Permission.notification.request();
                        }
                      } catch (e) {
                        debugPrint("notification permission: $e");
                      }
                      await BackgroundBackup.start(
                        title: "相册备份",
                        text: "准备备份 ${tasks.length} 个文件",
                      );
                      try {
                        if (!await BackgroundBackup.isIgnoringBatteryOptimizations()) {
                          bool go = await showCupertinoDialog<bool>(
                                context: context,
                                builder: (context) {
                                  return CupertinoAlertDialog(
                                    title: Text("后台备份"),
                                    content: Text("为保证锁屏后备份不被系统中断，建议允许${Util.appName}忽略电池优化。"),
                                    actions: [
                                      CupertinoDialogAction(
                                        onPressed: () => Navigator.of(context).pop(false),
                                        child: Text("暂不"),
                                      ),
                                      CupertinoDialogAction(
                                        onPressed: () => Navigator.of(context).pop(true),
                                        child: Text("去设置"),
                                      ),
                                    ],
                                  );
                                },
                              ) ??
                              false;
                          if (go) {
                            await BackgroundBackup.requestIgnoreBatteryOptimizations();
                          }
                        }
                      } catch (e) {
                        debugPrint("battery optimization: $e");
                      }
                    }

                    int failed = 0;
                    int skipped = 0;
                    cancel = false;
                    try {
                      for (int i = 0; i < tasks.length; i++) {
                        if (cancel) {
                          cancel = false;
                          Util.toast("备份任务已暂停");
                          break;
                        }

                        // originFile 在大文件/部分 Android 机型上可能返回 null，
                        // 此时回退到压缩文件，避免空指针导致应用崩溃。
                        File file;
                        try {
                          file = await tasks[i].originFile;
                          if (file == null) {
                            file = await tasks[i].file;
                          }
                        } catch (e) {
                          debugPrint("读取相册文件失败: $e");
                          file = null;
                        }
                        if (file == null) {
                          failed++;
                          Util.toast("无法读取文件，已跳过：${tasks[i].title ?? tasks[i].id}");
                          continue;
                        }
                        if (!file.existsSync()) {
                          failed++;
                          Util.toast("文件不存在，已跳过：${file.path.split("/").last}");
                          continue;
                        }

                        uploading = UploadItem(file, tasks[i].modifiedDateTime, tasks[i].type);
                        _lastNotifyMs = 0;
                        _lastUiMs = 0;
                        if (mounted) {
                          setState(() {
                            uploading.status = UploadStatus.running;
                          });
                        }
                        await BackgroundBackup.update(
                          title: "相册备份",
                          text: "正在上传 ${file.path.split("/").last}",
                          progress: 0,
                        );

                        var res = await Api.upload(backupFolder, uploading.file.path, uploading.cancelToken, (progress, total) {
                          int now = DateTime.now().millisecondsSinceEpoch;
                          // 10GB 级文件会产生大量进度回调，限制 UI 刷新频率，避免卡顿。
                          if (mounted && (now - _lastUiMs > 200 || progress == total)) {
                            _lastUiMs = now;
                            setState(() {
                              uploading.uploadSize = progress;
                              uploading.fileSize = total;
                            });
                          }
                          if (total > 0 && now - _lastNotifyMs > 1000) {
                            _lastNotifyMs = now;
                            int percent = (progress * 100 / total).clamp(0, 100).toInt();
                            BackgroundBackup.update(
                              title: "相册备份",
                              text: "${file.path.split("/").last} $percent%",
                              progress: percent,
                            );
                          }
                        });

                        if (res != null && res["success"] == true) {
                          if (res["skipped"] == true) {
                            skipped++;
                          }
                          if (Platform.isIOS && res["skipped"] != true) {
                            // 仅在iOS删除源文件（iOS非真实源文件）；跳过的文件不删
                            try {
                              uploading.file.deleteSync();
                            } catch (e) {}
                          }
                          Util.setStorage("last_backup_time", uploading.modifyTime.millisecondsSinceEpoch.toString());
                          if (mounted) {
                            setState(() {
                              lastBackupTime = uploading.modifyTime;
                              uploading.status = UploadStatus.complete;
                            });
                          }
                        } else {
                          failed++;
                          String msg = "上传失败";
                          if (res != null && res["error"] is Map && res["error"]["code"] != null) {
                            msg = res["error"]["code"].toString();
                          }
                          Util.toast("${file.path.split("/").last}: $msg");
                          if (mounted) {
                            setState(() {
                              uploading.status = UploadStatus.failed;
                            });
                          }
                        }

                        if (cancel) {
                          cancel = false;
                          Util.toast("备份任务已暂停");
                          break;
                        }
                      }

                      if (failed == 0) {
                        Util.toast(skipped > 0 ? "备份已完成，跳过 $skipped 个已存在文件" : "备份已完成");
                        Util.vibrate(FeedbackType.light);
                        Util.setStorage("last_backup_time", DateTime.now().millisecondsSinceEpoch.toString());
                        if (mounted) {
                          setState(() {
                            lastBackupTime = DateTime.now();
                          });
                        }
                      } else {
                        Util.toast("备份结束，${failed} 个文件失败${skipped > 0 ? "，跳过 $skipped 个已存在文件" : ""}");
                      }
                    } catch (e) {
                      debugPrint("备份异常: $e");
                      Util.toast("备份中断: $e");
                    } finally {
                      Backup.running = false;
                      if (mounted) {
                        setState(() {
                          uploading = null;
                        });
                      }
                      await BackgroundBackup.stop();
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("开始备份"),
                      SizedBox(height: 4),
                      Text(
                        "开始后可锁屏，备份在后台继续",
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),

                )
              : NeuButton(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  decoration: NeumorphicDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onPressed: () async {
                    cancel = true;
                    Util.toast("当前文件上传完成后将暂停任务");
                  },
                  child: Text("暂停备份"),
                ),
        ],
      ),
    );
  }
}
