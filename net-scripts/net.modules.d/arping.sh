# Copyright (c) 2004-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# void arping_depend(void)
#
# Sets up the dependancies for the module
arping_depend() {
	functions interface_exists interface_up
}

# bool arping_check_installed(void)
#
# Returns 0 if arping or arping2 is installed, otherwise 1
arping_check_installed() {
	[[ -x /sbin/arping || -x /usr/sbin/arping2 ]] && return 0
	if ${1:-false}; then
		eerror "For arping support emerge net-misc/iputils or net-analyzer/arping"
	fi
	return 1
}

# bool arping_address_exists(char *interface, char *address)
#
# Returns 0 if the address on the interface responds to an arping
# 1 if not - packets defaults to 1
# If neither arping (net-misc/iputils) or arping2 (net-analyzer/arping)
# is installed then we return 1
arping_address_exists() {
	local iface="$1" address="${2%%/*}" i

	# We only handle IPv4 addresses
	[[ ${address} != *.*.*.* ]] && return 1

	# 0.0.0.0 isn't a valid address - and some lusers have configured this
	[[ ${address} == "0.0.0.0" || ${address} == "0" ]] && return 1

	# We need to bring the interface up to test
	interface_up "${iface}"

	if [[ -x /sbin/arping ]] ; then
		/sbin/arping -q -c 2 -w 3 -D -f -I "${iface}" "${address}" \
		&>/dev/null || return 0
	elif [[ -x /usr/sbin/arping2 ]] ; then
		for (( i=0; i<3; i++ )) ; do
			/usr/sbin/arping2 -0 -c 1 -i "${iface}" "${address}" \
			&>/dev/null && return 0
		done
	fi
	return 1
}

# bool arping_start(char *iface)
#
# arpings a list of gateways
# If one is foung then apply it's configuration
arping_start() {
	local iface="$1" gateways x conf i

	interface_exists "${iface}" true || return 1

	einfo "Pinging gateways on ${iface} for configuration"

	gateways="gateways_${ifvar}[@]"
	if [[ -z ${!gateways} ]] ; then
		eerror "No gateways have been defined (gateways_${ifvar}=\"...\")"
		return 1
	fi

	eindent
	
	for x in ${!gateways}; do
		vebegin "${x}"
		if arping_address_exists "${iface}" "${x}" ; then
			for i in ${x//./ } ; do
				if [[ ${#i} == "2" ]] ; then
					conf="${conf}0${i}"
				elif [[ ${#i} == "1" ]] ; then
					conf="${conf}00${i}"
				else
					conf="${conf}${i}"
				fi
			done
			veend 0
			eoutdent
			veinfo "Configuring ${iface} for ${x}"
			configure_variables "${iface}" "${conf}"

			# Call the system module as we've aleady passed it by ....
			# And it *has* to be pre_start for other things to work correctly
			system_pre_start "${iface}"
			
			t="config_${ifvar}[@]"
			config=( "${!t}" )
			t="fallback_config_${ifvar}[@]"
			fallback_config=( "${!t}" )
			t="fallback_route_${ifvar}[@]"
			fallback_route=( "${!t}" )
			config_counter=-1
			return 0
		fi
		veend 1
	done

	eoutdent
	return 1
}

# vim: set ts=4 :
