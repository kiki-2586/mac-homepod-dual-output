# Mac HomePod 同播

将 Mac 的普通系统音频同时发送到 Mac 扬声器和同一局域网中的 HomePod，并手动调节相对延迟。

## 打开

完整应用：`dist/MacHomePod.app`。本次本机构建包适用于 Apple Silicon、macOS 26.0 及以上；当前验证机器是 macOS 26.6。后端及其运行库已经包含在应用内，运行时不需要 Homebrew、虚拟声卡或管理员权限。

这是本地 ad-hoc 签名版本，没有开发者公证。系统首次运行或音频权限提示由用户确认，不要关闭系统安全保护。

## 使用

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
- 后端配置 500ms 起始缓冲，Mac 初始延迟与其一致，实际同步需听音微调；视频画面不会自动补偿，游戏不适合。
- 受保护媒体可能无法捕获；系统录制权限拒绝时也无法转发。
- HomePod 的实际有声、固件兼容性和持续同步必须实机验证，发现到设备不代表已播放成功。
- 后端优先使用 AirPlay 2。已针对 macOS 将 PTP 时钟及音频控制 UDP 监听与回环 HTTP 管理接口分开；普通用户可在当前系统运行，管理接口仍只监听 127.0.0.1。
- 程序使用本机 `127.0.0.1:3689`，不能同时与另一份监听同端口的 OwnTone 实例运行。

## 构建与测试

应用源码基于 HomeSounds Sync，来源固定在 `UPSTREAM.md`，保留原始 MIT 许可证。

```sh
bash scripts/build-app.sh
bash scripts/test.sh
```

此机器 SwiftPM 动态库与默认 SDK 不匹配，构建脚本直接调用 Swift 编译器并选择已安装的 macOS 15.4 SDK。可用 `MAC_HOMEPOD_SDK=/path/to/MacOSX.sdk` 覆盖。源码平台下限是 macOS 15；本次附带的第三方预编译运行库需要 macOS 26，应用 Info.plist 如实标注。

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
