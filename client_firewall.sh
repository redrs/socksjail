#!/bin/sh

### Firewall off this host to stop any leaks when using a proxy.
### Safely proxy all traffic with SSH's socks4 proxy with something like:
### ssh -D8080 -f -C -q -N -o "VerifyHostKeyDNS no" -p 2222 -i /media/crypt/sshkey user@192.168.100.50

PROXY_SERVER_IP="192.168.100.50"	# IP to restrict traffic to/from
PROXY_SERVER_PORT="2222"			# only connect to this port
INTERFACE="eth0"					# interface of outgoing
PROXYUSERS="root someuser"			# local user accounts who can use this proxy
PROXYPORT="8080"					# local socks proxy port

### Do you SSH into this host?
HOSTSSH="Y"							# Y/N to run these rules
HOSTIF="eth1"						# listening interface
HOSTIP="192.168.10.10"				# ssh listening IP
HOSTPORT="22"						# ssh listening port

### Change DNS settings
CHANGEDNS="Y"						# change the resolv.conf to DNS below
DNS="127.0.0.1"						# nameserver
DNSLOCK="N"							# If Y set resolv.conf as immutable

### bins
IFCONFIG=/sbin/ifconfig
IPTABLES=/sbin/iptables
IP6TABLES=/sbin/ip6tables

##########################################################################################

### Change resolv.conf
if [ $CHANGEDNS  = "Y" ]; then
		echo "nameserver $DNS" > /etc/resolv.conf
fi
if [ $DNSLOCK  = "Y" ]; then
		chattr +i /etc/resolv.conf
fi

### flush existing rules and set chain policy setting to DROP
$IPTABLES -F
$IPTABLES -F -t nat
$IPTABLES -X
$IPTABLES -P INPUT DROP
$IPTABLES -P OUTPUT DROP
$IPTABLES -P FORWARD DROP

### just drop ipv6
$IP6TABLES -P INPUT DROP
$IP6TABLES -P OUTPUT DROP
$IP6TABLES -P FORWARD DROP

### IP Stack
# Enable IP spoofing protection
echo 1 > /proc/sys/net/ipv4/conf/all/rp_filter
# syncookies on
echo 1 > /proc/sys/net/ipv4/tcp_syncookies
# log martion packets:
echo 1 > /proc/sys/net/ipv4/conf/all/log_martians
# Don't accept or send ICMP redirects.
echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/bootp_relay
# no ip forwarding (not a router)
echo 0 > /proc/sys/net/ipv4/ip_forward
# icmp disabled
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_all
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts
echo 1 > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses
# Don't log invalid responses to broadcast frames, they just clutter the logs.
echo 1 > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses
# Disable proxy_arp.
echo 0 > /proc/sys/net/ipv4/conf/all/proxy_arp

# If you are SSHing into the machine that you want to FW off to proxy only
if [ $HOSTSSH  = "Y" ]; then
	$IPTABLES -A INPUT -i $HOSTIF -p tcp -m tcp --dport $HOSTPORT -d $HOSTIP -m state --state NEW,ESTABLISHED  -j ACCEPT
	$IPTABLES -A OUTPUT -p tcp --sport $HOSTPORT -s $HOSTIP -m state --state ESTABLISHED -j ACCEPT
fi

# the local users who can use the tunnel 
for usertraffic in $PROXYUSERS
do
	$IPTABLES -A OUTPUT -o lo -p tcp --dport $PROXYPORT --match owner --gid-owner $usertraffic -j ACCEPT
done
$IPTABLES -A OUTPUT -o lo -p tcp --dport $PROXYPORT -j LOG --log-prefix "BAD PROXY USER " --log-uid -m limit --limit 1/s --limit-burst 5 
$IPTABLES -A OUTPUT -o lo -p tcp --dport $PROXYPORT -j DROP

# localhost
$IPTABLES -A INPUT -i lo -j ACCEPT
$IPTABLES -A OUTPUT -o lo -j ACCEPT

# let established proxy server connection back in
$IPTABLES -A INPUT -i $INTERFACE -p tcp -s $PROXY_SERVER_IP --sport $PROXY_SERVER_PORT -m state --state ESTABLISHED -j ACCEPT

# drop all broadcast traffic without logging
INTERFACES=`$IFCONFIG | cut -c-10 | tr -d ' ' | grep -v lo | sed 's/\n/ /g' |  tr -s '\n'`
for theinterface in $INTERFACES
do
        BROADCAST=`$IFCONFIG $theinterface | grep Bcast | cut -d ":" -f3 | sed 's/ .*//'`
        $IPTABLES -A INPUT -d $BROADCAST -j DROP
done

# drop broadcast + multicast traffic (if we have xt_pkttype support in kernel)
$IPTABLES -A INPUT -m pkttype --pkt-type broadcast -j DROP
$IPTABLES -A INPUT -m pkttype --pkt-type multicast -j DROP

# log + drop incoming scans
$IPTABLES -A INPUT -j LOG --log-prefix "INCOMING! " --log-ip-options --log-tcp-options -m limit --limit 5/s --limit-burst 20
$IPTABLES -A INPUT -j DROP

# outgoing to proxy server
$IPTABLES -A OUTPUT -p tcp -d $PROXY_SERVER_IP --dport $PROXY_SERVER_PORT -m state --state NEW,ESTABLISHED -j ACCEPT

# Log + drop all other outgoing traffic
$IPTABLES -A OUTPUT -j LOG --log-prefix "LEAK " --log-uid -m limit --limit 1/s --limit-burst 5
$IPTABLES -A OUTPUT -j DROP

logger "iptables FW to proxy"
exit