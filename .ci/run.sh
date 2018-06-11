#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

# This script will execute the Kata Containers Test Suite. 

set -e

check_log_files()
{
	make log-parser

	# XXX: Only the CC runtime uses structured logging,
	# XXX: hence specify by name (rather than using $RUNTIME).
	for component in \
		kata-proxy \
		kata-runtime \
		kata-shim
	do
		file="${component}.log"
		args="--no-pager -q -o cat -a -t \"${component}\""

		cmd="sudo journalctl ${args} > ${file}"
		eval "$cmd"
	done

	logs=$(ls "$(pwd)"/*.log)
	{ kata-log-parser --debug --check-only --error-if-no-records $logs; ret=$?; } || true

	errors=0

	for log in $logs
	do
		# Display *all* errors caused by runtime exceptions and fatal
		# signals.
		for pattern in "fatal error" "fatal signal"
		do
			# Search for pattern and print all subsequent lines with specified log
			# level.
			results=$(sed -ne "/\<${pattern}\>/,\$ p" "$log" || true | grep "level=\"*error\"*")
			if [ -n "$results" ]
			then
				errors=1
				echo >&2 -e "ERROR: detected ${pattern} in '${log}'\n${results}" || true
			fi
		done

		for pattern in "segfault at [0-9]"
		do
			results=$(sed -ne "/\<${pattern}\>/,\$ p" "$log" || true)

			if [ -n "$results" ]
			then
				errors=1
				echo >&2 -e "ERROR: detected ${pattern} in '${log}'\n${results}" || true
			fi
		done
	done

	[ "$errors" -ne 0 ] && exit 1

	# Always remove logs since:
	#
	# - We don't want to waste disk-space.
	# - The teardown script will save the full logs anyway.
	# - the log parser tool shows full details of what went wrong.
	rm -f $logs

	[ $ret -eq 0 ] && true || false
}

check_collect_script()
{
	local cmd="kata-collect-data.sh"
	local cmdpath=$(command -v "$cmd" || true)

	local msg="Kata data collection script"

	if [ -z "$cmdpath" ]
	then
		echo "INFO: $msg not found"
		return
	fi

	echo "INFO: Checking $msg"
	sudo -E PATH="$PATH" chronic $cmd
}

export RUNTIME="kata-runtime"

echo "INFO: Running checks"
sudo -E PATH="$PATH" bash -c "make check"

echo "INFO: Running functional and integration tests ($PWD)"
sudo -E PATH="$PATH" bash -c "make test"

echo "INFO: Checking log files"
check_log_files

check_collect_script
