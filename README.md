# 电动车防盗报警器

基于 STM32F103C8T6 的电动车防盗报警器原型，含本地运动检测、声光报警与 Android App。

| 位置 | 内容 |
| --- | --- |
| `firmware/` | STM32 固件 v1.0.2、STM32CubeIDE 工程与链接脚本 |
| `app/` | Android App v1.0.1 的 Flutter 源码、资源和测试 |
| [Releases](../../releases) | Android APK |

## 固件

在 STM32CubeIDE 导入 `firmware/`，编译后用 ST‑LINK 通过 SWD 烧录。联网前在 `firmware/Core/Inc/config.h` 填写自己的 Wi‑Fi 和 MQTT 配置并重新编译。

## Android App

可从 Releases 获取 APK。也可在 `app/` 内执行 `flutter pub get`、`flutter test`、`flutter build apk --debug`。参考版本为 Flutter 3.35.4。绑定页面使用自己的 MQTT 账户，确认位置、状态和命令主题与固件一致。

本地运动报警由板端触发。电子围栏由 App 根据定位数据判定。原型使用明文 MQTT，联网需使用独立测试账号。
