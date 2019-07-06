#!/bin/sh

grep -E '\[mc ' src/*.tcl | sed -E -e 's/\[mc /^/g' | \
	cut -d'^' -f2 | sed -E -e 's/([A-Za-z0-9.-]+)\]/"\1"]/g' | \
	cut -d'"' -f2 | sort -u
