# Mac HomePod 同播

将 Mac 的普通系统音频同时发送到 Mac 扬声器和同一局域网中的 HomePod，并手动调节相对延迟。

## 打开

完整应用：`dist/MacHomePod.app`。本次本机构建包适用于 Apple Silicon、macOS 26.0 及以上；当前验证机器是 macOS 26.6。后端及其运行库已经包含在应用内，运行时不需要 Homebrew、虚拟声卡或管理员权限。

这是本地 ad-hoc 签名版本，没有开发者公证。系统首次运行或音频权限提示由用户确认，不要关闭系统安全保护。下载解压后退出旧版并完整替换“应用程序”中的 `.app`；若出现“无法验证开发者”或“Apple 无法检查恶意软件”，优先按下方步骤在本机从源码构建。本机0.3.0已成功安装并打开，原设备偏好仍保留。下载和历次迭代见 [GitHub Releases](https://github.com/kiki-2586/mac-homepod-dual-output/releases) 与 [更新日志](CHANGELOG.md)。

只使用“原生 AirPlay 跟随”时，从仓库克隆后执行 `bash scripts/build-app.sh`，不必准备 OwnTone。构建后退出旧版，再将 `dist/MacHomePod.app` 复制到“应用程序”并打开。共同播放模式还需先执行 `bash scripts/prepare-backend.sh`。完整 Xcode 不是必需，Command Line Tools 即可。

## 原生 AirPlay 跟随（0.2.0）

1. 先在 Mac TV App／系统声音中选择 HomePod，确认有声且画面同步。系统默认声音输出需为 AirPlay；仅 App 内直接投送、系统仍为本地输出的路径不在当前支持范围。
2. 打开应用，选择“原生 AirPlay 跟随”，勾选本地扬声器，点击“开始本地跟随”。
3. 允许系统音频录制。此模式不启动 OwnTone，不要求本地网络权限，不更改系统输出或 HomePod 音量。
4. 调节 Mac 延迟：提前则增加，落后则减少。本机当前 TV 内容在2000ms时，用户确认两边与画面基本同步；换内容／设备后可能需重调。
5. 停止只停止 Mac 副本，HomePod 继续原生播放。系统默认输出离开原来的 AirPlay 设备时，软件自动停止跟随。

两种模式分别记住每个本地设备的延迟；切换模式前先停止。此模式已包含在v0.2.1发布包中。不能保证所有受保护 TV 内容均可捕获。

### 左右声道分配（0.3.0）

在“原生 AirPlay 跟随”的“声道分配”中选择“Mac 左 · HomePod 右”或“Mac 右 · HomePod 左”，并且只勾选 Mac 内置扬声器。先停止，才能切换或交换左右；选择“立体声同播”可回到原来的完整声道跟随。

分声道会临时替换原声，将选定的一路送回当前 AirPlay 输出，另一路经延迟送往 Mac 内置扬声器。程序保持系统默认输出，不启动 OwnTone，不更改 HomePod 音量；HomePod 音量继续在 TV／系统中调节。停止、启动失败或输出断开后释放捕获并恢复原声。首次使用若一直无捕获数据，约6–8秒后自动停止；允许系统音频录制后可重新开始。

沿用现有 Mac 音量与延迟偏好；未保存延迟时，分声道从2000ms开始。AirPlay 重放保留40ms缓冲以适应捕获与输出回调节奏，并使用20ms软件音量淡变减少突变。启停仍可能有短暂切换声，不承诺无缝切换。这是普通左右立体声，不具备 Apple 空间音频、杜比全景声或头部追踪功能。

临时原型已连续验证60秒。正式0.3.0集成版随后逐项实测：用户确认正向左右分配正确、交换后正确且流畅同步；普通立体声同播重听后，两段两边都有声、流畅且音画基本同步。结果仅覆盖本机 TV App 的自制左右声道视频，详细记录见 `VALIDATION.md`。

## 共同播放

1. Mac 与 HomePod 在同一局域网。家庭 App → 家庭设置 → 扬声器与电视访问，选择“同一网络上的任何人”。
2. macOS 声音输出保持本地设备。Music 自己的输出保持“电脑”，避免原应用绕过本地捕获直接投送 AirPlay。
3. 选择“此 Mac · MacBook Air 扬声器”和 HomePod，点击“开始共同播放”。
4. macOS 提示时允许系统音频录制和本地网络访问。若刚允许权限但没有声音，停止后重新开始。
5. 用鼓点、拍手或节拍素材调节 Mac 同步延迟：Mac 提前就增加，Mac 落后就减少。设备选择、音量和延迟会记住。
6. 点击停止或退出应用恢复普通声音；菜单栏也可停止。关闭窗口会保留菜单栏，退出应用才关闭后端。

首次使用需要完成系统权限提示。没有收到系统音频或后端失去响应时会停止捕获，避免长时间静音。

更新本地签名版本后，若日志显示连接 HomePod “No route to host”，可在“系统设置 → 隐私与安全性 → 本地网络”中将 MacHomePod 关闭再打开，然后退出并重开程序。

## 本机验证

2026-10-22，在 MacBook Air（macOS26.6）与 HomePod（audioOS26.6）实测：本地音频、浏览器普通视频均可双端播放；本机 Mac 延迟1250ms时用户确认基本同步，设置已保存。连续会话超过10分钟未断开，结束听音仍基本同步；停止恢复和退出清理通过。详细结果与未测试项见 `VALIDATION.md`。

## 限制

- 相对同步依赖手动校准，没有经过声学测量的自动同步保证。
- 共同播放模式的后端配置 500ms 起始缓冲，Mac 初始延迟与其一致，实际同步需听音微调；视频画面不会自动补偿，游戏不适合。
- 受保护媒体可能无法捕获；系统录制权限拒绝时也无法转发。
- HomePod 的实际有声、固件兼容性和持续同步必须实机验证，发现到设备不代表已播放成功。
- 后端优先使用 AirPlay 2。已针对 macOS 将 PTP 时钟及音频控制 UDP 监听与回环 HTTP 管理接口分开；普通用户可在当前系统运行，管理接口仍只监听 127.0.0.1。
- 共同播放模式使用本机 `127.0.0.1:3689`，不能同时与另一份监听同端口的 OwnTone 实例运行。

## 构建与测试

应用源码基于 HomeSounds Sync，来源固定在 `UPSTREAM.md`，保留原始 MIT 许可证。

```sh
bash scripts/build-app.sh
bash scripts/test.sh
```

此机器 SwiftPM 动态库与默认 SDK 不匹配，构建脚本直接调用 Swift 编译器并选择已安装的 macOS 15.4 SDK。可用 `MAC_HOMEPOD_SDK=/path/to/MacOSX.sdk` 覆盖。可用 `MAC_HOMEPOD_APP_PATH=dist/MacHomePod-NativeFollow.app` 构建为另一个文件，保留旧版应用。源码平台下限是 macOS 15；本次附带的第三方预编译运行库需要 macOS 26，应用 Info.plist 如实标注。

完整后端重建需要 Homebrew 和 C 编译器：

```sh
MAC_HOMEPOD_BREW_BIN=/path/to/brew bash scripts/prepare-backend.sh
bash scripts/build-app.sh
```

脚本固定 OwnTone 29.2、FFmpeg 7.1.2、libinotify 20240724 的源码和 SHA-256，不注册 LaunchAgent，不安装到系统 Applications。Homebrew 依赖版本以本次构建记录为准；需要其他 macOS 版本时重新构建对应运行库。

`test.sh` 包括实际本机 HTTP 服务，终端必须允许回环网络。测试覆盖采样率与频率、FIFO 断连和背压、设备 API 错误、管道文件保护、系统 tap 排除和原始延迟缓冲回归测试。后端构建后可额外运行 `bash scripts/test-rtsp.sh` 和 `bash scripts/test-ptp.sh`，验证请求释放和真实 UDP 时钟登记。权限与实际听音不能由这些测试替代。

## 本地文件与卸载

运行数据：`~/Library/Application Support/MacHomePod/`。设备偏好使用应用自己的 bundle ID：`local.mac-homepod.dual-output`。

“查看日志”打开该目录的 `backend.log`。应用不保存音频文件，只在内存和本地 FIFO 中传输音频，后端向所选局域网设备发送音频。

退出应用后删除 `.app` 即可停止使用；需要清理记录时，可另外删除上述应用数据目录。本程序不设置开机自启，不改动默认音频输出设备。

## 许可证与对应源码

Swift 应用基于 MIT 项目修改。OwnTone 是独立进程，使用 GPL-2.0；FFmpeg 使用 LGPL-2.1，其他运行库保留各自许可证。应用 Resources/backend/licenses 包含许可证与依赖收据，源码交付包包含 OwnTone、FFmpeg、libinotify 的固定源码包，以及后端构建脚本与兼容性补丁。第三方源代码版本记录见 `THIRD_PARTY_NOTICES.md`。
