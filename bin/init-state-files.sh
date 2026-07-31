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

for conf in ${FHS}/etc/*.conf; do
  run=$(basename "$conf" .conf)
  [ -x "${FHS}/bin/${run}backup.sh" ] || continue
  for id in $(grep -E "^CFG_DEST_[1-9]=[^\\$]+" "$conf" | awk -F= '{print $1}' | awk -F_ '{print $3}'); do
    "${FHS}/bin/${run}backup.sh" --init-state "-${id}" "$@"
  done
done