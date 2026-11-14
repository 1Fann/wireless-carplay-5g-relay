# Sourced by the KernelSU module installer.
helper="$MODPATH/cellular-helper.apk"
[ -s "$helper" ] || abort "安装包缺少蜂窝连接助手。"

helper_size=$(wc -c <"$helper")
case "$helper_size" in ''|*[!0-9]*) abort "无法读取蜂窝连接助手大小。" ;; esac

# Stream the bundled APK so Android's package manager can read it without
# opening a root-only file in the KernelSU module directory.
install_result=$(cat "$helper" | /system/bin/pm install -r -S "$helper_size" 2>&1)
if [ "$?" -ne 0 ] || ! printf '%s\n' "$install_result" | grep -qx Success; then
    ui_print "$install_result"
    abort "蜂窝连接助手安装失败。请检查 Android 安装提示后重试。"
fi
ui_print "已一并安装蜂窝连接助手。"
rm -f "$helper"
