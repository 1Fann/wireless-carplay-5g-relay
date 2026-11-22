# IPv6 forwarding for cellular links that route the full /64 to this phone.
ipv6_enabled=0
ipv6_chain=CARPLAY5G6
ipv6_up_pref=14560
ipv6_down_pref=14561
ipv6_down_table=14563
ipv6_filter_pref=49104
ipv6_prefix=
ipv6_table=
ipv6_last_ra=0
owns_ipv6_chain=0
owns_ipv6_jump=0
owns_ipv6_route=0
owns_ipv6_up=0
owns_ipv6_down=0
owns_ipv6_dl=0
owns_ipv6_ul=0

clear_ipv6() {
    if [ "$ipv6_last_ra" != 0 ] &&
        iw dev "$lan" link | grep -Fxq "$(printf '\tSSID: %s' "$ssid")" &&
        ip -4 addr show dev "$lan" | grep -Fq "inet $lan_ip/"; then
        "$module/relay-ra" "$lan" "$iphone_mac" "$ipv6_prefix" 0 2>/dev/null || :
    fi
    ipv6_last_ra=0
    if [ "$owns_ipv6_dl" = 1 ]; then
        tc filter del dev "$lan" egress protocol ipv6 pref "$ipv6_filter_pref" 2>/dev/null || :
        owns_ipv6_dl=0
    fi
    if [ "$owns_ipv6_ul" = 1 ]; then
        tc filter del dev "$lan" ingress protocol ipv6 pref "$ipv6_filter_pref" 2>/dev/null || :
        owns_ipv6_ul=0
    fi
    if [ "$owns_ipv6_up" = 1 ]; then
        # Android may remove the cellular routing table's name before cleanup.
        ip -6 rule del pref "$ipv6_up_pref" iif "$lan" from "$ipv6_prefix" 2>/dev/null || :
        owns_ipv6_up=0
    fi
    if [ "$owns_ipv6_down" = 1 ]; then
        ip -6 rule del pref "$ipv6_down_pref" iif "$uplink" to "$ipv6_prefix" lookup "$ipv6_down_table" 2>/dev/null || :
        owns_ipv6_down=0
    fi
    if [ "$owns_ipv6_route" = 1 ]; then
        ip -6 route del "$ipv6_prefix" dev "$lan" table "$ipv6_down_table" 2>/dev/null || :
        owns_ipv6_route=0
    fi
    if [ "$owns_ipv6_jump" = 1 ]; then
        ip6tables -w -D FORWARD -j "$ipv6_chain" 2>/dev/null || :
        owns_ipv6_jump=0
    fi
    if [ "$owns_ipv6_chain" = 1 ]; then
        ip6tables -w -F "$ipv6_chain" 2>/dev/null || :
        ip6tables -w -X "$ipv6_chain" 2>/dev/null || :
        owns_ipv6_chain=0
        log "Stopped IPv6 forwarding"
    fi
    ipv6_prefix=
    ipv6_table=
}

start_ipv6() {
    ip -6 rule show | grep -Eq "^($ipv6_up_pref|$ipv6_down_pref):" && return 1
    [ -z "$(ip -6 route show table "$ipv6_down_table" 2>/dev/null || :)" ] || return 1
    ipv6_prefix=$1
    ipv6_table=$2
    ip6tables -w -N "$ipv6_chain" || return 1
    owns_ipv6_chain=1
    ip6tables -w -A "$ipv6_chain" -i "$lan" -o "$uplink" -s "$ipv6_prefix" -d 2000::/3 -m mac --mac-source "$iphone_mac" -j ACCEPT &&
    ip6tables -w -A "$ipv6_chain" -i "$lan" -s "$ipv6_prefix" -j DROP &&
    ip6tables -w -A "$ipv6_chain" -i "$uplink" -o "$lan" -d "$ipv6_prefix" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT &&
    ip6tables -w -A "$ipv6_chain" -o "$lan" -d "$ipv6_prefix" -j DROP &&
    ip6tables -w -I FORWARD 1 -j "$ipv6_chain" || return 1
    owns_ipv6_jump=1
    ip -6 route add "$ipv6_prefix" dev "$lan" table "$ipv6_down_table" || return 1
    owns_ipv6_route=1
    ip -6 rule add pref "$ipv6_down_pref" iif "$uplink" to "$ipv6_prefix" lookup "$ipv6_down_table" || return 1
    owns_ipv6_down=1
    ip -6 rule add pref "$ipv6_up_pref" iif "$lan" from "$ipv6_prefix" lookup "$ipv6_table" || return 1
    owns_ipv6_up=1

    # Share the rate budget with IPv4 while leaving link-local traffic alone.
    if [ "$owns_download_queue" = 1 ]; then
        tc filter add dev "$lan" egress protocol ipv6 pref "$ipv6_filter_pref" u32 \
            match ip6 src 2000::/3 match ip6 dst "$ipv6_prefix" \
            action mirred egress redirect dev "$download_queue" || return 1
        owns_ipv6_dl=1
    fi
    if [ "$owns_upload_queue" = 1 ]; then
        tc filter add dev "$lan" ingress protocol ipv6 pref "$ipv6_filter_pref" u32 \
            match ip6 src "$ipv6_prefix" match ip6 dst 2000::/3 \
            action mirred egress redirect dev "$upload_queue" || return 1
        owns_ipv6_ul=1
    fi
    log "Enabled IPv6 forwarding via $uplink"
}

sync_ipv6() {
    local address next_prefix next_table now
    if [ "$ipv6_enabled" != 1 ] || [ ! -x "$module/relay-ra" ] ||
        [ "$(cat "/proc/sys/net/ipv6/conf/$lan/forwarding" 2>/dev/null)" != 1 ]; then
        clear_ipv6
        return 0
    fi
    address=$(ip -6 -o addr show dev "$uplink" scope global |
        awk '$4 ~ /^[23][0-9a-f]*:.*\/64$/ && $0 !~ / tentative | deprecated / {print $4;exit}')
    next_table=$(ip -6 route show table all |
        awk -v iface="$uplink" '$1=="default" && $4=="dev" && $5==iface && $6=="table" {print $7;exit}')
    if [ -z "$address" ] || [ -z "$next_table" ]; then
        clear_ipv6
        return 0
    fi
    next_prefix=$("$module/relay-ra" prefix "$address") || return 0
    if [ "$ipv6_prefix" != "$next_prefix" ] || [ "$ipv6_table" != "$next_table" ] ||
        ! ip6tables -w -C FORWARD -j "$ipv6_chain" >/dev/null 2>&1; then
        clear_ipv6
        if ! start_ipv6 "$next_prefix" "$next_table"; then
            clear_ipv6
            return 0
        fi
    fi
    now=$(date +%s)
    if [ "$((now - ipv6_last_ra))" -ge 8 ] || [ "$now" -lt "$ipv6_last_ra" ]; then
        if "$module/relay-ra" "$lan" "$iphone_mac" "$ipv6_prefix" 40; then
            ipv6_last_ra=$now
        else
            clear_ipv6
        fi
    fi
}
