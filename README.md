# 虚空终端 - iOS 原生客户端

类微信简约风聊天应用的原生 iOS 客户端（SwiftUI），非网页套壳。

## 功能

- 登录 / 注册
- 公共大厅聊天
- 私聊（好友间）
- 群聊（创建、管理、解散）
- 好友系统（添加、验证、删除）
- 朋友圈（发布、点赞、评论、删除）
- 图片消息发送
- 消息撤回（2分钟内）
- 头像更换
- 深色 / 浅色主题
- 字体大小调节
- 站长管理（封禁、公告、大厅改名等）
- 服务器地址可配置

## 技术栈

- SwiftUI (iOS 16+)
- URLSession (REST API)
- URLSessionWebSocketTask (WebSocket)
- 无第三方依赖

## 项目结构

```
VoidTerminal/
├── VoidTerminalApp.swift      # App 入口
├── Theme.swift                 # 主题颜色
├── Models/                     # 数据模型
├── Services/                   # 网络层
│   ├── APIService.swift        # REST API
│   └── WebSocketService.swift  # WebSocket
├── ViewModels/                 # 视图模型
└── Views/                      # 界面
    ├── Auth/                   # 登录注册
    ├── Main/                   # 主界面四个Tab
    ├── Chat/                   # 聊天视图
    ├── Moments/                # 朋友圈
    └── Components/             # 通用组件
```

## 编译方法

### 方法一：本地 Xcode 编译（需要 Mac）

1. 用 Xcode 打开 `VoidTerminal.xcodeproj`
2. 选择你的开发者团队（Signing & Capabilities）
3. 连接 iPhone，选择设备
4. 按 Cmd+R 编译运行

### 方法二：GitHub Actions 云编译（无需 Mac）

1. 将本项目推送到 GitHub 仓库
2. 在仓库 Settings → Secrets and variables → Actions 中配置（可选，用于自动签名）：
   - `IOS_CODE_SIGN_IDENTITY`
   - `IOS_PROVISIONING_PROFILE`
3. 推送代码到 main 分支，或手动触发 Actions
4. 等待构建完成，在 Actions 页面下载 `VoidTerminal.ipa`
5. 用 Sideloadly 或 AltStore 签名安装到手机

### 方法三：命令行编译

```bash
# 未签名编译
xcodebuild -project VoidTerminal.xcodeproj \
  -scheme VoidTerminal \
  -configuration Release \
  -sdk iphoneos \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

# 打包 IPA
mkdir -p Payload
cp -r build/Build/Products/Release-iphoneos/VoidTerminal.app Payload/
zip -r VoidTerminal.ipa Payload
```

## 服务器配置

默认服务器地址：`http://buer.kdns.fr`

在登录页点击「服务器设置」可修改服务器地址。
WebSocket 地址会自动从 HTTP 地址推导（http→ws, https→wss）。

## 服务器端

本客户端连接的是 Node.js + Express + ws 搭建的聊天服务器，API 协议：

- REST: `/api/register`, `/api/login`, `/api/me`, `/api/avatar`, `/api/upload-msg-image`, `/api/moment-post`, `/api/change-password`, `/api/change-username`
- WebSocket: `/ws`，JSON 消息格式，type 字段区分消息类型

## 要求

- iOS 16.0+
- Xcode 15.0+

 版本历史

v3.1 - 2026-08-27

大厅输入@不再弹出列表，改为长按头像@
修复已知问题
v3.0.2 - 2026-08-27

修复已知问题
v3.0.1 - 2026-08-26

修复已知问题
v3.0 - 2026-08-26

新增图片缓存，图片只下载一次
头像、消息图片、朋友圈图片、图片预览均支持缓存
全局网络缓存优化
聊天记录增量合并，重连后减少重复请求
朋友圈按时间倒序排列
v2.2 - 2026-08-26

修复头像加载不稳定
修复头像 URL 双斜杠 404
修复消息重复发送
修复群成员列表显示不全
修复群解散和发朋友圈实时更新
v2.1 - 2026-08-26

聊天消息显示发送者用户名
新增站长、群主角色标签
新增更新日志界面和版本号显示
v2.0 - 2026-08-25

全面安全加固，HTTPS + SSL Pinning
Token 和聊天记录加密存储
注册密码强度要求
支持 GitHub Actions 云编译
v1.0

首个公开版本，类微信简约风 SwiftUI 原生客户端
支持大厅、私聊、群聊、好友、朋友圈、图片消息、消息撤回、头像更换、主题切换、站长管理等全部基础功能
无第三方依赖，纯原生实现
