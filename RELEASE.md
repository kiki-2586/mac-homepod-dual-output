# 发布说明

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

构建并实机验证后运行 `python3 scripts/package-release.py`。源码包需准备并校验15份固定第三方源码，默认暂存于 `dist/source-staging/MacHomePod-source/vendor-sources/`。发布构建对应源码应与二进制同时上传，不能仅依赖 GitHub 自动生成的 Swift 源码归档。

正式公证发行需要自己的 Apple Developer ID、嵌套代码签名、Hardened Runtime、公证与 stapling；当前构建不宣称已完成这些步骤。
