#!/bin/bash
# Copyright 1999-2003 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$

source /etc/init.d/functions.sh

ebegin "Caching service dependencies"

if [ ! -d "${svcdir}" ]
then
	if ! mkdir -p -m 0755 "${svcdir}" 2>/dev/null
	then
		eerror " Could not create needed directory '${svcdir}'!"
	fi
fi

for x in ${svcdir} softscripts snapshot options started
do
	if [ ! -d "${x}" ]
	then
		if ! mkdir -p -m 0755 "${svcdir}/${x}" 2>/dev/null
		then
			eerror " Could not create needed directory '${svcdir}/${x}'!"
		fi
	fi
done

# Clean out the non volitile directories ...
rm -rf ${svcdir}/dep{cache,tree} ${svcdir}/{broken,snapshot}/*

retval=0
SVCDIR="${svcdir}"
DEPTYPES="${deptypes}"
ORDTYPES="${ordtypes}"

export SVCDIR DEPTYPES ORDTYPES

cd /etc/init.d

/bin/gawk \
	-f /lib/rcscripts/awk/functions.awk \
	-f /lib/rcscripts/awk/cachedepends.awk || \
	retval=1

bash "${svcdir}/depcache" | \
\
/bin/gawk \
	-f /lib/rcscripts/awk/functions.awk \
	-f /lib/rcscripts/awk/gendepends.awk || \
	retval=1

#eend ${retval} "Failed to cache service dependencies"

exit ${retval}


# vim:ts=4
