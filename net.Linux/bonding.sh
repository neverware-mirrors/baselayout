# Copyright 2004-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# void bonding_depend(void)
#
# Sets up the dependancies for the module
bonding_depend() {
	before interface macchanger
}

# void bonding_expose(void)
#
# Expose variables that can be configured
bonding_expose() {
	variables slaves
}

# bool bonding_check_installed(void)
#
# Returns 0 if ifenslave is installed, otherwise 1
bonding_check_installed() {
	[[ -x /sbin/ifenslave ]] && return 0
	${1:-false} && eerror $"For link aggregation (bonding) support, emerge net-misc/ifenslave"
	return 1
}

# bonding_exists(char *interface)
#
# Returns 0 if we are a bonded interface, otherwise 1
bonding_exists() {
	[[ -f "/proc/net/bonding/$1" ]]
}

# bool bonding_post_start(char *iface)
#
# Bonds the interface
bonding_pre_start() {
	local iface="$1" s= ifvar=$(bash_variable "$1")
	local -a slaves=()

	slaves="slaves_${ifvar}[@]"
	[[ -z ${!slaves} ]] && return 0
	slaves=( "${!slaves}" )

	# Support space seperated slaves
	[[ ${#slaves[@]} == 1 ]] && slaves=( ${slaves} )

	interface_exists "${iface}" true || return 1

	if ! bonding_exists "${iface}" ; then
		eerror "${iface}" $"is not capable of bonding"
		return 1
	fi

	ebegin $"Adding slaves to" "${iface}"
	eindent
	einfo "${slaves[@]}"

	# Check that our slaves exist
	for s in "${slaves[@]}" ; do
		interface_exists "${s}" true || return 1
	done

	# Must force the slaves to a particular state before adding them
	for s in "${slaves[@]}" ; do
		interface_del_addresses "${s}"
		interface_up "${s}"
	done

	# now force the master to up
	interface_up "${iface}"

	# finally add in slaves
	eoutdent
	/sbin/ifenslave "${iface}" ${slaves[@]} >/dev/null
	eend $?

	return 0 #important
}

# bool bonding_stop(void)
# Unbonds bonded interfaces
#
# Always returns 0 (true) 
bonding_stop() {
	local iface="$1" slaves= s=

	# return silently if this is not a bonding interface
	! bonding_exists "${iface}" && return 0

	# don't trust the config, get the active list instead
	slaves=$( \
		sed -n -e 's/^Slave Interface: //p' "/proc/net/bonding/${iface}" \
		| tr '\n' ' ' \
	)
	[[ -z ${slaves} ]] && return 0

	# remove all slaves
	ebegin $"Removing slaves from" "${iface}"
	eindent
	einfo "${slaves}"
	eoutdent
	/sbin/ifenslave -d "${iface}" ${slaves}

	# reset all slaves
	for s in ${slaves}; do
		if interface_exists "${s}" ; then
			interface_del_addresses "${s}"
			interface_down "${s}"
		fi
	done

	eend 0
	return 0
}

# vim: set ts=4 :