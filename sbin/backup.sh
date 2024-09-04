#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present Peter Tuschy (foss@bofh42.de)

# bash version 4 or later
[ ${BASH_VERSION%%.*} -ge 4 ] || exit 1
# bash version 4.2 or later
printf '%(%s)T' -1 >/dev/null 2>&1 || exit 1

export LANG=en_US.UTF-8

print_log() { echo "$(printf '%(%FT%T)T' -1) $@"; }
convertsecs() { ((h=${1}/3600)); ((m=(${1}%3600)/60)); ((s=${1}%60)); printf "%02d:%02d:%02d" $h $m $s; }
need_cmd() { hash "$1" 2>/dev/null; if [ $? -ne 0 ]; then echo "ERROR: script ${0##*/} needs command $1"; exit 1; fi; }
for i in readlink awk sed sort egrep ; do need_cmd $i ; done

SCRIPT=$(readlink -f $0)
WHERE=${SCRIPT%/*}
FHS=${WHERE%/*}
WHAT=${0##*/}
run=${WHAT%backup.sh}

## what is supported to run
case "${run}" in
  borg) : ;;
  *)    echo "ERROR: this script does not support backup with \"${run}\""; exit 1;;
esac

need_cmd ${run}

usage() {
echo ""
echo "usage: $0 [--server <fqdn> | -<1-9> ] --type <type> | --info | --list | --export [--verbose]"
cat << EOF

    -t|--type <type>        : set backup type to hourly, daily, weekly, monthly
    -1 up to -9             : backup target server (set in backup.conf and 1 is default)
    --server <fqdn>         : backup target server
    -v|--verbose            : more output
    -i|--info               : just do ${run} info
    -l|--list               : just do ${run} list
    -e|--export             : export setting to use ${run} on command line

EOF
}

show_env() {
    echo ""
    env | grep ^${run^^}
    echo ""
    echo "destination host \$CFG_DEST   : $CFG_DEST"
    echo "source host      \$CFG_HOST   : $CFG_HOST"
    if [ -z "${ONLY}" ]; then
        echo "backup type      \$CFG_TYPE   : $CFG_TYPE"
    fi
    echo ""
}

if [ $# -lt 1 ] ; then
    usage
    exit 1
fi

# version check
ver_ge() { [ "$1" = "`echo -e "$1\n$2" | sort -rV | head -n1`" ]; }
case "${run}" in
  borg) CFG_NEED="1.2.8"; CFG_VER="$(borg -V | awk '/^borg /{ print $2 }')";;
esac
if ver_ge $CFG_VER $CFG_NEED ; then 
  [ -n "$debug42" ] && echo "${run} version is $CFG_VER, we need at least ${CFG_NEED}"
else
  echo "ERROR ${run} version $CFG_VER is less than ${CFG_NEED}"
  exit 1
fi

for i in backup.conf exclude.pattern include.list ; do
  if [ -f "${FHS}/etc/${i}" ]; then
    : # this is fine we have a config file
  else
    cp "${FHS}/lib/${i}" "${FHS}/etc/${i}" \
      && echo "INFO: copied ${FHS}/lib/${i} to ${FHS}/etc/${i}" \
      || exit $?
  fi
done

ALL="$@"

# source host of the backup
CFG_HOST=${CFG_HOST:-${HOSTNAME%%.*}}

while [ -n "$1" ]; do
    case "$1" in
        -t|--type) shift
            CFG_TYPE="$1"
            shift
            ;;
        -v|--verbose) shift
            CFG_NOT_QUIET="--verbose --progress"
            ;;
        -l|--list) shift
            ONLY=list
            ;;
        -e|--export) shift
            ONLY=export
            ;;
        -i|--info) shift
            ONLY=info
            ;;
        --server) shift
            CFG_DEST=$1
            shift
            ;;
        -[1-9])
            if [ -n "$CFG_DEST" ]; then
                echo "ERROR just 1 server definition please"
                usage
                exit 1
            fi
            # what number to check
            CFG_NR=${1#-}
            shift
            # is there a CFG_DEST definition
            for i in CFG_DEST ${run^^}_REPO CFG_CREATE CFG_PRUNE_HOURLY CFG_PRUNE_DAILY CFG_PRUNE_WEEKLY CFG_PRUNE_MONTHLY CFG_PRUNE_YEARLY ; do
                eval $(grep "^${i}_${CFG_NR}=" ${FHS}/etc/backup.conf | sed -E "s|^${i}_[1-9]=|${i}=|")
                eval CFG_WHAT=\$${i}
                case "$i" in
                    "CFG_DEST")
                        if [ -z "$CFG_WHAT" ]; then
                            echo "ERROR destination host CFG_DEST_${CFG_NR} not defined in ${FHS}/etc/backup.conf"
                            exit 1
                        fi
                        ;;
                esac
            done
            ;;
        --) shift
            break
            ;;
        *)
            echo ""
            echo "ERROR parameter not known"
            usage
            exit 1
            ;;
    esac
done

## should it be quiet
[ -z "$CFG_NOT_QUIET" ] && QUIET="--quiet"
[ -n "$CFG_NOT_QUIET" ] && SETX=' set -x ' || SETX=' : '

## do we have a backup host
if [ -z "$CFG_DEST" ]; then
    eval $(grep "^CFG_DEST_1=" ${FHS}/etc/backup.conf | sed -E 's|^CFG_DEST_1=|CFG_DEST=|')
fi

# check for the target host
if [ -z "${CFG_DEST}" ]; then
    echo ""
    echo "ERROR backup target host not defined"
    echo "      not as CFG_DEST_1 in ${FHS}/etc/backup.conf"
    echo "      or on command line with --server"
    show_env
    usage
    exit 1
fi

# short destination hostname
CFG_DEST_SHORT=${CFG_DEST%%.*}

# short name for source to destination
CFG_S2D=${CFG_HOST}2${CFG_DEST_SHORT}

# where is the repo (that should be relativ)
case "${run}" in
  borg)
    BORG_REPO=${BORG_REPO:-ssh://z${run}@${CFG_DEST}/~/hosts/${CFG_HOST}}
    export BORG_REPO
    ;;
  *)
    echo "ERROR: this script does not support backup with \"${run}\""
    exit 1
    ;;
esac

# do we have a password/passphrase
CFG_KEY_PASSWORD="${run}_${CFG_S2D}.pass"
if [ ! -f ${HOME}/.ssh/${CFG_KEY_PASSWORD} ]; then
    echo ""
    echo "ERROR missig ${CFG_KEY_PASSWORD}"
    echo "create with next line"
    echo "head -c 37 /dev/urandom | base64 -w 0 > ${HOME}/.ssh/${CFG_KEY_PASSWORD} ; chmod 0400 ${HOME}/.ssh/${CFG_KEY_PASSWORD}"
    echo ""
    exit 1
else
    export ${run^^}_PASSCOMMAND="cat ${HOME}/.ssh/${CFG_KEY_PASSWORD}"
fi

# is it a ssh repo
eval CFG_REPO=\$${run^^}_REPO
echo "$CFG_REPO" | grep -q '^ssh://'
if [ $? -eq 0 ]; then
    # what ssh key to use
    CFG_SSH_KEY="${run}_${CFG_S2D}"
    if [ ! -f ${HOME}/.ssh/${CFG_SSH_KEY} ]; then
        echo ""
        echo "ERROR missig ${CFG_SSH_KEY}"
        echo "create with next line BUT without passphrase"
        echo "ssh-keygen -t ed25519 -f ${HOME}/.ssh/${CFG_SSH_KEY} -C \"${CFG_SSH_KEY}\""
        echo ""
        exit 1
    else
        export ${run^^}_RSH="ssh -i ${HOME}/.ssh/${CFG_SSH_KEY}"
    fi
fi

# this is used for create commands
CFG_CREATE=${CFG_CREATE:- --error --exclude-if-present .nobackup --keep-exclude-tags --exclude-caches --exclude-nodump}

# prune config
# hourly only runs every 4h in default cron setup
CFG_PRUNE_HOURLY=${CFG_PRUNE_HOURLY:-13}
CFG_PRUNE_DAILY=${CFG_PRUNE_DAILY:-8}
CFG_PRUNE_WEEKLY=${CFG_PRUNE_WEEKLY:-6}
CFG_PRUNE_MONTHLY=${CFG_PRUNE_MONTHLY:-18}
# only monthly backups will be used as yearly, there is no extra yearly backup type
CFG_PRUNE_YEARLY=${CFG_PRUNE_YEARLY:-3}

# cache in /var/cache at least for root
if [ "$(id -u)" = "0" ]; then
  eval CFG_CACHE_DIR=\$${run^^}_CACHE_DIR
  export ${run^^}_CACHE_DIR=${CFG_CACHE_DIR:-/var/cache/${run}/root/${CFG_S2D}}
fi

if [ -n "$CFG_NOT_QUIET" -a ! "${ONLY}" = "export" ]; then
    show_env
fi

# just list backup or show archive info and exit
if [ -n "${ONLY}" -a "${ONLY}" = "export" ]; then
    echo ""
    echo "# to export your ${run} config to your shell for ${run} command line use"
    echo "# execute the next line or copy & paste the ${run^^}_* line to your shell"
    echo ""
    echo "eval \$($0 ${ALL} | egrep -v '^\$|^#|^eval')"
    echo ""
    echo "export CFG_S2D=$CFG_S2D"
    show_env | grep ^${run^^} | sed -E 's|^|export |g ; s|=|="|g ; s|$|"|g'
    exit 0
elif [ -n "${ONLY}" ]; then
    ( ${SETX} ; ${run} ${ONLY} $@ )
    exit $?
fi

if [ -z "$CFG_DEST" -o -z "$CFG_HOST" -o -z "$CFG_TYPE" -o -z "$CFG_REPO" ]; then
    echo ""
    echo "ERROR: please make sure all needed variables are defined"
    show_env
    exit 2
fi


# what type of backup is it
case "${CFG_TYPE}" in
    hourly)
        # dont run at midnight
        if [ "$(date +%H)" = "00" ]; then exit 0 ; fi
        CFG_PRUNE="--keep-hourly ${CFG_PRUNE_HOURLY}"
        ;;
    daily)
        # dont run on the 01 day in the month
        if [ "$(date +%d)" = "01" ]; then exit 0 ; fi
        # dont run on monday
        if [ "$(date +%w)" = "1" ]; then exit 0 ; fi
        CFG_PRUNE="--keep-daily ${CFG_PRUNE_DAILY}"
        ;;
    weekly)
        # dont run on the 01 day in the month
        if [ "$(date +%d)" = "01" ]; then exit 0 ; fi
        CFG_PRUNE="--keep-weekly ${CFG_PRUNE_WEEKLY}"
        ;;
    monthly)
        CFG_PRUNE="--keep-monthly ${CFG_PRUNE_MONTHLY} --keep-yearly ${CFG_PRUNE_YEARLY}"
        ;;
    *)
        CFG_PRUNE=
        ;;
esac

# collecting mountpoint to backup
CFG_MOUNTS=()
for i in $(df --no-sync -lPT -x tmpfs -x devtmpfs | awk '/^\/dev\//''{ print $NF }'); do
  CFG_MOUNTS+=("$i")
done
for include in ${FHS}/etc/include.list ${FHS}/etc/include.list.${CFG_TYPE} ; do
  if [ -f "$include" ]; then
    for i in $(egrep -v '^$|^#' "$include"); do
      CFG_MOUNTS+=("$i")
    done
  fi
done

[ -n "$CFG_NOT_QUIET" ] && echo "start ${CFG_TYPE} ${run} backup for ${CFG_HOST}"
[ -n "$CFG_NOT_QUIET" ] && echo -e "\n${run} create ${CFG_NOT_QUIET} -x ${CFG_CREATE} --exclude-from ${FHS}/etc/exclude.pattern ::{now:%Y-%m-%dT%H:%M}.${CFG_TYPE} ${CFG_MOUNTS[*]}"

( ${SETX} ; ${run} create ${CFG_NOT_QUIET} -x ${CFG_CREATE} --exclude-from ${FHS}/etc/exclude.pattern ::{now:%Y-%m-%dT%H:%M}.${CFG_TYPE} ${CFG_MOUNTS[*]} )
CFG_EXIT=$?

if [ $CFG_EXIT -gt 1 ]; then
    echo "ERROR exit code $CFG_EXIT ${CFG_TYPE} ${run} backup for ${CFG_HOST} ${CFG_MOUNTS[*]}"
else
    env | grep -E "^${run^^}_REPO|^${run^^}_RSH" | sort >/run/${run}backup-list-${CFG_S2D}
    echo "cmd: ${run} create ${CFG_NOT_QUIET} -x ${CFG_CREATE} --exclude-from ${FHS}/etc/exclude.pattern ::{now:%Y-%m-%dT%H:%M}.${CFG_TYPE} ${CFG_MOUNTS[*]}" >>/run/${run}backup-list-${CFG_S2D}
    if [ -n "${CFG_PRUNE}" ]; then
        [ -n "$CFG_NOT_QUIET" ] && echo "${run} prune ${CFG_NOT_QUIET} ${CFG_PRUNE} -a \"*.${CFG_TYPE}\""
        ( ${SETX} ; ${run} prune ${CFG_NOT_QUIET} ${CFG_PRUNE} -a "*.${CFG_TYPE}" )
        echo "cmd: ${run} prune ${CFG_NOT_QUIET} ${CFG_PRUNE} -a \"*.${CFG_TYPE}\"" >>/run/${run}backup-list-${CFG_S2D}
        ( ${SETX} ; ${run} compact ${CFG_NOT_QUIET} )
        echo "cmd: ${run} compact ${CFG_NOT_QUIET}" >>/run/${run}backup-list-${CFG_S2D}
    fi
    [ -n "$CFG_NOT_QUIET" ] && echo "${run} list >/run/${run}backup-list-${CFG_S2D}"
    ( ${SETX} ; ${run} list >>/run/${run}backup-list-${CFG_S2D} )
fi

[ -n "$CFG_NOT_QUIET" ] && echo -e "\ndone ${CFG_TYPE} ${run} backup for ${CFG_HOST}\n"


