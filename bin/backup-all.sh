#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present Peter Tuschy (foss@bofh42.de)

# bash version 4 or later
[ ${BASH_VERSION%%.*} -ge 4 ] || exit 1
# bash version 4.2 or later
printf '%(%s)T' -1 >/dev/null 2>&1 || exit 1

export LANG=en_US.UTF-8

print_log() { echo "$(printf '%(%FT%T)T' -1) $@"; }
need_cmd() { command -v "$1" >/dev/null 2>&1; if [ $? -ne 0 ]; then echo "ERROR: script ${0##*/} needs command $1"; exit 1; fi; }
for i in readlink grep awk ; do need_cmd $i ; done

SCRIPT=$(readlink -f $0)
WHERE=${SCRIPT%/*}
FHS=${WHERE%/*}

usage() {
cat << EOF

usage: $0 <type> [tool ...] [-v|--verbose]

    runs <tool>backup.sh -<id> -t <type> for every CFG_DEST_<id> in ${FHS}/etc/<tool>.conf
    type                    : mandatory, first parameter
                              hourly, daily, weekly, monthly with forget (keep rules)
                              any other like pre-reinstall without forget
    tool                    : borg, restic, ... (default: every tool with a etc/<tool>.conf)
                              targets with backup-all or all in CFG_IGN_<id> are skipped
    -v|--verbose            : passed on to <tool>backup.sh
    -h|--help               : this help

EOF
}

# tool is usable if it has a config and a backup script
tool_ok() { [ -f "${FHS}/etc/$1.conf" -a -x "${FHS}/bin/$1backup.sh" ]; }

# CFG_IGN_<id>="a,b" in <conf>: true if the comma list has <word> or all
ign_has() { local ign; ign=$(grep -m1 "^CFG_IGN_$2=" "$1" | cut -d= -f2- | tr -d "\"' "); [[ ",${ign}," == *",$3,"* || ",${ign}," == *",all,"* ]]; }

# any type is fine (own types get no forget), it ends up in tags and archive names
case "$1" in
  -h|--help) usage; exit 0 ;;
  "") echo ""; echo "ERROR backup type missing"; usage; exit 1 ;;
  -*) echo ""; echo "ERROR first parameter must be the backup type, not $1"; usage; exit 1 ;;
esac
if [[ ! "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo ""; echo "ERROR backup type \"$1\" only with A-Z a-z 0-9 . _ - please"; usage; exit 1
fi
TYPE="$1"; shift

TOOLS=()
VERBOSE=""
while [ -n "$1" ]; do
  case "$1" in
    -v|--verbose) VERBOSE="--verbose" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo ""; echo "ERROR parameter $1 not known"; usage; exit 1 ;;
    *)
      if ! tool_ok "$1"; then
        echo "ERROR tool $1 needs ${FHS}/etc/$1.conf and ${FHS}/bin/$1backup.sh"
        exit 1
      fi
      [[ " ${TOOLS[*]} " == *" $1 "* ]] || TOOLS+=("$1")
      ;;
  esac
  shift
done

# no tool given: every etc/<tool>.conf with a <tool>backup.sh (like init-state-files.sh)
if [ ${#TOOLS[@]} -eq 0 ]; then
  for conf in ${FHS}/etc/*.conf; do
    run=$(basename "$conf" .conf)
    tool_ok "$run" && TOOLS+=("$run")
  done
fi

EXIT=0
FOUND=0
for run in "${TOOLS[@]}"; do
  for id in $(grep -E "^CFG_DEST_[1-9]=[^\\$]+" "${FHS}/etc/${run}.conf" | awk -F= '{print $1}' | awk -F_ '{print $3}'); do
    FOUND=1
    # CFG_IGN_<id> with backup-all or all skips it here, <tool>backup.sh -<id> still works
    if ign_has "${FHS}/etc/${run}.conf" "${id}" backup-all; then
      [ -n "$VERBOSE" ] && print_log "INFO: skip ${run}backup.sh -${id}, CFG_IGN_${id} has backup-all or all"
      continue
    fi
    [ -n "$VERBOSE" ] && print_log "INFO: start ${run}backup.sh -${id} -t ${TYPE}"
    "${FHS}/bin/${run}backup.sh" "-${id}" -t "${TYPE}" ${VERBOSE}
    rc=$?
    # keep going with the other targets, report the highest exit code at the end
    if [ $rc -ne 0 ]; then
      print_log "ERROR: ${run}backup.sh -${id} -t ${TYPE} exit code ${rc}"
      [ $rc -gt $EXIT ] && EXIT=$rc
    fi
  done
done

if [ $FOUND -eq 0 ]; then
  print_log "ERROR: no backup target (CFG_DEST_[1-9]=) found for ${TOOLS[*]:-any tool} in ${FHS}/etc/"
  exit 1
fi
exit $EXIT
