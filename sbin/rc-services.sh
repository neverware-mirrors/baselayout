# Copyright 1999-2003 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# Author: Martin Schlemmer <azarah@gentoo.org>
# $Header$

# RC Dependency and misc service functions


RC_GOT_SERVICES="yes"

[ "${RC_GOT_FUNCTIONS}" != "yes" ] && source /sbin/functions.sh
[ "${RC_GOT_DEPTREE_INFO}" != "yes" -a -f "${svcdir}/deptree" ] \
	&& source "${svcdir}/deptree"

if [ "${RC_GOT_DEPTREE_INFO}" != "yes" ]
then
	eerror "Dependency info is missing!  Please run"
	echo
	eerror "  # /sbin/depscan.sh"
	echo
	eerror "to fix this."
fi


#####################
# Internal variables
#####################

# The name of the service whose dependency info we currently have
rc_name=
# The index of the service whose dependency info we currently have
rc_index=
# Our dependency types ...
rc_ineed=
rc_needsme=
rc_iuse=
rc_usesme=
rc_ibefore=
rc_iafter=
rc_broken=
rc_parallel=

############
# Functions
############

# bool get_dep_info(service)
#
#   Set the Dependency variables to contain data for 'service'
#
get_dep_info() {
	local x=1
	local myservice="$1"
	
	[ -z "$1" ] && return 1

	# We already have the right stuff ...
	[ "$1" = "${rc_name}" ] && return 0

	while [ "${x}" -le "${RC_DEPEND_TREE[0]}" ]
	do
		if [ "$1" = "${RC_DEPEND_TREE[$((${x} * ${rc_index_scale}))]}" ]
		then
			rc_index=$((${x} * ${rc_index_scale}))
			rc_name="${RC_DEPEND_TREE[${rc_index}]}"
			rc_ineed="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_ineed}))]}"
			rc_needsme="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_needsme}))]}"
			rc_iuse="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_iuse}))]}"
			rc_usesme="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_usesme}))]}"
			rc_ibefore="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_ibefore}))]}"
			rc_iafter="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_iafter}))]}"
			rc_broken="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_broken}))]}"
			rc_parallel="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_parallel}))]}"
			return 0
		fi

		let "x += 1"
	done

	return 1
}

# string check_dependency(deptype, service1)
#
#   List all the services that depend on 'service1' of dependency
#   type 'deptype'
#
# bool check_dependency(deptype, -t, service1, service2)
#
#   Returns true if 'service2' is a dependency of type 'deptype'
#   of 'service1'
#
check_dependency() {
	local x=

	[ -z "$1" -o -z "$2" ] && return 1
	
	# Set the dependency variables to relate to 'service1'
	if [ "$2" = "-t" ]
	then
		[ -z "$3" -o -z "$4" ] && return 1

		get_dep_info "$3" &>/dev/null || {
			eerror "Could not get dependency info for \"$3\"!" > /dev/stderr
			eerror "Please run:" > /dev/stderr
			echo > /dev/stderr
			eerror "  # /sbin/depscan.sh" > /dev/stderr
			echo > /dev/stderr
			eerror "to try and fix this." > /dev/stderr
			return 1
		}
	else
		get_dep_info "$2" &>/dev/null || {
			eerror "Could not get dependency info for \"$2\"!" > /dev/stderr
			eerror "Please run:" > /dev/stderr
			echo > /dev/stderr
			eerror "  # /sbin/depscan.sh" > /dev/stderr
			echo > /dev/stderr
			eerror "to fix this." > /dev/stderr
			return 1
		}
	fi

	# Do we have valid info for 'deptype' ?
	[ -z "$(eval echo \${rc_$1})" ] && return 1

	if [ "$2" = "-t" -a -n "$4" ]
	then
		# Check if 'service1' have 'deptype' dependency on 'service2'
		for x in $(eval echo \${rc_$1})
		do
			[ "${x}" = "$4" ] && return 0
		done
	else
		# Just list all services that 'service1' have 'deptype' dependency on.
		eval echo "\${rc_$1}"

		return 0
	fi

	return 1
}

# Same as for check_dependency, except 'deptype' is set to
# 'ineed'.  It will return all the services 'service1' NEED's.
ineed() {
	[ -z "$1" ] && return 1
	
	check_dependency ineed $*
	
	return $?
}

# Same as for check_dependency, except 'deptype' is set to
# 'needsme'.  It will return all the services that NEED 'service1'.
needsme() {
	[ -z "$1" ] && return 1
	
	check_dependency needsme $*

	return $?
}

# Same as for check_dependency, except 'deptype' is set to
# 'iuse'.  It will return all the services 'service1' USE's.
iuse() {
	[ -z "$1" ] && return 1
	
	check_dependency iuse $*

	return $?
}

# Same as for check_dependency, except 'deptype' is set to
# 'usesme'.  It will return all the services that USE 'service1'.
usesme() {
	[ -z "$1" ] && return 1
	
	check_dependency usesme $*

	return $?
}

# Same as for check_dependency, except 'deptype' is set to
# 'ibefore'.  It will return all the services that are started
# *after* 'service1' (iow, it will start 'service1' before the
# list of services returned).
ibefore() {
	[ -z "$1" ] && return 1
	
	check_dependency ibefore $*

	return $?
}

# Same as for check_dependency, except 'deptype' is set to
# 'iafter'.  It will return all the services that are started
# *before* 'service1' (iow, it will start 'service1' after the
# list of services returned).
iafter() {
	[ -z "$1" ] && return 1
	
	check_dependency iafter $*

	return $?
}

# Same as for check_dependency, except 'deptype' is set to
# 'broken'.  It will return all the services that 'service1'
# NEED, but are not present.
broken() {
	[ -z "$1" ] && return 1

	check_dependency broken $*
	
	return $?
}

# bool iparallel(service)
#
#   Returns true if the service can be started in parallel.
#
iparallel() {
	[ -z "$1" ] && return 1

	if check_dependency parallel -t "$1" "no"
	then
		return 1
	fi

	return 0
}

# bool is_fake_service(service, runlevel)
#
#   Returns ture if 'service' is a fake service in 'runlevel'.
#
is_fake_service() {
	local x=
	local fake_services=

	[ -z "$1" -o -z "$2" ] && return 1

	if [ "$2" != "${BOOTLEVEL}" -a \
	     -e "/etc/runlevels/${BOOTLEVEL}/.fake" ]
	then
		fake_services="$(< /etc/runlevels/${BOOTLEVEL}/.fake)"
	fi

	if [ -e "/etc/runlevels/$2/.fake" ]
	then
		fake_services="${fake_services} $(< /etc/runlevels/$2/.fake)"
	fi

	for x in ${fake_services}
	do
		if [ "$1" = "${x##*/}" ]
		then
			return 0
		fi
	done

	return 1
}

# bool in_runlevel(service, runlevel)
#
#   Returns true if 'service' is in runlevel 'runlevel'.
#
in_runlevel() {
	[ -z "$1" -o -z "$2" ] && return 1

	[ -L "/etc/runlevels/$2/$1" ] && return 0

	return 1
}

# bool is_runlevel_start()
#
#   Returns true if it is a runlevel change, and we are busy
#   starting services.
#
is_runlevel_start() {
	[ -d "${svcdir}/softscripts.old" ] && return 0

	return 1
}

# bool is_runlevel_stop()
#
#   Returns true if it is a runlevel change, and we are busy
#   stopping services.
#
is_runlevel_stop() {
	[ -d "${svcdir}/softscripts.new" ] && return 0

	return 1
}

# int start_service(service)
#
#   Start 'service' if it is not already running.
#
start_service() {
	[ -z "$1" ] && return 1
	
	if ! service_started "$1"
	then
		if is_fake_service "$1" "${SOFTLEVEL}"
		then
			mark_service_started "$1"
		else
			(. /sbin/runscript.sh "/etc/init.d/$1" start)
		
			return $?
		fi
	fi

	return 0
}

# int stop_service(service)
#
#   Stop 'service' if it is not already running.
#
stop_service() {
	[ -z "$1" ] && return 1

	if service_started "$1" 
	then
		if is_runlevel_stop
		then
			if is_fake_service "$1" "${OLDSOFTLEVEL}"
			then
				mark_service_stopped "$1"

				return 0
			fi
		else
			if is_fake_service "$1" "${SOFTLEVEL}"
			then
				mark_service_stopped "$1"

				return 0
			fi
		fi

		(. /sbin/runscript.sh "/etc/init.d/$1" stop)
	
		return $?
	fi

	return 0
}

# bool mark_service_started(service)
#
#   Mark 'service' as started.
#
mark_service_started() {
	[ -z "$1" ] && return 1

	ln -snf "/etc/init.d/$1" "${svcdir}/started/$1"

	return $?
}

# bool mark_service_stopped(service)
#
#   Mark 'service' as stopped.
#
mark_service_stopped() {
	[ -z "$1" ] && return 1

	rm -f "${svcdir}/started/$1"

	return $?
}

# bool service_started(service)
#
#   Returns true if 'service' is started
#
service_started() {
	[ -z "$1" ] && return 1

	if [ -L "${svcdir}/started/$1" ]
	then
		if [ ! -e "${svcdir}/started/$1" ]
		then
			rm -f "${svcdir}/started/$1"
			
			return 1
		fi
		return 0
	fi

	return 1
}

# bool mark_service_failed(service)
#
#   Mark service as failed for current runlevel.  Note that
#   this is only valid on runlevel change ...
#
mark_service_failed() {
	[ -z "$1" ] && return 1

	if [ -d "${svcdir}/failed" ]
	then
		ln -snf "/etc/init.d/$1" "${svcdir}/failed/$1"
		return $?
	fi

	return 1
}

# bool service_failed(service)
#
#   Return true if 'service' have failed during this runlevel.
#
service_failed() {
	[ -z "$1" ] && return 1
	
	if [ -L "${svcdir}/failed/$1" ]
	then
		return 0
	fi

	return 1
}

# bool net_service(service)
#
#   Returns true if 'service' is a service controlling a network interface
#
net_service() {
	[ -z "$1" ] && return 1

	if [ "${1%%.*}" = "net" -a "${1##*.}" != "$1" ]
	then
		return 0
	fi

	return 0
}

# void schedule_service_startup(service)
#
#   Schedule 'service' for startup, in parallel if possible.
#
schedule_service_startup() {
	local count=0
	local current_job=

	if [ "${RC_PARALLEL_STARTUP}" = "yes" ]
	then
		set -m +b

		if [ "$(jobs | grep -c "Running")" -gt 0 ]
		then
			if [ "$(jobs | grep -c "Running")" -eq 1 ]
			then
				if [ -n "$(jobs)" ]
				then
					current_job="$(jobs | awk '/Running/ { print $4}')"
				fi
				
				# Wait if we cannot start this service with the already running
				# one (running one might start this one ...).
				query_before "$1" "${current_job}" && wait

			elif [ "$(jobs | grep -c "Running")" -ge 2 ]
			then
				count="$(jobs | grep -c "Running")"

				# Wait until we have only one service running
				while [ "${count}" -gt 1 ]
				do
					count="$(jobs | grep -c "Running")"
				done

				if [ -n "$(jobs)" ]
				then
					current_job="$(jobs | awk '/Running/ { print $4}')"
				fi

				# Wait if we cannot start this service with the already running
				# one (running one might start this one ...).
				query_before "$1" "${current_job}" && wait
			fi
		fi

		if iparallel "$1"
		then
			eval start_service "$1" \&
		else
			# Do not start with any service running if we cannot start
			# this service in parallel ...
#			wait
			
			start_service "$1"
		fi
	else
		start_service "$1"
	fi

	# We do not need to check the return value here, as svc_{start,stop}() do
	# their own error handling ...
	return 0
}

# bool dependon(service1, service2)
#
#   Does service1 depend (NEED or USE) on service2 ?
#
dependon() {
	[ -z "$1" -o -z "$2" ] && return 1
	
	if ineed -t "$1" "$2" || iuse -t "$1" "$2"
	then
		return 0
	fi

	return 1
}

# string valid_iuse(service)
#
#   This will only give the valid use's for the service
#   (they must be in the boot or current runlevel)
#
valid_iuse() {
	local x=
	local y=

	for x in $(iuse "$1")
	do
		if [ -e "/etc/runlevels/${BOOTLEVEL}/${x}" -o \
		     -e "/etc/runlevels/${mylevel}/${x}" -o \
			 ${x} = "net" ]
		then
			echo "${x}"
		fi
	done

	return 0
}

# string valid_iafter(service)
#
#   Valid services for current or boot rc level that should start
#   before 'service'
#
valid_iafter() {
	local x=
	
	for x in $(iafter "$1")
	do
		if [ -e "/etc/runlevels/${BOOTLEVEL}/${x}" -o \
		     -e "/etc/runlevels/${mylevel}/${x}" -o \
			 ${x} = "net" ]
		then
			echo "${x}"
		fi
	done

	return 0
}

# void trace_depend(deptype, service, deplist)
#
#   Trace the dependency tree of 'service' for type 'deptype', and
#   modify 'deplist' with the info.
#
trace_depend() {
	local x=
	local y=
	local add=

	[ -z "$1" -o -z "$2" -o -z "$3" ] && return 1

	# Build the list of services that 'deptype' on this one
	for x in "$("$1" "$2")"
	do
		add="yes"
		
		for y in $(eval echo "\${$3}")
		do
			[ "${x}" = "${y}" ] && add="no"
		done

		[ "${add}" = "yes" ] && eval $(echo "$3=\"\${$3} ${x}\"")
		
		# Recurse to build a complete list ...
		trace_depend "$1" "${x}" "$3"
	done

	return 0
}

# string list_depend_trace(deptype)
#
#   Return resulting list of services for a trace of
#   type 'deptype' for $myservice
#
list_depend_trace() {
	local x=
	local list=

	[ -z "$1" ] && return 1
	
	trace_depend "$1" "${myservice}" "list"

	for x in ${list}
	do
		echo "${x}"
	done

	return 0
}

# bool query_before(service1, service2)
#
#   Return true if 'service2' should be started *before*
#   service1.
#
query_before() {
	local x=
	local list=
	local netservice="no"

	[ -z "$1" -o -z "$2" ] && return 1

	trace_depend "ineed" "$1" "list"

	for x in $1 ${list}
	do
		trace_depend "iuse" "${x}" "list"
	done

	for x in $1 ${list}
	do
		trace_depend "iafter" "${x}" "list"
	done

	net_service "$2" && netservice="yes"
	
	for x in ${list}
	do
		[ "${x}" = "$2" ] && return 0

		# Also match "net" if this is a network service ...
		[ "${netservice}" = "yes" -a "${x}" = "net" ] && return 0
	done

	return 1
}

# bool query_after(service1, service2)
#
#   Return true if 'service2' should be started *after*
#   service1.
#
query_after() {
	local x=
	local list=
	local netservice="no"

	[ -z "$1" -o -z "$2" ] && return 1

	trace_depend "needsme" "$1" "list"

	for x in $1 ${list}
	do
		trace_depend "usesme" "${x}" "list"
	done

	for x in $1 ${list}
	do
		trace_depend "ibefore" "${x}" "list"
	done

	net_service "$2" && netservice="yes"

	for x in ${list}
	do
		[ "${x}" = "$2" ] && return 0

		# Also match "net" if this is a network service ...
		[ "${netservice}" = "yes" -a "${x}" = "net" ] && return 0
	done

	return 1
}


# vim:ts=4
