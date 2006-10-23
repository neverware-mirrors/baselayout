# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

function print_start() {
	print ". /sbin/functions.sh" >> TMPCACHE
	print "" >> TMPCACHE
	print "need() {" >> TMPCACHE
	print "	echo \"NEED $*\"; return 0" >> TMPCACHE
	print "}" >> TMPCACHE
	print "" >> TMPCACHE
	print "use() {" >> TMPCACHE
	print "	echo \"USE $*\"; return 0" >> TMPCACHE
	print "}" >> TMPCACHE
	print "" >> TMPCACHE
	print "before() {" >> TMPCACHE
	print "	echo \"BEFORE $*\"; return 0" >> TMPCACHE
	print "}" >> TMPCACHE
	print "" >> TMPCACHE
	print "after() {" >> TMPCACHE
	print "	echo \"AFTER $*\"; return 0" >> TMPCACHE
	print "}" >> TMPCACHE
	print "" >> TMPCACHE
	print "provide() {" >> TMPCACHE
	print "	echo \"PROVIDE $*\"; return 0" >> TMPCACHE
	print "}" >> TMPCACHE
	print "" >> TMPCACHE
}

function print_header1() {
	print "#*** " MYFILENAME " ***" >> TMPCACHE
	print "" >> TMPCACHE
	print "SVCNAME=\"" MYFILENAME "\"" >> TMPCACHE
	print "SVCNAME=\"${SVCNAME##*/}\"" >> TMPCACHE

	# Support deprected myservice variable
	print "myservice=\"${SVCNAME}\"" >> TMPCACHE
	
	print "echo \"RCSCRIPT ${SVCNAME}\"" >> TMPCACHE
	print "" >> TMPCACHE
}

function print_header2() {
	print "(" >> TMPCACHE
	print "  # Get settings for rc-script ..." >> TMPCACHE
	print "" >> TMPCACHE
	print "  [ -e \"/etc/conf.d/${SVCNAME%%.*}\" ]    && \\" >> TMPCACHE
	print "  [ \"${SVCNAME%%.*}\" != \"${SVCNAME}\" ] && . \"/etc/conf.d/${SVCNAME%%.*}\"" >> TMPCACHE
	print "" >> TMPCACHE
	print "  [ -e \"/etc/conf.d/${SVCNAME}\" ]        && . \"/etc/conf.d/${SVCNAME}\"" >> TMPCACHE
	print "" >> TMPCACHE
	print "  [ -e /etc/rc.conf ]                      && . /etc/rc.conf" >> TMPCACHE
	print "" >> TMPCACHE
	print "  depend() {" >> TMPCACHE
	print "    return 0" >> TMPCACHE
	print "  }" >> TMPCACHE
	print "" >> TMPCACHE
}

function print_end() {
	print "" >> TMPCACHE
	print "  depend" >> TMPCACHE

	# Support user defined RC_NEED, RC_USE, RC_AFTER, RC_BEFORE AND RC_PROVIDE
	print "" >> TMPCACHE
	print "  for x in ${RC_NEED} ; do" >> TMPCACHE
	print "    need \"${x}\"" >> TMPCACHE
	print "  done" >> TMPCACHE
	print "  for x in ${RC_USE} ; do" >> TMPCACHE
	print "    use \"${x}\"" >> TMPCACHE
	print "  done" >> TMPCACHE
	print "  for x in ${RC_AFTER} ; do" >> TMPCACHE
	print "    after \"${x}\"" >> TMPCACHE
	print "  done" >> TMPCACHE
	print "  for x in ${RC_BEFORE} ; do" >> TMPCACHE
	print "    before \"${x}\"" >> TMPCACHE
	print "  done" >> TMPCACHE
	print "  for x in ${RC_PROVIDE} ; do" >> TMPCACHE
	print "    provide \"${x}\"" >> TMPCACHE
	print "  done" >> TMPCACHE
	print ")" >> TMPCACHE
	print "" >> TMPCACHE
}

BEGIN {
	# Get our environment variables
	SVCDIR = ENVIRON["SVCDIR"]
	if (SVCDIR == "") {
		eerror("Could not get SVCDIR!")
		exit 1
	}

	# Since this could be called more than once simultaneously, use a
	# temporary cache and rename when finished.  See bug 47111
	("echo -n \"${SVCDIR}/depcache.$$\"") | getline TMPCACHE
	if (TMPCACHE == "") {
		eerror("Failed to create temporary cache!")
		exit 1
	}

	pipe = "ls /etc/init.d/*"
	while ((pipe | getline tmpstring) > 0)
		scripts = scripts " " tmpstring
	close(pipe)

	split(scripts, TMPRCSCRIPTS)

	# Make sure that its a file we are working with,
	# and do not process scripts, source or backup files.
	for (x in TMPRCSCRIPTS)
		if (((isfile(TMPRCSCRIPTS[x])) || (islink(TMPRCSCRIPTS[x]))) &&
		    (TMPRCSCRIPTS[x] !~ /((\.(c|bak))|\~)$/)) {

			RCCOUNT++

			RCSCRIPTS[RCCOUNT] = TMPRCSCRIPTS[x]
		}

	if (RCCOUNT == 0) {
		eerror("No scripts to process!")
		dosystem("rm -f "TMPCACHE)
		exit 1
	}

	print_start()

	for (count = 1;count <= RCCOUNT;count++) {
		
		MYFNR = 1
		MYFILENAME = RCSCRIPTS[count]

		while (((getline < (RCSCRIPTS[count])) > 0) && (!NEXTFILE)) {

			# If line start with a '#' and is the first line
			if (($0 ~ /^[[:space:]]*#/) && (MYFNR == 1)) {
	
				# Remove any spaces and tabs
				gsub(/[[:space:]]+/, "")

				if ($0 == "#!/sbin/runscript") {

					if (RCSCRIPTS[count] ~ /\.sh$/) {

						ewarn(RCSCRIPTS[count] " is invalid (should not end with '.sh')")
						NEXTFILE = 1
						continue
					}

					ISRCSCRIPT = 1
					print_header1()
				} else  {
			
					NEXTFILE = 1
					continue
				}
			}

			# Filter out comments and only process if its a rcscript
			if (($0 !~ /^[[:space:]]*#/) && (ISRCSCRIPT)) {

				# If line contain 'depend()', set GOTDEPEND to 1
				if ($0 ~ /depend[[:space:]]*\(\)/) {
				
					GOTDEPEND = 1

					print_header2()
					print "  # Actual depend() function ..." >> TMPCACHE
				}
	
				# We have the depend function...
				if (GOTDEPEND) {

					# Basic theory is that COUNT will be 0 when we
					# have matching '{' and '}'
					COUNT += gsub(/{/, "{")
					COUNT -= gsub(/}/, "}")
		
					# This is just to verify that we have started with
					# the body of depend()
					SBCOUNT += gsub(/{/, "{")

					# Make sure depend() contain something, else bash
					# errors out (empty function).
					if ((SBCOUNT > 0) && (COUNT == 0))
						print "  \treturn 0" >> TMPCACHE
		
					# Print the depend() function
					print "  " $0 >> TMPCACHE
		
					# If COUNT=0, and SBCOUNT>0, it means we have read
					# all matching '{' and '}' for depend(), so stop.
					if ((SBCOUNT > 0) && (COUNT == 0)) {

						GOTDEPEND = 0
						COUNT = 0
						SBCOUNT = 0
						ISRCSCRIPT = 0

						print_end()
						
						NEXTFILE = 1
						continue
					}
				}
			}

			MYFNR++
		}

		close(RCSCRIPTS[count])

		NEXTFILE = 0

	}

	
	assert(dosystem("rm -f "SVCDIR"/depcache"), "system(rm -f "SVCDIR"/depcache)")
	assert(dosystem("mv "TMPCACHE" "SVCDIR"/depcache"), "system(mv "TMPCACHE" "SVCDIR"/depcache)")
}


# vim:ts=4