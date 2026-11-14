# 无线Carplay盒子5G中继

两台手机连到无线 CarPlay 盒子的 Wi-Fi。Android 手机用蜂窝数据为 iPhone 转发 IPv4 流量，盒子只提供本地无线链路。

## 安装

1. 从 Releases 下载模块 ZIP，用 KernelSU 安装，再重启 Android。模块通过自带进程按需申请蜂窝网络。升级到 1.2.0 并确认转发生效后，可以卸载旧版「CarPlay 蜂窝连接助手」。
2. 让两个手机连接盒子的 Wi-Fi。在 KernelSU 模块的设置页填写盒子 Wi-Fi 名称、Android 在此网络上的 IPv4 地址、iPhone 的 IPv4 地址，以及 iPhone 在该网络详情中显示的 Wi-Fi 地址（MAC）。选取可用地址以避免 DHCP 地址冲突。
3. 在 iPhone 的 Wi-Fi 详情里使用同网段的手动 IPv4 地址，将路由器填为 Android 的 IPv4 地址，填写可达的 DNS（例如 223.5.5.5），关闭 HTTP 代理。保持 Android 移动数据开启。
4. 在停车状态下验证无线 CarPlay、iPhone 外网和 Android 原有应用。换盒子时按新的网络参数更新即可。

模块只在配置的 Wi-Fi 和 Android 地址匹配时请求蜂窝网络，并限制为指定 iPhone 转发。断开 Wi-Fi 或禁用模块后撤销转发。使用过程中如果盒子 Wi-Fi 没有 DNS 且被安卓选为默认网络，模块会暂时让本机外网流量走蜂窝。模块不启用「移动数据始终开启」。

当前实现需要 KernelSU、Android 29 及以上、iptables 和可用的 rmnet 蜂窝接口。盒子须允许同一 Wi-Fi 下的客户端互通。已在一套设备上验证上网链路，其他设备和实际车机兼容性需要验证。部分澎湃 OS 手机可在「设置 → WLAN → 网络加速」关闭「网络切换」，减少无互联网切换提醒。这个选项会影响该手机的其他 WLAN。

## 构建和卸载

模块 ZIP 的根目录包含 module 目录的文件和 `cellular-request.jar`。使用 Android SDK 35 的 `android.jar` 编译 `cellular-helper/CellularRequest.java`，再用 D8 生成含 `classes.dex` 的 JAR。进程依赖系统的 `app_process` 和当前设备允许 root 注册蜂窝请求，其他 ROM 需要实测。

在 KernelSU 中关闭或卸载模块。在 iPhone 的盒子 Wi-Fi 设置中把 IP 和 DNS 恢复为自动。
