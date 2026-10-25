#!/bin/bash

declare -g SERVER_AWG_IF_CONF_ROOT_DIR="/etc/amnezia/amneziawg"

function distribution() {
    if [ ! -f "/etc/debian_version" ]; then
        echo "ERROR: Linux distribution must be Ubuntu!"
        exit 1
    fi
}

function num1.num2.num3_lt() {
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"
}

function kernel() {
    if num1.num2.num3_lt "$(uname -r | cut -d- -f1)" "5.6.0"; then
        echo "ERROR: Kernel version must be >= 5.6.0!"
        exit 1
    fi
}

function root() {
    if [ "$(echo ${USER})" != "root" ]; then
        echo "WARNING: You must be root to run the script!"
        exit 1
    fi
}

function awg_tools_status() {
    if [ -f "/usr/bin/awg" ] && [ -f "/usr/bin/awg-quick" ]; then
        return 0
    else
        return 1
    fi
}

function install_awg_dkms_and_awg_tools() {
    if [ ! -f "/lib/modules/$(uname -r)/updates/dkms/amneziawg.ko.zst" ] && [ ! -f "/usr/bin/awg" ] && [ ! -f "/usr/bin/awg-quick" ]; then
        apt install software-properties-common python3-launchpadlib gnupg2 linux-headers-$(uname -r) -y >/dev/null 2>&1
        add-apt-repository --no-update ppa:amnezia/ppa -y >/dev/null 2>&1
        apt-get update -y >/dev/null 2>&1
        apt-get install amneziawg -y
    else
        echo "NOTICE: amneziawg-dkms and amneziawg-tools is installed, no need to reinstall!"
    fi
    exit 0
}

function generate_awg_ifs() {
    local AWG_TOOLS_STATUS="$?"

    if [ ${AWG_TOOLS_STATUS} -eq 0 ]; then
        local SERVER_PUBLIC_IPV6="$(curl -s -6 https://cloudflare.com/cdn-cgi/trace | grep ip | awk -F '=' '{ print $2 }')"
        local SERVER_PUBLIC_NIC="$(ip -4 -o route get 1.1.1.1 | awk '{ print $5 }')"

        local SERVER_AWG_NIC="awg0"
        local SERVER_AWG_PORT="51820"
        local SERVER_AWG_HEADER_PROTECTION_KEY="$(awg genkey)"
        local AWG_MTU="1280"

        local SERVER_AWG_IF_CONF="${SERVER_AWG_IF_CONF_ROOT_DIR}/${SERVER_AWG_NIC}.conf"
        local CLIENT_AWG_IF_CONF="${SERVER_AWG_IF_CONF_ROOT_DIR}/${SERVER_AWG_NIC}-client.conf"

        local SERVER_AWG_IPV4="10.0.0.1"
        local SERVER_AWG_IPV6="fd00::1"
        local SERVER_PRIVATE_KEY="$(awg genkey)"
        local SERVER_PUBLIC_KEY="$(echo ${SERVER_PRIVATE_KEY} | awg pubkey)"

        local CLIENT_AWG_IPV4="10.0.0.2"
        local CLIENT_AWG_IPV6="fd00::2"
        local CLIENT_PRIVATE_KEY="$(awg genkey)"
        local CLIENT_PUBLIC_KEY="$(echo ${CLIENT_PRIVATE_KEY} | awg pubkey)"
        local CLIENT_PRESHARED_KEY="$(awg genpsk)"

        generate_server_awg_if
        generate_client_awg_if
        chmod -R 400 ${SERVER_AWG_IF_CONF_ROOT_DIR}

        echo ${SERVER_AWG_IF_CONF}
        echo ${CLIENT_AWG_IF_CONF}
        exit 0
    else
        echo "ERROR: Not installed, you must install amneziawg-dkms and amneziawg-tools!"
        exit 1
    fi
}

function generate_server_awg_if() {
    cat >${SERVER_AWG_IF_CONF} <<EOF
[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = ${SERVER_AWG_IPV4}/32, ${SERVER_AWG_IPV6}/128
ListenPort = ${SERVER_AWG_PORT}
MTU = ${AWG_MTU}
S1 = 20
S2 = 20
S3 = 20
S4 = 20
H1 = 1
H2 = 2
H3 = 3
H4 = 4
I1 = <r 128>
Jc = 5
Jmin = 65
Jmax = 250
HeaderProtectionKey = ${SERVER_AWG_HEADER_PROTECTION_KEY}
ContentPaddingAddition = 0-16
RekeyAfterTime = 0-0
RekeyTimeout = 0-0
RejectAfterTime = 0-0
KeepaliveTimeout = 0-0
MaxHandshakeAttempts = 0-0
RandomTrailers = on
DisableCookies = off
PreUp = sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
PreUp = sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1
PreUp = sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
PreUp = sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
PostUp = iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP
PostUp = iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PostUp = iptables -A FORWARD -i ${SERVER_AWG_NIC} -o ${SERVER_PUBLIC_NIC} -j ACCEPT
PostUp = iptables -A FORWARD -i ${SERVER_PUBLIC_NIC} -o ${SERVER_AWG_NIC} -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_PUBLIC_NIC} -j MASQUERADE
PostUp = ip6tables -A FORWARD -m conntrack --ctstate INVALID -j DROP
PostUp = ip6tables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PostUp = ip6tables -A FORWARD -i ${SERVER_AWG_NIC} -o ${SERVER_PUBLIC_NIC} -j ACCEPT
PostUp = ip6tables -A FORWARD -i ${SERVER_PUBLIC_NIC} -o ${SERVER_AWG_NIC} -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o ${SERVER_PUBLIC_NIC} -j MASQUERADE
PreDown = iptables -D FORWARD -m conntrack --ctstate INVALID -j DROP
PreDown = iptables -D FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PreDown = iptables -D FORWARD -i ${SERVER_AWG_NIC} -o ${SERVER_PUBLIC_NIC} -j ACCEPT
PreDown = iptables -D FORWARD -i ${SERVER_PUBLIC_NIC} -o ${SERVER_AWG_NIC} -j ACCEPT
PreDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUBLIC_NIC} -j MASQUERADE
PreDown = ip6tables -D FORWARD -m conntrack --ctstate INVALID -j DROP
PreDown = ip6tables -D FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PreDown = ip6tables -D FORWARD -i ${SERVER_AWG_NIC} -o ${SERVER_PUBLIC_NIC} -j ACCEPT
PreDown = ip6tables -D FORWARD -i ${SERVER_PUBLIC_NIC} -o ${SERVER_AWG_NIC} -j ACCEPT
PreDown = ip6tables -t nat -D POSTROUTING -o ${SERVER_PUBLIC_NIC} -j MASQUERADE
PostDown = sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1
PostDown = sysctl -w net.ipv6.conf.all.forwarding=0 >/dev/null 2>&1
PostDown = sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1
PostDown = sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${CLIENT_AWG_IPV4}/32, ${CLIENT_AWG_IPV6}/128
EOF
}

function generate_client_awg_if() {
    cat >${CLIENT_AWG_IF_CONF} <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_AWG_IPV4}/32, ${CLIENT_AWG_IPV6}/128
DNS = 1.1.1.1, 1.0.0.1, 1.1.1.2, 1.0.0.2, 1.1.1.3, 1.0.0.3
DNS = 2606:4700:4700::1111, 2606:4700:4700::1001, 2606:4700:4700::1112, 2606:4700:4700::1002, 2606:4700:4700::1113, 2606:4700:4700::1003
MTU = ${AWG_MTU}
S1 = 20
S2 = 20
S3 = 20
S4 = 20
H1 = 1
H2 = 2
H3 = 3
H4 = 4
I1 = <r 128>
Jc = 5
Jmin = 65
Jmax = 250
HeaderProtectionKey = ${SERVER_AWG_HEADER_PROTECTION_KEY}
ContentPaddingAddition = 0-16
RekeyAfterTime = 0-0
RekeyTimeout = 0-0
RejectAfterTime = 0-0
KeepaliveTimeout = 0-0
MaxHandshakeAttempts = 0-0
RandomTrailers = on
DisableCookies = off

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = [${SERVER_PUBLIC_IPV6}]:${SERVER_AWG_PORT}
PersistentKeepalive = 25
EOF
}

function generate_all_clients_awg_ifs() {
    if [ -d "${SERVER_AWG_IF_CONF_ROOT_DIR}" ]; then
        cd ${SERVER_AWG_IF_CONF_ROOT_DIR}
    else
        echo "ERROR: No such a directory!"
        echo "  - /etc/amnezia/amneziawg"
        exit 1
    fi

    if [ -f "awg0.conf" ] && [ -f "awg0-client.obfs.conf" ]; then
        local CLIENT_AWG_IF_CONFS=(
            "3 openwrt.obfs.conf"
            "4 ubuntu.obfs.conf"
            "5 macos.obfs.conf"
            "6 windows.obfs.conf"
            "7 ios.obfs.conf"
            "8 ipados.obfs.conf"
            "9 android.obfs.conf"
        )

        for A_CLIENT_AWG_IF_CONF in "${CLIENT_AWG_IF_CONFS[@]}"; do
            local NUM=$(echo ${A_CLIENT_AWG_IF_CONF} | cut -d ' ' -f1)
            local FILENAME=$(echo ${A_CLIENT_AWG_IF_CONF} | cut -d ' ' -f2)

            cp awg0-client.obfs.conf "${FILENAME}"

            local CLIENT_AWG_IPV4="10.0.0.${NUM}"
            local CLIENT_AWG_IPV6="fd00::${NUM}"
            local CLIENT_PRIVATE_KEY="$(awg genkey)"
            local CLIENT_PUBLIC_KEY="$(echo ${CLIENT_PRIVATE_KEY} | awg pubkey)"
            local CLIENT_PRESHARED_KEY="$(awg genpsk)"

            sed -i "s|^\(PrivateKey\s*=\s*\).*|\1${CLIENT_PRIVATE_KEY}|" "${FILENAME}"
            sed -i "s|^\(Address\s*=\s*\).*|\1${CLIENT_AWG_IPV4}/32, ${CLIENT_AWG_IPV6}/128|" "${FILENAME}"
            sed -i "s|^\(PresharedKey\s*=\s*\).*|\1${CLIENT_PRESHARED_KEY}|" "${FILENAME}"

            cat >>awg0.conf <<EOF

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${CLIENT_AWG_IPV4}/32, ${CLIENT_AWG_IPV6}/128
EOF
        done
        chmod -R 400 ${SERVER_AWG_IF_CONF_ROOT_DIR}
        exit 0
    else
        echo "ERROR: No such files!"
        echo "  - /etc/amnezia/amneziawg/awg0.conf"
        echo "  - /etc/amnezia/amneziawg/awg0-client.obfs.conf"
        exit 1
    fi
}

function remove() {
    if [ -f "/lib/modules/$(uname -r)/updates/dkms/amneziawg.ko.zst" ] && [ -f "/usr/bin/awg" ] && [ -f "/usr/bin/awg-quick" ]; then
        awg-quick down ${SERVER_AWG_NIC} >/dev/null 2>&1
        apt-get purge amneziawg amneziawg-dkms amneziawg-tools -y >/dev/null 2>&1
        add-apt-repository --no-update --remove ppa:amnezia/ppa -y >/dev/null 2>&1
        apt-get purge software-properties-common python3-launchpadlib gnupg2 linux-headers-$(uname -r) -y >/dev/null 2>&1
        apt-get autoremove --purge -y >/dev/null 2>&1
        apt-get update -y >/dev/null 2>&1
        rm -rf ${SERVER_AWG_IF_CONF_ROOT_DIR} >/dev/null 2>&1
    else
        echo "NOTICE: Not installed, no need to remove!"
    fi
    exit 0
}

function help() {
    cat <<EOF
USAGE
  bash amneziawg3x.sh [OPTION]

OPTION
  -h, --help         Show help manual
  -i, --install      Install "amneziawg-dkms and amneziawg-tools"
  -g, --generate     Generate a pair of new AmneziaWG interface configuration files
  -G, --generate-all Generate some new AmneziaWG interface configuration files for all clients
                       - 3 openwrt.obfs.conf
                       - 4 ubuntu.obfs.conf
                       - 5 macos.obfs.conf
                       - 6 windows.obfs.conf
                       - 7 ios.obfs.conf
                       - 8 ipados.obfs.conf
                       - 9 android.obfs.conf
  -r, --remove       Remove "amneziawg-dkms and amneziawg-tools"
EOF
    exit 0
}

function main() {
    distribution
    kernel
    root
    awg_tools_status

    if [ "$#" -eq 0 ]; then
        help
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                help
                ;;
            -i|--install)
                install_awg_dkms_and_awg_tools
                ;;
            -g|--generate)
                generate_awg_ifs
                ;;
            -G|--generate-all)
                generate_all_clients_awg_ifs
                ;;
            -r|--remove)
                remove
                ;;
            *)
                echo "ERROR: Invalid option \"$1\"!"
                exit 1
                ;;
        esac
        shift
    done
}

main "$@"
