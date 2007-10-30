# Copyright 2004-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# Fix any potential localisation problems
# Note that LC_ALL trumps LC_anything_else according to locale(7)
ifconfig() {
	LC_ALL=C /sbin/ifconfig "$@"
}

ifconfig_tunnel() {
	LC_ALL=C /sbin/iptunnel "$@"
}

route() {
	LC_ALL=C /sbin/route "$@"
}

# void ifconfig_depend(void)
#
# Sets up the dependancies for the module
ifconfig_depend() {
	provide interface
}

# void ifconfig_expose(void)
#
# Expose variables that can be configured
ifconfig_expose() {
	variables config routes fallback metric ifconfig \
		ifconfig_fallback routes inet6 iface alias broadcast netmask
}

# bool ifconfig_check_installed(void)
#
# Returns 1 if ifconfig is installed, otherwise 0
ifconfig_check_installed() {
	[[ -x /sbin/ifconfig ]] && return 0
	${1:-false} && eerror "For ifconfig support, emerge sys-apps/net-tools"
	return 1
}

# bool ifconfig_exists(char *interface, bool report)
#
# Returns 1 if the interface exists, otherwise 0
ifconfig_exists() {
	local e=$(ifconfig -a | grep -o "^$1") report="${2:-false}"
	[[ -n ${e} ]] && return 0

	if ${report} ; then
		eerror "network interface $1 does not exist"
		eerror "Please verify hardware or kernel module (driver)"
	fi

	return 1
}

# char* cidr2netmask(int cidr)
#
# Returns the netmask of a given CIDR
cidr2netmask() {
	local cidr="$1" netmask="" done=0 i sum=0 cur=128
	local octets= frac=

	(( octets=cidr/8 ))
	(( frac=cidr%8 ))
	while [[ octets -gt 0 ]] ; do
		netmask="${netmask}.255"
		(( octets-- ))
		(( done++ ))
	done

	if [[ ${done} -lt 4 ]] ; then
		for (( i=0; i<${frac}; i++ )); do
			(( sum+=cur ))
			(( cur/=2 ))
		done
		netmask="${netmask}.${sum}"
		(( done++ ))

		while [[ ${done} -lt 4 ]] ; do
			netmask="${netmask}.0"
			(( done++ ))
		done
	fi

	echo "${netmask:1}"
}

# void ifconfig_up(char *iface)
#
# provides a generic interface for bringing interfaces up
ifconfig_up() {
	ifconfig "$1" up
}

# void ifconfig_down(char *iface)
#
# provides a generic interface for bringing interfaces down
ifconfig_down() {
	ifconfig "$1" down
}

# bool ifconfig_is_up(char *iface, bool withaddress)
#
# Returns 0 if the interface is up, otherwise 1
# If withaddress is true then the interface has to have an IPv4 address
# assigned as well
ifconfig_is_up() {
	local check="\<UP\>" addr="${2:-false}"
	${addr} && check="\<inet addr:.*${check}"
	ifconfig "$1" | tr '\n' ' ' | grep -Eq "${check}" && return 0
	return 1
}

# void ifconfig_set_flag(char *iface, char *flag, bool enabled)
#
# Sets or disables the interface flag 
ifconfig_set_flag() {
	local iface="$1" flag="$2" enable="$3"
	${enable} || flag="-${flag}"
	ifconfig "${iface}" "${flag}"
}

# void ifconfig_get_address(char *interface)
#
# Fetch the address retrieved by DHCP.  If successful, echoes the
# address on stdout, otherwise echoes nothing.
ifconfig_get_address() {
	local -a x=( $( ifconfig "$1" \
	| sed -n -e 's/.*inet addr:\([^ ]*\).*Mask:\([^ ]*\).*/\1 \2/p' ) )
	x[1]=$(netmask2cidr "${x[1]}")
	[[ -n ${x[0]} ]] && echo "${x[0]}/${x[1]}"
}

# bool ifconfig_is_ethernet(char *interface)
#
# Return 0 if the link is ethernet, otherwise 1.
ifconfig_is_ethernet() {
	ifconfig "$1" | grep -q "^$1[[:space:]]*Link encap:Ethernet[[:space:]]"
}

# void ifconfig_get_mac_address(char *interface)
#
# Fetch the mac address assingned to the network card
ifconfig_get_mac_address() {
	local mac=$(ifconfig "$1" | sed -n -e \
		's/.*HWaddr[ \t]*\<\(..:..:..:..:..:..\)\>.*/\U\1/p')
	[[ ${mac} != '00:00:00:00:00:00' \
	&& ${mac} != '44:44:44:44:44:44' \
	&& ${mac} != 'FF:FF:FF:FF:FF:FF' ]] \
		&& echo "${mac}"
}

# void ifconfig_set_mac_address(char *interface, char *mac)
#
# Assigned the mac address to the network card
ifconfig_set_mac_address() {
	ifconfig "$1" hw ether "$2"
}

# int ifconfig_set_name(char *interface, char *new_name)
#
# Renames the interface
# This will not work if the interface is setup!
ifconfig_set_name() {
	[[ -z $2 ]] && return 1
	local current="$1" new="$2"

	local mac=$(ifconfig_get_mac_address "${current}")
	if [[ -z ${mac} ]]; then
		eerror "${iface} does not have a MAC address"
		return 1
	fi

	/sbin/nameif "${new}" "${mac}"
}

# void ifconfig_get_aliases_rev(char *interface)
#
# Fetch the list of aliases for an interface.  
# Outputs a space-separated list on stdout, in reverse order, for
# example "eth0:2 eth0:1"
ifconfig_get_aliases_rev() {
	ifconfig | grep -Eo "^$1:[^ ]+" | sed '1!G;h;$!d'
}

# bool ifconfig_del_addresses(char *interface, bool onlyinet)
#
# Remove addresses from interface.  Returns 0 (true) if there
# were addresses to remove (whether successful or not).  Returns 1
# (false) if there were no addresses to remove.
# If onlyinet is true then we only delete IPv4 / inet addresses
ifconfig_del_addresses() {
	local iface="$1" i= onlyinet="${2:-false}"
	# We don't remove addresses from aliases
	[[ ${iface} == *:* ]] && return 0

	# If the interface doesn't exist, don't try and delete
	ifconfig_exists "${iface}" || return 0

	# iproute2 can add many addresses to an iface unlike ifconfig ...
	# iproute2 added addresses cause problems for ifconfig
	# as we delete an address, a new one appears, so we have to
	# keep polling
	while ifconfig "${iface}" | grep -q -m1 -o 'inet addr:[^ ]*' ; do
		ifconfig "${iface}" 0.0.0.0 || break
	done

	# Remove IPv6 addresses
	if ! ${onlyinet} ; then
		for i in $( ifconfig "${iface}" \
			| sed -n -e 's/^.*inet6 addr: \([^ ]*\) Scope:[^L].*/\1/p' ) ; do
			/sbin/ifconfig "${iface}" inet6 del "${i}"
		done
	fi
	return 0
}

# bool ifconfig_get_old_config(char *iface)
#
# Returns config and config_fallback for the given interface
ifconfig_get_old_config() {
	local iface="$1" ifvar=$(bash_variable "$1") i= inet6=

	config="ifconfig_${ifvar}[@]"
	config=( "${!config}" )
	config_fallback="ifconfig_fallback_${ifvar}[@]"
	config_fallback=( "${!config_fallback}" )
	inet6="inet6_${ifvar}[@]"
	inet6=( "${!inet6}" )

	# BACKWARD COMPATIBILITY: populate the config_IFACE array
	# if iface_IFACE is set (fex. iface_eth0 instead of ifconfig_eth0)
	i="iface_${ifvar}"
	if [[ -n ${!i} && -z ${config} ]]; then
		# Make sure these get evaluated as arrays
		local -a aliases=() broadcasts=() netmasks=()

		# Start with the primary interface
		config=( "${!i}" )

		# ..then add aliases
		aliases="alias_${ifvars}"
		aliases=( ${!aliases} )
		broadcasts="broadcast_${ifvar}"
		broadcasts=( ${!broadcasts} )
		netmasks="netmask_${ifvar}"
		netmasks=( ${!netmasks} )
		for (( i=0; i<${#aliases[@]}; i++ )); do
			config[i+1]="${aliases[i]} ${broadcasts[i]:+broadcast ${broadcasts[i]}} ${netmasks[i]:+netmask ${netmasks[i]}}"
		done
	fi

	# BACKWARD COMPATIBILITY: check for space-separated inet6 addresses
	[[ ${#inet6[@]} == 1 && ${inet6} == *' '* ]] &&  inet6=( ${inet6} )

	# Add inet6 addresses to our config if required
	[[ -n ${inet6} ]] && config=( "${config[@]}" "${inet6[@]}" )

	# BACKWARD COMPATIBILITY: set the default gateway
	if [[ ${gateway} == "${iface}/"* ]]; then
		i="routes_${ifvar}[@]"
		local -a routes=( "${!i}" )
		
		# We don't add the old gateway if one has been set in routes_IFACE
		local gw=true
		for i in "${routes[@]}"; do
			[[ ${i} != *"default gw"* ]] && continue
			gw=false
			break
		done
	
		if ${gw} ; then
			eval "routes_${ifvar}=( \"default gw \${gateway#*/}\" \"\${routes[@]}\" )"
		fi
	fi

	return 0
}

# bool ifconfig_iface_stop(char *interface)
#
# Do final shutdown for an interface or alias.
#
# Returns 0 (true) when successful, non-zero (false) on failure
ifconfig_iface_stop() {
	# If an alias is already down, then "ifconfig eth0:1 down"
	# will try to bring it up with an address of "down" which
	# fails.  Do some double-checking before returning error
	# status
	ifconfig_is_up "$1" || return 0
	ifconfig_down "$1" && return 0

	# It is sometimes impossible to transition an alias from the
	# UP state... particularly if the alias has no address.  So
	# ignore the failure, which should be okay since the entire
	# interface will be shut down eventually.
	[[ $1 == *:* ]] && return 0
	return 1
}

# bool ifconfig_pre_start(char *interface)
#
# Runs any pre_start stuff on our interface - just the MTU atm
# We set MTU twice as it may be needed for DHCP - a dhcp client could
# change it in error, so we set MTU in post start too
ifconfig_pre_start() {
	local iface="$1"

	interface_exists "${iface}" || return 0

	local ifvar=$(bash_variable "$1") mtu=

	# MTU support
	mtu="mtu_${ifvar}"
	[[ -n ${!mtu} ]] && ifconfig "${iface}" mtu "${!mtu}"

	return 0
}


# bool ifconfig_post_start(char *iface)
#
# Bring up iface using ifconfig utilities, called from iface_start
#
# Returns 0 (true) when successful on the primary interface, non-zero
# (false) when the primary interface fails.  Aliases are allowed to
# fail, the routine should still return success to indicate that
# net.eth0 was successful
ifconfig_post_start() {
	local iface="$1" ifvar=$(bash_variable "$1") x= y= metric= mtu=
	local -a routes=()
	metric="metric_${ifvar}"

	ifconfig_exists "${iface}" || return 0
	
	# Make sure interface is marked UP
	ifconfig_up "${iface}"

	# MTU support
	mtu="mtu_${ifvar}"
	[[ -n ${!mtu} ]] && ifconfig "${iface}" mtu "${!mtu}"

	x="routes_${ifvar}[@]"
	routes=( "${!x}" )

	[[ -z ${routes} ]] && return 0

	# Add routes for this interface, might even include default gw
	einfo "Adding routes"
	eindent
	for x in "${routes[@]}"; do
		ebegin "${x}"

		# Support iproute2 style routes
		x="${x//via/gw} "
		x="${x//scope * / }"

		# Support adding IPv6 addresses easily
		if [[ ${x} == *:* ]]; then
			[[ ${x} != *"-A inet6"* ]] && x="-A inet6 ${x}"
			x="${x// -net / }"
		else
			# Work out if we're a host or a net if not told
			if [[ " ${x} " != *" -net "* && " ${x} " != *" -host "* ]] ; then
				y="${x% *}"
				y="${y##* }"
				if [[ ${x} == *" netmask "* ]] ; then
					x="-net ${x}"
				elif [[ ${y} == *.*.*.*/32 ]] ; then
					x="-host ${x}"
				elif [[ ${y} == *.*.*.*/* || ${y} == "default" || ${y} == "0.0.0.0" ]] ; then
					x="-net ${x}"
				else
					# Given the lack of a netmask, we assume a host
					x="-host ${x}"
				fi
			fi
		fi

		# Add a metric if we don't have one
		[[ ${x} != *" metric "* ]] && x="${x} metric ${!metric}"

		route add ${x} dev "${iface}"
		eend $?
	done
	eoutdent

	return 0
}

# bool ifconfig_add_address(char *iface, char *options ...)
#
# Adds the given address to the interface
ifconfig_add_address() {
	local iface="$1" i=0 r= e= real_iface=$(interface_device "$1")

	ifconfig_exists "${real_iface}" true || return 1
	
	# Extract the config
	local -a config=( "$@" )
	config=( ${config[@]:1} )

	if [[ ${config[0]} == *:* ]]; then
		# Support IPv6 - nice and simple
		config[0]="inet6 add ${config[0]}"
	else
		# IPv4 is tricky - ifconfig requires an aliased device
		# for multiple addresses
		if ifconfig "${iface}" | grep -Eq "\<inet addr:.*" ; then
			# Get the last alias made for the interface and add 1 to it
			i=$(ifconfig | sed '1!G;h;$!d' | grep -m 1 -o "^${iface}:[0-9]*" \
				| sed -n -e 's/'"${iface}"'://p')
			i="${i:-0}"
			(( i++ ))
			iface="${iface}:${i}"
		fi

		# ifconfig doesn't like CIDR addresses
		local ip="${config[0]%%/*}" cidr="${config[0]##*/}" netmask=
		if [[ -n ${cidr} && ${cidr} != "${ip}" ]]; then
			netmask=$(cidr2netmask "${cidr}")
			config[0]="${ip} netmask ${netmask}"
		fi	

		# Support iproute2 style config where possible
		r="${config[@]}"
		config=( ${r//brd +/} )
		config=( "${config[@]//brd/broadcast}" )
		config=( "${config[@]//peer/pointopoint}" )
	fi

	# Some kernels like to apply lo with an address when they are brought up
	if [[ ${config[@]} == "127.0.0.1 netmask 255.0.0.0 broadcast 127.255.255.255" ]]; then
		if is_loopback "${real_iface}" ; then
			ifconfig "${real_iface}" ${config[@]}
			return 0
		fi
	fi

	ifconfig "${iface}" ${config[@]}
}

# vim: set ts=4 :
