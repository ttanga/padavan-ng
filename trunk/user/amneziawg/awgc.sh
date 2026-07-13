#!/bin/sh

###

AWG="awg"
IF_NAME="wg0"
IF_ADDR=$(nvram get vpnc_wg_if_addr)
IF_MTU=$(nvram get vpnc_wg_mtu)
[ "$IF_MTU" ] || IF_MTU=1420
IF_PRIVATE=$(nvram get vpnc_wg_if_private)
IF_PRESHARED=$(nvram get vpnc_wg_if_preshared)
IF_DNS=$(nvram get vpnc_wg_if_dns | tr -d ' ')
IF_JC=$(nvram get vpnc_awg_jc)
IF_JMIN=$(nvram get vpnc_awg_jmin)
IF_JMAX=$(nvram get vpnc_awg_jmax)
IF_S1=$(nvram get vpnc_awg_s1)
IF_S2=$(nvram get vpnc_awg_s2)
IF_H1=$(nvram get vpnc_awg_h1)
IF_H2=$(nvram get vpnc_awg_h2)
IF_H3=$(nvram get vpnc_awg_h3)
IF_H4=$(nvram get vpnc_awg_h4)
IF_I1=$(nvram get vpnc_awg_i1)

PEER_PUBLIC=$(nvram get vpnc_wg_peer_public)
PEER_PORT=$(nvram get vpnc_wg_peer_port)
PEER_ENDPOINT="$(nvram get vpnc_wg_peer_endpoint)${PEER_PORT:+":$PEER_PORT"}"
PEER_KEEPALIVE=$(nvram get vpnc_wg_peer_keepalive)
PEER_ALLOWEDIPS="$(nvram get vpnc_wg_peer_allowedips | tr -d ' ')"
POST_SCRIPT="/etc/storage/vpnc_server_script.sh"
REMOTE_NETWORK_LIST="/etc/storage/vpnc_remote_network.list"
EXCLUDE_NETWORK_LIST="/etc/storage/vpnc_exclude_network.list"

FWMARK=51820
TABLE=51

PREF_WG=5182
PREF_MAIN=5181
PREF_SUPPRESS=5180

WAN_ADDR=$(nvram get wan_ipaddr)
WAN0_ADDR=$(nvram get wan0_ipaddr)
WAN0_IFNAME=$(nvram get wan0_ifname)
WAN0_GW=$(nvram get wan0_gateway)

# if iproute2 is not available
IPBB=$(ip 2>&1 | grep -i busybox)

###

log()
{
	[ -n "$*" ] || return
	echo "$@"
	logger -t amneziawg "$@"
}

error()
{
	log "error: $@"
	exit 1
}

die()
{
	echo "$@" >&2
	exit 1
}

is_started()
{
	ip link show ${IF_NAME} >/dev/null 2>&1
	return $?
}

prepare_awg()
{
	modprobe -q amneziawg >/dev/null 2>&1
	sysctl -q net.ipv4.conf.all.src_valid_mark=1
	sysctl -q net.ipv6.conf.all.disable_ipv6=0 2>/dev/null
	sysctl -q net.ipv6.conf.all.forwarding=1 2>/dev/null
}

awg_setdns()
{
	[ "$IF_DNS" ] || return

	local getdns=$(nvram get vpnc_pdns)
	[ "$getdns" = "0" ] && return

	nvram set vpnc_dns_t="$IF_DNS"

	if [ "$getdns" = "2" ]; then
		sed -i "/nameserver/d" /etc/resolv.conf
		echo "nameserver 127.0.0.1" >> /etc/resolv.conf
	fi

	for i in $(echo "$IF_DNS" | tr ',' '\n'); do
		grep -qE "nameserver ${i}\s*$" /etc/resolv.conf \
			|| echo "nameserver $i" >> /etc/resolv.conf
	done

	restart_dns
}

append_if_set()
{
	[ -n "$2" ] && echo "$1 = $2" >> "/tmp/${IF_NAME}.conf.$$"
}

setconf_awg()
{
	is_started || return 1

	cat > "/tmp/${IF_NAME}.conf.$$" <<EOF
[Interface]
PrivateKey = $IF_PRIVATE
EOF

	# AmneziaWG extensions are parsed in [Interface] section.
	append_if_set "Jc" "$IF_JC"
	append_if_set "Jmin" "$IF_JMIN"
	append_if_set "Jmax" "$IF_JMAX"
	append_if_set "S1" "$IF_S1"
	append_if_set "S2" "$IF_S2"
	append_if_set "H1" "$IF_H1"
	append_if_set "H2" "$IF_H2"
	append_if_set "H3" "$IF_H3"
	append_if_set "H4" "$IF_H4"
	append_if_set "I1" "$IF_I1"

	cat >> "/tmp/${IF_NAME}.conf.$$" <<EOF

[Peer]
PublicKey = $PEER_PUBLIC
Endpoint = $PEER_ENDPOINT
PersistentKeepalive = $PEER_KEEPALIVE
AllowedIPs = $PEER_ALLOWEDIPS
EOF
	[ "$IF_PRESHARED" ] && echo "PresharedKey = $IF_PRESHARED" >> "/tmp/${IF_NAME}.conf.$$"

	local ipv6=$(ip -6 route show default)

	[ ! "$ipv6" ] && echo "precedence ::ffff:0:0/96  100" > /etc/gai.conf
	local res=$($AWG setconf $IF_NAME "/tmp/${IF_NAME}.conf.$$" 2>&1)
	rm -f "/tmp/${IF_NAME}.conf.$$"
	[ ! "$ipv6" ] && rm -f /etc/gai.conf

	if ! echo "$res" | grep -q "error"; then
		log "configuration $IF_NAME applied successfully"
		$AWG show $IF_NAME | grep -A 5 "peer:" | while read i; do
			log "  $i"
		done
	else
		echo "$res" | while read i; do
			log "$i"
		done
		return 1
	fi
}

start_awg()
{
	local i p iplist

	[ "$(nvram get vpnc_type)" = "4" -a "$(nvram get vpnc_enable)" = "1" ] || die "disabled"
	is_started && die "already started"

	prepare_awg

	ip link add dev $IF_NAME type amneziawg || error "cannot create $IF_NAME"
	ip link set dev $IF_NAME mtu $IF_MTU

	for i in $(echo "$IF_ADDR" | tr ',' '\n'); do
		p=4; [ "$i" != "${i#*:}" ] && p=6
		ip -$p addr add "$i" dev $IF_NAME 2>/dev/null || log "warning: cannot set $IF_NAME address $i"
	done

	local if_ip=$(ip addr show dev $IF_NAME | awk '/inet/{print $2}')
	[ "$if_ip" ] || error "$IF_NAME interface address not set"

	setconf_awg || die

	if ip link set $IF_NAME up; then
		log "client started, interface: $IF_NAME, addresses: $if_ip"
	else
		error "$IF_NAME startup failed"
	fi

	msg_unable() ( log "warning: unable to add route for $1 from $2 list" )

	$AWG set $IF_NAME fwmark $FWMARK

	[ ! "$IPBB" ] && for p in 4 6; do
		ip -$p rule add not fwmark $FWMARK table $TABLE pref $PREF_WG
		ip -$p rule add table main suppress_prefixlength 0 pref $PREF_SUPPRESS
	done

	# if iproute2 is not available - use $TABLE for exclude network
	[ "$IPBB" -a "$WAN0_GW" -a "$WAN0_IFNAME" ] && ip route add default via $WAN0_GW dev $WAN0_IFNAME table $TABLE

	if [ "$(nvram get vpnc_dgw)" = "1" ]; then
		if [ "$IPBB" ]; then
			ip route add 0/1 dev $IF_NAME
			ip route add 128/1 dev $IF_NAME
			log "  add default route dev $IF_NAME"
		else
			for p in 4 6; do
				ip -$p route add default dev $IF_NAME table $TABLE \
					&& log "  add ipv$p default route dev $IF_NAME table $TABLE" \
					|| log "  unable to add ipv$p default route dev $IF_NAME table $TABLE"
			done
		fi
	else
		iplist=$(cat "$REMOTE_NETWORK_LIST" | grep -v "^#")
		for i in $iplist; do
			if [ "$IPBB" ]; then
				[ "$i" != "${i#*:}" ] && continue
				ip route add "$i" dev $IF_NAME || msg_unable "$i" "remote network"
			else
				p=4; [ "$i" != "${i#*:}" ] && p=6
				ip -$p route add "$i" dev $IF_NAME table $TABLE || msg_unable "$i" "remote network"
			fi
		done

		iplist=$($AWG show $IF_NAME allowed-ips | cut -f2-)
		for i in $iplist; do
			case "$i" in
				*/0) continue;;
				*:*) p="6";;
				*)   p="4";;
			esac
			if [ "$IPBB" ]; then
				[ "$p" = "4" ] && ip route add "$i" dev $IF_NAME || msg_unable "$i" "allowed ips"
			else
				ip -$p route add "$i" dev $IF_NAME table $TABLE || msg_unable "$i" "allowed ips"
			fi
		done
	fi

	iplist=$(cat "$EXCLUDE_NETWORK_LIST" | grep -v "^#")
	for i in $iplist; do
		if [ "$IPBB" ]; then
			case "$i" in
				*/0|*:*) continue;;
			esac
			ip rule add from "$i" table $TABLE pref $PREF_MAIN
		else
			p=4; [ "$i" != "${i#*:}" ] && p=6
			ip -$p rule add from "$i" lookup main pref $PREF_MAIN || msg_unable "$i" "exclude network"
		fi
	done

	local endpoint=$($AWG show $IF_NAME endpoints | sed -r 's/^.+\t//; s/:[0-9]+$//')
	[ "$endpoint" ] && if [ "$IPBB" ]; then
		ip rule add to "$endpoint" table $TABLE pref $PREF_MAIN
	else
		p=4; [ "$endpoint" != "${endpoint#*:}" ] && p=6
		ip -$p rule add to "$endpoint" lookup main pref $PREF_MAIN 2>/dev/null
	fi

	for i in $WAN_ADDR $WAN0_ADDR; do
		[ "$i" = "0.0.0.0" ] && continue
		if [ "$IPBB" ]; then
			ip rule add from "$i" table $TABLE pref $PREF_MAIN
		else
			ip -4 rule add from "$i" lookup main pref $PREF_MAIN
		fi
	done

	awg_setdns

	# trying to send a packet through AWG for activating web indicator
	ping -c1 -W1 -I $IF_NAME 8.8.8.8 >/dev/null 2>&1 &
}

stop_awg()
{
	local i p

	is_started || return

	[ "$IPBB" ] && ip route del default table $TABLE 2>/dev/null

	for i in $PREF_SUPPRESS $PREF_MAIN $PREF_WG; do
		for p in 4 6; do
			while ip -$p rule del pref $i 2>/dev/null; do true; done
		done
	done

	ip link set $IF_NAME down
	ip link del dev $IF_NAME

	log "client stopped"
}

case $1 in
	start)
		start_awg
	;;

	stop)
		stop_awg
	;;

	restart)
		stop_awg
		start_awg
	;;
esac

IFNAME=$IF_NAME
# first interface address
IPLOCAL=$(echo "$IF_ADDR" | tr ',' '\n' | head -n1)
# IF_PRIVATE
# PEER_PUBLIC
# PEER_ENDPOINT
# PEER_KEEPALIVE
# PEER_ALLOWEDIPS

[ -s "$POST_SCRIPT" -a -x "$POST_SCRIPT" ] && . "$POST_SCRIPT"
