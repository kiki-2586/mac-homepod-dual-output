# 第三方组件

HomeSounds Sync：MIT，固定提交 873d605bbcf48a926d48b694cb374865e8e835fd。

OwnTone 29.2（GPL-2.0）、FFmpeg7.1.2（LGPL-2.1）、libinotify20240724 的原始源码包附于源码交付包 vendor-sources/；构建和相对路径打包脚本附于 scripts/；OwnTone 的本地修改完整保存在 patches/，用于分离 LAN 时钟/UDP 与回环 TCP 管理监听、保持双协议时钟登记，以及修复同步连接失败时的请求释放。

本次 runtime Homebrew 组件：

| 组件 | 版本 |
| --- | --- |
| confuse | 3.4 |
| gettext | 1.0 |
| json-c | 0.19 |
| libevent | 2.1.13_1 |
| libgcrypt | 1.12.4 |
| libgpg-error | 1.61 |
| libplist | 2.8.0 |
| libsodium | 1.0.22 |
| libunistring | 1.5 |
| libwebsockets | 5.0.0_2 |
| openssl@4 | 4.0.3 |
| sqlite | 3.54.1 |

每个组件的许可证与瓶装构建收据在 backend/licenses/。源代码上游与配方信息可在组件 INSTALL_RECEIPT.json 的 source 字段及 Homebrew 的公开配方中查阅。

应用自有代码不对后端协议兼容性或第三方固件更新作保证。
