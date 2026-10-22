# 发布说明

## v0.2.1

本次迭代包含原生 AirPlay 跟随、紧凑玻璃界面和动漫风 Mac＋HomePod 图标。

- TV App／系统先原生连接 HomePod，再开启“原生 AirPlay 跟随”，为本地扬声器增加可调延迟；保留 HomePod 的原生播放连接和音画补偿。停止只停止本地副本。
- 两种模式分别保存延迟；共同播放模式继续提供整个 Mac 的声音转发和独立音量。
- 520×470紧凑窗口、可滚动设备卡片、分段模式选择。在macOS26上使用原生 Liquid Glass；旧系统源码构建回退到材质背景。
- 图标采用动漫／柔和3D造型，放大设备组合，减少外围留白。

### 安装与升级

预编译应用需要 Apple Silicon、macOS26+。退出旧版后，将解压出的 `MacHomePod.app` 复制到“应用程序”并打开；现有音量和延迟设置使用同一bundle ID保留。

当前仍为 **ad-hoc 签名、未经 Apple 公证的实验版本**。本机曾遇到下载压缩包被“无法验证开发者”拦截，从源码本机重新编译后安装并打开成功。遇到拦截时可按README从源码构建；只用原生跟随不需要构建后端。不要关闭系统安全保护。本次更新不宣称解决所有下载环境的Gatekeeper拦截。

### 资产

- `MacHomePod-0.2.1-arm64.zip`：完整应用、独立OwnTone后端与许可证。
- `MacHomePod-0.2.1-source.zip`：对应Swift源码、构建脚本、兼容性补丁、15份固定第三方源码及配方和许可证。
- `SHA256SUMS-0.2.1.txt`：应用包与源码包的SHA-256校验值。

### 验证与限制

原生跟随在本机TV内容中经过用户听音确认：2000ms时Mac、HomePod与画面基本同步；停止后HomePod与画面正常继续。这个数值是本机手动校准结果，没有声学量化同步保证。受保护内容和App内直传AirPlay可能无法捕获。

完整音频、FIFO、API、捕获配置和生命周期回归通过；实际检查默认和最小窗口、四设备滚动列表与模式设置恢复。界面迭代未改变音频路径，未重新做长时间听音验证。详细证据和边界见 `VALIDATION.md`。

## v0.1.0

首个实验版：捕获整个 Mac 的普通系统音频，在本地扬声器与 HomePod 共同播放；提供独立音量、手动延迟、中文界面与按应用生命周期管理的独立 OwnTone 后端。

本机构建适用于 Apple Silicon、macOS26+。这是 ad-hoc 签名版本，尚未获得 Developer ID 签名或 Apple 公证；下载后 Gatekeeper 可能拦截。源码构建是可选安装路径。不要关闭 Gatekeeper 或其他系统安全保护。

### 资产

- `MacHomePod-0.1.0-arm64.zip`：完整应用，含后端及依赖许可证。
- `MacHomePod-0.1.0-source.zip`：Swift 源码、构建脚本、兼容性补丁，以及后端/运行库对应源码和配方。
- `SHA256SUMS.txt`：上述文件的 SHA-256 校验值。

### 验证

在 Apple Silicon MacBook Air、macOS26.6 与 HomePod AudioAccessory6,1、audioOS26.6 上验证：本地播放器及浏览器普通 MP4 均双端有声；手动校准1250ms后主观基本同步；同一会话超过10分钟未掉线，结束听音未见明显变化；停止恢复、后端退出重启和应用退出清理通过。详情见 `VALIDATION.md`。

没有声学量化同步保证；受保护媒体、真实断网、拒绝权限和睡眠唤醒的边界恢复仍需更多测试。视频画面不会自动补偿音频延迟。

## 维护者打包

构建并实机验证后运行 `python3 scripts/package-release.py`。脚本从应用Info.plist读取版本，可用 `MAC_HOMEPOD_APP_PATH` 指定应用路径，按版本输出应用、源码包和校验值。源码包需准备并校验15份固定第三方源码，默认暂存于 `dist/source-staging/MacHomePod-source/vendor-sources/`。发布构建对应源码应与二进制同时上传，不能仅依赖 GitHub 自动生成的 Swift 源码归档。

正式公证发行需要自己的 Apple Developer ID、嵌套代码签名、Hardened Runtime、公证与 stapling；当前构建不宣称已完成这些步骤。
