#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present Peter Tuschy (foss@bofh42.de)

# bash version 4 or later
[ ${BASH_VERSION%%.*} -ge 4 ] || exit 1
# bash version 4.2 or later
printf '%(%s)T' -1 >/dev/null 2>&1 || exit 1

export LANG=en_US.UTF-8

need_cmd() { command -v "$1" >/dev/null 2>&1; if [ $? -ne 0 ]; then echo "ERROR: script ${0##*/} needs command $1"; exit 1; fi; }
for i in readlink egrep awk  ; do need_cmd $i ; done

SCRIPT=$(readlink -f $0)
WHERE=${SCRIPT%/*}
FHS=${WHERE%/*}

print_log() { echo "$(printf '%(%FT%T)T' -1) $@"; }
# CFG_IGN_<id>="a,b" in <conf>: true if the comma list has <word> or all
ign_has() { local ign; ign=$(grep -m1 "^CFG_IGN_$2=" "$1" | cut -d= -f2- | tr -d "\"' "); [[ ",${ign}," == *",$3,"* || ",${ign}," == *",all,"* ]]; }

for conf in ${FHS}/etc/*.conf; do
  run=$(basename "$conf" .conf)
  [ -x "${FHS}/bin/${run}backup.sh" ] || continue
  for id in $(grep -E "^CFG_DEST_[1-9]=[^\\$]+" "$conf" | awk -F= '{print $1}' | awk -F_ '{print $3}'); do
    if ign_has "$conf" "$id" init-state; then
      print_log "INFO: skip ${run}backup.sh --init-state -${id}, CFG_IGN_${id} has init-state or all"
      continue
    fi
    "${FHS}/bin/${run}backup.sh" --init-state "-${id}" "$@"
  done
done