# 蓝果短剧

蓝果短剧是一款用 Flutter 开发的个人短剧客户端，支持在 Android 和 iOS 上运行。应用本身不制作、不托管视频，而是通过可切换的第三方数据源浏览、搜索和播放短剧，并提供播放记录、收藏和离线缓存等常用功能。

本仓库对应的 Dart 包名为 `haokan_shipin`。

## 主要功能

- 多数据源切换：可从远程源列表更新，也支持添加自定义接口；启动或手动刷新时会检测源是否可用
- 首页分类浏览、下拉刷新与搜索
- 视频播放：支持倍速，并自动保存播放进度
- 继续观看与播放记录
- 收藏影片
- 离线缓存当前集数，支持离线播放；缓存过程中会显示进度、网速和影片大小
- 已下载管理与设备存储空间示意
- 设置与关于页

## 数据源

应用会读取 `assets/sources.json` 中的源列表。采集站 JSON 源（`type: 1`）共用一套接口；少数需要单独适配的自定义源走本地逻辑。暂不支持配置里其他需要独立 JS 爬虫的源。

可在「我的」页进入「数据源」，切换已有源或添加自定义采集站地址。接口一般形如 `https://example.com/api.php/provide/vod/` 或 `https://example.com/api/json.php`。当前选中的源会被记住，下次打开仍然有效。

这些都是第三方站点的非官方接口，地址和规则可能会变，只建议作为个人学习使用。

## 环境与运行

- 本机需要已安装 Flutter。本项目近期在 Flutter 3.41.9、Dart 3.11 下开发
- iOS 部署目标 15.0，Android 最低 API 24

在项目根目录执行：

```bash
chmod +x tool/bootstrap.sh
./tool/bootstrap.sh
flutter run
```

`bootstrap.sh` 会生成 Android / iOS 工程、补上网络权限（含部分源需要的明文 HTTP），并执行 `flutter pub get`。

如果只想手动处理，也可以执行：

```bash
flutter create . --project-name haokan_shipin --org com.haokan --platforms=android,ios
flutter pub get
flutter run
```

手动创建后，请把 `android/app/src/main/AndroidManifest.xml` 的 `<application>` 加上 `android:usesCleartextTraffic="true"`，并在 iOS 的 `Info.plist` 中允许访问 HTTP。脚本会自动做这两步。

若使用 [FVM](https://fvm.app/) 管理 Flutter 版本，将上面的 `flutter` 换成 `fvm flutter` 即可。

打包示例：

```bash
# Android arm64 真机包
fvm flutter build apk --release --target-platform android-arm64

# iOS 需配置好开发者证书与描述文件后再导出 IPA
fvm flutter build ipa --release --export-options-plist=ios/ExportOptions-development.plist
```

## 免责声明

1. 本项目仅供学习、研究与技术交流使用，不提供任何商业服务。
2. 应用中展示或播放的视频、封面、标题、简介等内容全部来自第三方数据源，本项目作者不拥有这些内容的版权，也未获得相关授权，不对内容的合法性、真实性、准确性或可用性作任何保证。
3. 本仓库只包含客户端源代码，不存储、不提供、不传播任何视频文件。
4. 请勿将本项目或通过本项目获取的内容用于商业目的、公开传播或其他违法违规用途。使用时请遵守所在地法律法规及第三方平台条款。
5. 如权利人认为相关内容侵犯其合法权益，请通过本仓库 Issue 联系，将配合处理。
6. 因使用本项目而产生的任何风险、损失或法律责任，均由使用者自行承担，项目作者不承担任何责任。
