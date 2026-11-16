# 爱看影视

可切换数据源的个人 Flutter 影视 App。首页、分类、搜索和播放都走当前选中的源，也可以手动添加采集站接口。

它会读取 `assets/sources.json` 里的源列表。采集站 JSON 源（`type: 1`）共用一套接口；「黄果短剧」这种自定义爬虫源单独适配。暂不支持配置里其他需要独立 JS 爬虫的源。

## 运行

本机需要已安装 Flutter。在项目根目录执行：

```bash
chmod +x tool/bootstrap.sh
./tool/bootstrap.sh
flutter run
```

`bootstrap.sh` 会生成 Android / iOS 工程、补上网络权限（含部分源需要的明文 HTTP），并执行 `flutter pub get`。

如果只想手动处理，也可以执行：

```bash
flutter create . --project-name aikan_yingshi --org com.aikan --platforms=android,ios
flutter pub get
flutter run
```

手动创建后，请把 `android/app/src/main/AndroidManifest.xml` 的 `<application>` 加上 `android:usesCleartextTraffic="true"`，并在 iOS 的 `Info.plist` 中允许访问 HTTP。脚本会自动做这两步。

## 使用

- 底部「源」页可以切换已有源，也可以添加自定义采集站地址。
- 采集站接口一般形如 `https://example.com/api.php/provide/vod/` 或 `https://example.com/api/json.php`。
- 当前选中的源会记住，下次打开还在。

这些都是第三方站点的非官方接口，地址和签名规则可能会变，只建议作为个人使用。
