# 贡献指南

欢迎提交设备兼容性反馈、问题报告和 Pull Request。请提供 macOS 版本、HomePod 型号/固件、复现步骤与脱敏日志，不要提交录音、访问令牌或家庭网络信息。

## 构建和验证

```sh
bash scripts/build-app.sh
bash scripts/test.sh
```

后端构建需要 Homebrew：

```sh
bash scripts/prepare-backend.sh
bash scripts/build-app.sh
bash scripts/test-rtsp.sh
bash scripts/test-ptp.sh
```

脚本优先使用已安装的 macOS15.4 SDK，缺失时选择当前 Xcode/Command Line Tools SDK；可用 `MAC_HOMEPOD_SDK` 显式覆盖。额外后端回归依赖已编译的 OwnTone 源码和 Homebrew 库，可用 `MAC_HOMEPOD_BREW_PREFIX` 指定前缀。

自动测试不能证明 HomePod 已出声或两边声学同步。涉及捕获、缓冲、重采样和生命周期的修改需补充有意义的回归测试；发布前仍需实际双设备听音、停止恢复和连续播放验证。

## 约定

- 保留原作者与第三方许可证。
- 不在音频回调中进行阻塞 I/O。
- 不自动安装驱动、LaunchAgent 或关闭系统安全保护。
- 中文界面说明实际状态，区分已连接、正在传输和用户确认有声。
- 调整 OwnTone 时，补丁放入 `patches/`，同步更新源码版本、构建脚本和第三方说明。
