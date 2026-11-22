# 无线Carplay盒子5G中继

两台手机连到无线 CarPlay 盒子的 Wi-Fi。Android 手机用蜂窝数据为 iPhone 转发 IPv4 流量，盒子只提供本地无线链路。

## 安装

1. 从 Releases 下载模块 ZIP，用 KernelSU 安装，再重启 Android。模块通过自带进程按需申请蜂窝网络。升级到 1.2.0 并确认转发生效后，可以卸载旧版「CarPlay 蜂窝连接助手」。
2. 让两个手机连接盒子的 Wi-Fi。在 KernelSU 模块的设置页填写盒子 Wi-Fi 名称、Android 在此网络上的 IPv4 地址、iPhone 的 IPv4 地址，以及 iPhone 在该网络详情中显示的 Wi-Fi 地址（MAC）。选取可用地址以避免 DHCP 地址冲突。
3. 在 iPhone 的 Wi-Fi 详情里使用同网段的手动 IPv4 地址，将路由器填为 Android 的 IPv4 地址，填写可达的 DNS（例如 223.5.5.5），关闭 HTTP 代理。保持 Android 移动数据开启。
4. 在停车状态下验证无线 CarPlay、iPhone 外网和 Android 原有应用。换盒子时按新的网络参数更新即可。

模块只在配置的 Wi-Fi 和 Android 地址匹配时请求蜂窝网络，并限制为指定 iPhone 转发。断开 Wi-Fi 或禁用模块后撤销转发。使用过程中如果盒子 Wi-Fi 没有 DNS 且被安卓选为默认网络，模块会暂时让本机外网流量走蜂窝。模块不启用「移动数据始终开启」。

在支持相应流量队列的 Android 手机上，中继运行时会平滑 iPhone 的外网流量，默认下载上限为 24 Mbps，上传上限为 12 Mbps。在模块设置页可以单独调整两项上限，允许 1 到 500 Mbps 的整数。保存后自动应用，无需重启。同网段的本地流量绕过队列。如果某个方向的队列不受支持，或相应接口已有流量规则，该方向仍正常转发。

在设置页勾选「启用 IPv6 中继」后，iPhone 会通过路由器通告自动配置 IPv6。IPv4 和 IPv6 共用下载与上传上限。IPv6 功能需要 ARM64 安卓设备，以及能向手机路由整个 IPv6 /64 前缀的蜂窝网络。开启后可在 iPhone 上访问 IPv6-only 测试页确认运营商是否支持。原有 IPv4 配置仍用于 IPv4 上网。

当前实现需要 KernelSU、Android 29 及以上、iptables 和可用的 rmnet 蜂窝接口。盒子须允许同一 Wi-Fi 下的客户端互通。已在一套设备上验证上网链路，其他设备和实际车机兼容性需要验证。部分澎湃 OS 手机可在「设置 → WLAN → 网络加速」关闭「网络切换」，减少无互联网切换提醒。这个选项会影响该手机的其他 WLAN。

在支持对应通知接口的澎湃 OS 上，模块会暂缓当前盒子网络的「当前 WLAN 无法访问互联网」通知。控制中心的 WLAN 连接状态仍由系统显示。

在设置页启用「修复盒子 Wi-Fi 自动连接」，可尝试让 Android 记住这个网络允许无互联网。系统扫描到盒子时，如果手机未连接其他 Wi-Fi，模块会用系统中已经保存并允许自动连接的配置发起连接。设置按模块中填写的 Wi-Fi 名称匹配。

模块监听 Android 的 Wi-Fi 扫描和连接事件。盒子未连接时通常等待事件，连接期间定时维护蜂窝转发与 IPv6 通告。系统不支持事件监听时，会回退到定时检查。

## 构建和卸载

模块 ZIP 的根目录包含 module 目录的文件和 `cellular-request.jar`。使用 Android SDK 35 的 `android.jar` 编译 `cellular-helper` 下的 Java 源码，再用 D8 生成含 `classes.dex` 的 JAR。进程依赖系统的 `app_process` 和当前设备允许 root 调用相关网络接口，其他 ROM 需要实测。

IPv6 版本还需将 `ipv6-helper/ra.go` 以 `GOOS=linux GOARCH=arm64 CGO_ENABLED=0` 编译为 `relay-ra` 并放在 ZIP 根目录。

在 KernelSU 中关闭或卸载模块。在 iPhone 的盒子 Wi-Fi 设置中把 IP 和 DNS 恢复为自动。
