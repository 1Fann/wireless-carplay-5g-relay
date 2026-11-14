#!/system/bin/sh
# KernelSU late-start service for a wireless CarPlay network.
set -u
export PATH=/system/bin:/system/xbin:/vendor/bin
umask 077

module=${0%/*}
lan=wlan0
state=/data/adb/carplay-5g-relay
chain=CARPLAY5G
forward_owner=carplay_5g_relay
uplink=
table=
owns_chain=0
cellular_pid=
forward_requested=0
saved_wifi_default=
power_save_changed=0

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$state/relay.log"; }

clear_route() {
    [ "$owns_chain" = 1 ] || return 0
    iptables -w -t nat -D POSTROUTING -s "$iphone/32" -o "$uplink" -j MASQUERADE 2>/dev/null || :
    iptables -w -D FORWARD -j "$chain" 2>/dev/null || :
    iptables -w -F "$chain" 2>/dev/null || :
    iptables -w -X "$chain" 2>/dev/null || :
    ip -4 rule del pref 14550 iif "$lan" from "$iphone/32" 2>/dev/null || :
    ip -4 rule del pref 14551 iif "$uplink" to "$iphone/32" lookup main 2>/dev/null || :
    log "Stopped forwarding via $uplink"
    owns_chain=0
}

start_route() {
    if ip -4 rule show | grep -qE '^(14550|14551):' || iptables -w -S "$chain" >/dev/null 2>&1; then
        return 1
    fi
    uplink=$1
    table=$2
    iptables -w -N "$chain" || return 1
    owns_chain=1
    iptables -w -A "$chain" -i "$lan" -o "$uplink" -s "$iphone/32" -m mac --mac-source "$iphone_mac" -j ACCEPT &&
    iptables -w -A "$chain" -i "$lan" -o "$uplink" -s "$iphone/32" -j DROP &&
    iptables -w -A "$chain" -i "$uplink" -o "$lan" -d "$iphone/32" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT &&
    iptables -w -A "$chain" -i "$uplink" -o "$lan" -d "$iphone/32" -j DROP &&
    iptables -w -I FORWARD 1 -j "$chain" &&
    iptables -w -t nat -I POSTROUTING 1 -s "$iphone/32" -o "$uplink" -j MASQUERADE &&
    ip -4 rule add pref 14550 iif "$lan" from "$iphone/32" lookup "$table" &&
    ip -4 rule add pref 14551 iif "$uplink" to "$iphone/32" lookup main
}

request_cellular() {
    if [ -n "$cellular_pid" ] && kill -0 "$cellular_pid" 2>/dev/null; then
        return 0
    fi
    CLASSPATH="$module/cellular-request.jar" /system/bin/app_process /system/bin \
        --nice-name=carplay-cellular-request local.carplay.cellular.CellularRequest \
        9>&- >"$state/cellular-request.log" 2>&1 &
    cellular_pid=$!
}

release_cellular() {
    [ -n "$cellular_pid" ] || return 0
    kill -TERM "$cellular_pid" 2>/dev/null || :
    wait "$cellular_pid" 2>/dev/null || :
    cellular_pid=
}

restore_local_network() {
    if [ -n "$saved_wifi_default" ]; then
        current=$(printf '' | dumpsys connectivity 2>/dev/null | awk '/Active default network:/ {print $NF;exit}')
        if [ "$current" = "$saved_wifi_default" ]; then
            ndc network default set "$current" >/dev/null 2>&1
        fi
        saved_wifi_default=
    fi
    if [ "$power_save_changed" = 1 ]; then
        iw dev "$lan" set power_save on 2>/dev/null
        power_save_changed=0
    fi
    if [ "$forward_requested" = 1 ]; then
        ndc ipfwd disable "$forward_owner" >/dev/null 2>&1
        forward_requested=0
    fi
}

configure_local_network() {
    if [ "$forward_requested" = 0 ] &&
        ndc ipfwd enable "$forward_owner" | grep -q '^200 '; then
        forward_requested=1
    fi
    if [ "$power_save_changed" = 0 ] &&
        iw dev "$lan" get power_save | grep -q 'Power save: on' &&
        iw dev "$lan" set power_save off; then
        power_save_changed=1
    fi
}

load_settings() {
    [ -s "$state/network.conf" ] || return 1
    {
        IFS= read -r next_ssid &&
        IFS= read -r next_lan &&
        IFS= read -r next_phone &&
        IFS= read -r next_mac
    } <"$state/network.conf" || return 1
    [ -n "$next_ssid" ] && [ "$next_lan" != "$next_phone" ] || return 1
    for address in "$next_lan" "$next_phone"; do
        printf '%s\n' "$address" | awk -F. 'NF!=4 {exit 1} {for(i=1;i<=4;i++) if ($i !~ /^[0-9]+$/ || $i>255) exit 1}' || return 1
    done
    printf '%s\n' "$next_mac" | grep -Eiq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || return 1
    if [ "${lan_ip:-}" != "$next_lan" ] || [ "${iphone:-}" != "$next_phone" ] ||
        [ "${iphone_mac:-}" != "$next_mac" ] || [ "${ssid:-}" != "$next_ssid" ]; then
        clear_route
        restore_local_network
        release_cellular
    fi
    ssid=$next_ssid
    lan_ip=$next_lan
    iphone=$next_phone
    iphone_mac=$next_mac
}

prefer_cellular_default() {
    # The framework can still report Wi-Fi as default after the netd change.
    # Only override that default when it is our local-only Wi-Fi.
    set -- $network_summary
    [ "$#" = 3 ] && [ "$1" = 1 ] || return 0
    if ndc network default set "$3" | grep -q '^200 '; then
        saved_wifi_default=$2
    fi
}

read_cellular_network() {
    # Prefer the current usable cellular interface when Android has several
    # concurrent data connections, including during a handover.
    printf '' | dumpsys connectivity 2>/dev/null | awk -v lan="$lan" -v previous="$uplink" '
      /Active default network:/ { current=$NF }
      /NetworkAgentInfo\{network\{[0-9]+\}/ {
        id=$0; sub(/^.*NetworkAgentInfo\{network\{/,"",id); sub(/\}.*/,"",id)
        if (index($0,"InterfaceName: " lan " ") && index($0,"DnsAddresses: [ ]")) wifi=id
        if (!index($0,"Transports: CELLULAR") || !index($0,"&INTERNET") ||
            !index($0,"&VALIDATED") || !index($0,"&NOT_SUSPENDED")) next
        iface=$0; sub(/^.*lp\{\{InterfaceName: /,"",iface); sub(/ .*/,"",iface)
        if (iface !~ /^rmnet[A-Za-z0-9_]+$/) next
        cell[iface]=id
        if (first=="") first=iface
      }
      END {
        iface = (previous in cell) ? previous : first
        if (iface!="") print (wifi!="" && current==wifi ? 1 : 0), (wifi=="" ? "-" : wifi), cell[iface], iface
      }'
}

route_is_intact() {
    iptables -w -C FORWARD -j "$chain" >/dev/null 2>&1 &&
    iptables -w -t nat -C POSTROUTING -s "$iphone/32" -o "$uplink" -j MASQUERADE >/dev/null 2>&1 &&
    ip -4 route get 1.1.1.1 from "$iphone" iif "$lan" 2>/dev/null |
        grep -Fq "dev $uplink "
}

mkdir -p "$state" || exit 1
if [ "${1:-}" != --locked ]; then
    exec /data/adb/ksu/bin/busybox flock -n "$state/module.lock" /system/bin/sh "$0" --locked
fi
trap 'clear_route; restore_local_network; release_cellular' EXIT
trap 'exit 0' HUP INT TERM
while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 5; done

while [ -f "$module/module.prop" ] && [ ! -e "$module/remove" ]; do
    if [ -e "$module/disable" ]; then
        clear_route
        restore_local_network
        release_cellular
        sleep 5
        continue
    fi
    if ! load_settings; then
        clear_route
        restore_local_network
        release_cellular
        sleep 5
        continue
    fi
    wifi=$(iw dev "$lan" link 2>/dev/null)
    case "$wifi" in
        "Connected to "*)
            if printf '%s\n' "$wifi" | grep -Fxq "$(printf '\tSSID: %s' "$ssid")" &&
                ip -4 addr show dev "$lan" | grep -Fq "inet $lan_ip/"; then
                request_cellular
                configure_local_network
                set -- $(read_cellular_network)
                network_summary=
                if [ "$#" = 4 ]; then
                    network_summary="$1 $2 $3"
                    chosen_uplink=$4
                    set -- $(ip -4 route show table all |
                        awk -v iface="$chosen_uplink" '$1=="default" && $4=="dev" && $5==iface && $6=="table" {print $5,$7;exit}')
                else
                    set --
                fi
                if [ "$#" = 2 ] && [ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ]; then
                    prefer_cellular_default
                    if [ "$owns_chain" = 1 ] && [ "$1" = "$uplink" ] && [ "$2" = "$table" ] &&
                        route_is_intact; then
                        sleep 5
                        continue
                    fi
                    clear_route
                    if start_route "$1" "$2"; then
                        log "Forwarding $iphone through $uplink"
                    else
                        clear_route
                    fi
                    sleep 5
                    continue
                fi
                clear_route
                sleep 5
                continue
            fi
            ;;
    esac
    clear_route
    restore_local_network
    release_cellular
    sleep 5
done
