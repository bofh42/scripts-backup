#!/usr/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2023-present Peter Tuschy (foss@bofh42.de)

[ ${BASH_VERSION%%.*} -ge 4 ] || exit 1

LANG=en_US.UTF-8
export LANG
SCRIPT=$(readlink -f $0)
WHERE=${SCRIPT%/*}
FHS=${WHERE%/*}


# zfs filesystems list with excludes
eZFSs=$(cat ${FHS}/etc/zfs.fs-exclude | grep -v -E '^#|^$' | sed -e "s|__zpool__|${SPOOL}|g" | xargs | sed -e 's|^|^|' -e 's# #|^#g')

for i in "$@" ; do
  SPOOL=$i
  /usr/sbin/zpool list -H -o name  | egrep -q "^${SPOOL}$"
  if [ $? -ne 0 ] ; then
    echo "ERROR source pool $1 does not exist"
    exit 1
  fi
  /usr/sbin/zfs list -t filesystem -r -H -o name ${SPOOL} | egrep -v "$eZFSs" | while read line ; do /usr/sbin/zfs list -t filesystem -H -o mountpoint ${line} ; done
done | grep -Ev '^none$'
