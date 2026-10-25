# Codex Usage Bar

[English](README.md) · [更新说明](CHANGELOG.zh-CN.md) · [安全审查](SECURITY_REVIEW.zh-CN.md) · [隐私说明](PRIVACY_REVIEW.zh-CN.md)

<img src="assets/icon.png" alt="Codex Usage Bar 图标" width="96">

**1.3.0（构建号 7）** 是一款非官方 macOS 订阅额度工具，根据当前前台桌面应用显示对应服务的剩余额度和重置时间。

- Codex／Work（`com.openai.codex`）在前台：显示 Codex。
- Claude 桌面版（`com.anthropic.claudefordesktop`）在前台：显示 Claude。
- 其他应用在前台：隐藏。不识别浏览器标签页，也不区分同一应用内部的不同窗口。
- `5hrs` 表示五小时额度，`W` 表示每周额度。绿色百分比表示**剩余**额度，不是已用额度；菜单和状态提示目前使用中文。
- 两家的缓存、错误和请求状态分开保存，后台迟到的请求不会覆盖另一家的显示。

刘海屏自动放在刘海左侧，保留 8 点间距；无刘海屏保持主屏幕顶部居中。切换显示器、桌面空间、全屏、唤醒及应用激活时会重新定位和恢复；文字过长时截断。

## 下载与升级

从 [Release v1.3.0](https://github.com/ittiav/CodexUsageBar/releases/tag/v1.3.0) 下载通用安装包、源码包及校验文件。通用包包含 Apple Silicon 和 Intel 两种架构，需要 **macOS 13 或更高版本**。

1. 先退出旧的 `CodexUsageBar` 进程。看不到菜单时，可以在“活动监视器”中退出该进程。
2. 解压后替换 `/Applications/CodexUsageBar.app`。
3. 重新打开这个副本，再切回 Codex／Work 或 Claude 桌面版。此工具没有 Dock 图标或常规主窗口；其他应用在前台时启动，看起来可能没有反应。

替换文件不会自动重启旧进程。Finder 文件夹日期可能保留旧时间，请通过“显示简介”或以下命令核实版本：

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/CodexUsageBar.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/CodexUsageBar.app/Contents/Info.plist
```

本版应输出 `1.3.0` 和 `7`。应用采用 **ad hoc 本地签名，未经过 Apple 公证**。将两个 ZIP 和 `SHA256SUMS.txt` 放在同一文件夹后，可验证：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

## Codex 配置

需要已登录的本机 Codex CLI，路径为 `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`。工具通过本机标准输入／输出调用 `account/rateLimits/read`；该接口可能随 Codex 更新变化。凭据由已安装的 CLI 管理，不打包进本工具。

## 连接 Claude Pro／Max

1. 点击任一服务的用量条，选择 **“连接 Claude…”**。
2. 在连接窗口内的 `https://claude.ai/settings/usage` 登录与 Claude 桌面版相同的账号。不会导入桌面版现有登录，也不需要 Claude Code CLI。
3. 点击窗口顶部原生按钮 **“读取额度”**。存在多个工作区时，选择桌面版中使用的那一个。
4. 看到连接成功提示后，关闭连接窗口，再切回 Claude 桌面版。

读取可用的五小时额度及“所有模型”每周额度。缺少的额度窗口显示“暂无数据”，不会伪造零用量或满额。本版不显示 API 账单、第三方余额或各模型独立周限额。无法自动识别桌面版账号变化；更换账号后，请先断开，再连接相同账号。

**“断开 Claude 连接”** 会清除本工具的 WebKit 登录状态、工作区选择及 Claude 额度缓存，不会退出 Claude 桌面版或其他浏览器。详见[隐私说明](PRIVACY_REVIEW.zh-CN.md)。

### 兼容性限制

Claude 读取依赖网站内部的 `/api/organizations` 与 `/api/organizations/{id}/usage` **非公开、未版本化接口**，并非受支持的公开订阅额度 API，网站更新可能导致失效。登录验证需要本人完成，不会绕过验证。部分登录提供方可能拒绝内嵌浏览器；本版不会绕过该限制。未知的主页面登录重定向会被阻止，而非自动信任。

## 刷新与排查

- 正常约每分钟刷新一次；首次使用 Claude 后，其读取会在后台继续。切换应用不会导致密集请求。
- Claude 返回 HTTP 429 后，至少暂停五分钟；服务要求更久时继续等待，手动刷新也遵守该等待时间。
- `~` 表示本次运行尚未验证、已经变旧或请求失败后使用的缓存。已到重置时间的旧额度显示“待更新”；超过一天的快照不再使用。
- 完全不显示时，确认对应的**桌面客户端**在前台，以及升级后已退出并重新打开旧进程。
- Codex 不可读时检查 CLI 路径和登录；Claude 不可读时重新打开连接窗口，核对账号／工作区，再点“读取额度”。不会把网站原始错误正文显示在用量条上。

## 源码构建与检查

使用 Xcode 16 或兼容的新版本：

```sh
xcodebuild -project CodexUsageBar.xcodeproj -scheme CodexUsageBar -configuration Release -derivedDataPath build 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
codesign --force --deep --sign - build/Build/Products/Release/CodexUsageBar.app
```

只构建当前机器架构时，去掉 `ARCHS` 和 `ONLY_ACTIVE_ARCH`。产物在 `build/Build/Products/Release/`。

```sh
mkdir -p work
swiftc UsageModels.swift Tests/main.swift -o work/usage-model-tests
work/usage-model-tests
node Tests/claude-request.test.js
```

检查覆盖额度解析、缓存分离、导航边界、来源和重定向、工作区选择、数据最小化及错误处理。模拟请求不会使用账号或连接网络；本机还验证了真实 Claude 额度读取及两家显示切换。尚未完整测试 Intel 实机、所有账号／登录方式及全部显示和唤醒场景。

## 登录时启动

将 `LaunchAgents/local.codex.usagebar.login.plist` 复制到 `~/Library/LaunchAgents/`，然后退出并重新登录 macOS。配置指向 `/Applications/CodexUsageBar.app`；菜单中的“退出”结束本次运行。

## 隐私与许可

代码未实现遥测或自建数据收集服务器。Claude 登录由本工具自己的 WebKit 会话保存，不在应用包中。Release 排除登录状态、额度缓存、Git 历史、日志及调试符号。请阅读有范围限制的[安全审查](SECURITY_REVIEW.zh-CN.md)及[隐私说明](PRIVACY_REVIEW.zh-CN.md)，它们不构成独立安全认证。

本项目与 OpenAI、Anthropic 均无隶属关系。采用 [MIT 许可](LICENSE)。
