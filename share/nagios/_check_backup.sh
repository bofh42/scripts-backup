#!/usr/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present Peter Tuschy (foss@bofh42.de)

# bash version 4 or later
[ ${BASH_VERSION%%.*} -ge 4 ] || exit 1

export LANG=en_US.UTF-8

need_cmd() { command -v "$1" >/dev/null 2>&1 ; if [ $? -ne 0 ]; then echo "ERROR: script ${0##*/} needs command $1"; exit 1; fi; }
for i in readlink uname find tail sed egrep xargs wc ; do need_cmd $i ; done

SCRIPT=$(readlink -f $0)
WHERE=${SCRIPT%/*}
WHAT=${0##*/}
WHAT=${WHAT##check_}
TYPE=${WHAT%backup.sh}

# Version    : 2.0.0 - 2026-04-07
# Info       : derived from check_borgbackup.sh by duc and unified by bofh42
# Version    : 2.1.0 - 2026-04-22
# Info       : added type other, default warn now 10h
# Version    : 2.2.0 - 2026-08-04
# Info       : added lock detection for restic

# setting default exit values
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

# import exit values from utils.sh if we found one
if   [ -f ${WHERE}/utils.sh ] ; then
  . ${WHERE}/utils.sh
elif [ -f ${WHERE}/../utils.sh ] ; then
  . ${WHERE}/../utils.sh
fi

usage() {
  echo "Usage: $0 [-w <time in hours>] [-c <time in hours>]"
  exit $STATE_UNKNOWN
}

# a default for now
warning=10
critical=27

# command line parsing
while [ "$1" != "" ]; do
  case $1 in
    -w)
      shift
      warning=$1
      ;;
    -c)
      shift
      critical=$1
      ;;
    --help|-h)
      usage
      ;;
    -*)
      usage
      ;;
    *)
      usage
      ;;
  esac
  shift
done

# threshold values
if [ -n "${critical}" ] ; then
  if [ ${critical} -lt 0 ] ; then
    echo "Critical must be a positive integer."
    exit $STATE_UNKNOWN
  fi
fi
if [ -n "${warning}" ] ; then
  if [ ${warning} -lt 0 ] ; then
    echo "Critical must be a positive integer."
    exit $STATE_UNKNOWN
  fi
fi

if [ -n "${critical}" -a -n "${warning}" ] ; then
  if [ ${critical} -lt ${warning} ] ; then
    echo "critical must be greater than warning value."
    exit $STATE_UNKNOWN
  fi
fi

OS=`uname`

case "${OS}" in
  Linux)
    DEST=$(find /run -name "${TYPE}backup-list-${HOSTNAME%%.*}2*")
    ;;
  *)
    echo "OS ${OS} not supportet by this check"
    exit $STATE_UNKNOWN
esac

for i in ${DEST} ; do
  LOCKINFO=""
  case "${TYPE}" in
    other) LAST=$(tail -n 1 $i) ;;
    borg) LAST=$(tail -n 1 $i | sed -E 's|\..*||') ;;
    restic)
      LAST=$(grep -E '^[0-9a-f]{8}' $i | tail -n 1 | awk '{print $2"T"$3}')
      LOCKs="$(grep '^locks:' $i | xargs -rn1 | grep -Ev '^(locks:|none)$' | wc -l)"
      [ "${LOCKs:-0}" -gt 0 ] && LOCKINFO="_locks:${LOCKs}"
      ;;
  esac
  if [ -z "${LAST}" ]; then
    echo "ERROR: could not find any last date for ${TYPE}"
    exit 1
  fi
  server=${i#/run/*${TYPE}backup-list-${HOSTNAME%%.*}2}
  DIFF=$(echo "`date "+%s"` - `date -d $LAST "+%s"`" | bc)
  OLD=$(echo "$DIFF / 60 / 60 " | bc)
  if [ $OLD -ge $critical ]; then
    PLUGCRIT+="${server}_${OLD}h${LOCKINFO} "
  elif [ $OLD -ge $warning ] || [ -n "${LOCKINFO}" ] ; then
    PLUGWARN+="${server}_${OLD}h${LOCKINFO} "
  else
    PLUGOK+="${server}_${OLD}h${LOCKINFO} "
  fi
done
# at least warn if there is no state
if [ -z "$DEST" ]; then
  PLUGDATA+="WARNING no backup state in /run for ${TYPE}backup-list-${HOSTNAME%%.*}2* found"
  [ -z "$EXIT_STATE" ] && EXIT_STATE=$STATE_WARNING
fi

if [ -n "$PLUGCRIT" ]; then
  PLUGDATA+="CRITICAL ${TYPE} backup $PLUGCRIT"
  EXIT_STATE=$STATE_CRITICAL
fi
if [ -n "$PLUGWARN" ]; then
  PLUGDATA+="WARNING ${TYPE} backup $PLUGWARN"
  [ -z "$EXIT_STATE" ] && EXIT_STATE=$STATE_WARNING
fi
if [ -n "$PLUGOK" ]; then
  PLUGDATA+="OK ${TYPE} backup $PLUGOK"
  [ -z "$EXIT_STATE" ] && EXIT_STATE=$STATE_OK
fi

echo "${PLUGDATA}"
exit $EXIT_STATE
