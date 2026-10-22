# Neko VRC

一个 VRChat 的非官方第三方 Android 客户端，用 Flutter 编写。

手机上就能查看好友在线情况、谁在哪个房间、好友动态，也能改自己的状态、收发通知、管理收藏与图库。
所有数据只存在本机，不经过任何自建服务器。

> 本项目与 VRChat Inc. 没有任何关联，不是官方产品。

## 功能

- **登录**：账号密码 + 两步验证（TOTP / 邮箱 / 恢复码），支持记住密码与冷启动恢复会话
- **好友**：在线/离线分组、按所在实例分组、搜索、好友收藏夹过滤、在线时长、在线状态灯
- **动态**：记录好友上线下线、位置变化、状态与签名变化、与你相遇；支持 全部 / 上下线 / 位置 / 资料 / 相遇 分类筛选
  - 数据来源为 Pipeline 实时事件 + 前台 60 秒一次的 REST 快照对比，弱网或实时通道掉线也能补上变化
  - Web 端的上下线不提醒，只在进入/退出游戏时记录
- **位置**：显示「地图名 · 房间类型 · #实例号」，私人房间统一显示为「位于私人房间」；点击可直接进入该实例页并邀请自己
- **资料**：头像、状态签名、徽章、语言、当前模型、代表群组、创建的世界与收藏夹
- **通知**：好友申请、邀请、请求加入、boop 等，可在 App 内直接回复或邀请自己
- **图库**：浏览、上传、保存到手机、删除，支持五种分类
- **其他**：世界搜索与详情、当前实例成员、新建房间、个人状态编辑、模型切换

## 技术栈

| 项 | 说明 |
| --- | --- |
| 框架 | Flutter 3.47（Dart 3.13） |
| 状态管理 | Riverpod |
| VRChat API | `vrchat_dart` 5.0（官方 Web API，无自建后端） |
| 图片 | `cached_network_image` + `native_animated_image`（支持 APNG 头像框/名字牌） |
| 本地存储 | `path_provider` + 本地 JSON（动态、Cookie、登录信息） |

## 构建

```bash
flutter pub get

# 单架构（体积最小，真机用这个）
flutter build apk --release --target-platform android-arm64

# 需要覆盖多种设备时
flutter build apk --release --split-per-abi
```

签名配置放在 `android/key.properties`（**不提交到仓库**）：

```properties
storePassword=***
keyPassword=***
keyAlias=neko
storeFile=neko-release.jks
```

没有该文件时 Flutter 会用 debug 签名构建，功能不受影响。

## 使用说明

- 首次登录需要能访问 `api.vrchat.cloud`。国内网络通常需要代理；如果登录时提示「连接被拒绝」，多半是代理节点或规则的问题，换节点或重开代理再试
- 「相遇」需要你的账号同时在 PC 端 VRChat 里在线，App 才能知道你所处的实例
- 动态只记录安装之后发生的变化，VRChat 接口本身不提供历史记录

## 开发说明

本项目的大部分代码与文档由 AI 辅助完成，主要使用了 **DeepSeek-V4.1-Flash** 与 **GLM-5.3-Flash**；
功能设计、测试与发布由项目作者负责。

## 免责声明

本项目仅供学习与个人使用，使用 VRChat 官方公开 API，未修改客户端、未绕过任何验证。
请遵守 [VRChat 服务条款](https://vrchat.com/legal) 与第三方应用规范；因使用本工具导致的账号风险由使用者自行承担。

应用会在 User-Agent 中声明自身名称与联系方式，联系方式见 `lib/src/core/app_info.dart`。

## 许可证

[MIT](LICENSE) © 2026 NekoChiffon

## 版本

当前 `0.38.9+117`。

`promo/` 目录下是内测用的宣传页 HTML，可直接用浏览器打开。
