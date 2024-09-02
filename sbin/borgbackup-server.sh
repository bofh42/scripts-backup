#!/usr/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2023-present Peter Tuschy (foss@bofh42.de)

[ ${BASH_VERSION%%.*} -ge 4 ] || exit 1

LANG=en_US.UTF-8
export LANG
SCRIPT=$(readlink -f $0)
WHERE=${SCRIPT%/*}
FHS=${WHERE%/*}

usage() {
echo ""
echo "usage: $0 [--server <fqdn> | -<1-9> ] --type <type> | --info | --list | --export [--verbose]"
cat << EOF

    -t|--type <type>        : set backup type to hourly, daily, weekly, monthly
    -1 up to -9             : backup target server (set in backup.conf and 1 is default)
    --server <fqdn>         : backup target server
    -v|--verbose            : more output
    -i|--info               : just do borg info
    -l|--list               : just do borg list
    -e|--export             : export setting to use borg on command line

EOF
}

show_env() {
    echo ""
    env | grep ^BORG
    echo ""
    echo "destination host \$BB_DEST   : $BB_DEST"
    echo "source host      \$BB_HOST   : $BB_HOST"
    if [ -z "${ONLY}" ]; then
        echo "backup type      \$BB_TYPE   : $BB_TYPE"
    fi
    echo ""
}

if [ $# -lt 1 ] ; then
    usage
    exit 1
fi

# version check
ver_ge() { [ "$1" = "`echo -e "$1\n$2" | sort -rV | head -n1`" ]; }
BB_VER="$(borg -V | awk '/^borg /{ print $2 }')"
BB_NEED="1.1.13"
BB_VER12="1.2.0"
if ver_ge $BB_VER $BB_NEED ; then 
  [ -n "$rzdebug" ] && echo "borg version is $BB_VER, we need at least ${BB_NEED}"
else
  echo "ERROR borg version $BB_VER is less than ${BB_NEED}"
  exit 1
fi

ALL="$@"

#
# getopt long
#
SHORT_OPTIONS="t:vile123456789"
LONG_OPTIONS="type:,verbose,info,list,export,server:"
# Invoke getopt; suppress its stderr initially.
args=$(getopt -o $SHORT_OPTIONS -l $LONG_OPTIONS -n $0 -- "$@")
if [ $? -ne 0 ]; then
    usage
    exit 1
fi
eval set -- "$args"

# source host of the backup
BB_HOST=${BB_HOST:-${HOSTNAME%%.*}}

while true; do
    case "$1" in
        -t|--type) shift
            BB_TYPE="$1"
            shift
            ;;
        -v|--verbose|--progress) shift
            BB_NOT_QUIET="--verbose --progress"
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
            BB_DEST=$1
            shift
            ;;
        -[1-9])
            if [ -n "$BB_DEST" ]; then
                echo "ERROR just 1 server definition please"
                usage
                exit 1
            fi
            # what number to check
            BB_NR=${1#-}
            shift
            # is there a BB_DEST definition
            for i in BB_DEST BORG_REPO BB_CREATE BB_PRUNE_HOURLY BB_PRUNE_DAILY BB_PRUNE_WEEKLY BB_PRUNE_MONTHLY BB_PRUNE_YEARLY ; do
                eval $(grep "^${i}_${BB_NR}=" /opt/borgbackup/etc/backup.conf | sed -E "s|^${i}_[1-9]=|${i}=|")
                eval BB_WHAT=\$${i}
                case "$i" in
                    "BB_DEST")
                        if [ -z "$BB_WHAT" ]; then
                            echo "ERROR destination host BB_DEST_${BB_NR} not defined in /opt/borgbackup/etc/backup.conf"
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

## do we have a backup host
if [ -z "$BB_DEST" ]; then
    eval $(grep "^BB_DEST_1=" /opt/borgbackup/etc/backup.conf | sed -E 's|^BB_DEST_1=|BB_DEST=|')
fi

# check for the target host
if [ -z "${BB_DEST}" ]; then
    echo ""
    echo "ERROR backup target host not defined"
    echo "      not as BB_DEST_1 in /etc/borgbackup/backup.conf"
    echo "      nor on command line with --server"
    show_env
    usage
    exit 1
fi

# short destination hostname
BB_DEST_SHORT=${BB_DEST%%.*}

# short name for source to destination
BB_S2D=${BB_HOST}2${BB_DEST_SHORT}

# where is the repo (that should be relativ)
BORG_REPO=${BORG_REPO:-ssh://zborg@${BB_DEST}/~/hosts/${BB_HOST}}
export BORG_REPO

# do we have a passphrase
BB_KEY_PASSWORD="borg_${BB_S2D}.bb"
if [ ! -f ${HOME}/.ssh/${BB_KEY_PASSWORD} ]; then
    echo ""
    echo "ERROR missig ${BB_KEY_PASSWORD}"
    echo "create with next line"
    echo "head -c 37 /dev/urandom | base64 -w 0 > ${HOME}/.ssh/${BB_KEY_PASSWORD} ; chmod 0400 ${HOME}/.ssh/${BB_KEY_PASSWORD}"
    echo ""
    exit 1
else
    export BORG_PASSCOMMAND="cat ${HOME}/.ssh/${BB_KEY_PASSWORD}"
fi

# is it a ssh repo
echo "$BORG_REPO" | grep -q '^ssh://'
if [ $? -eq 0 ]; then
    # what ssh key to use
    BB_SSH_KEY="borg_${BB_S2D}"
    if [ ! -f ${HOME}/.ssh/${BB_SSH_KEY} ]; then
        echo ""
        echo "ERROR missig ${BB_SSH_KEY}"
        echo "create with next line BUT without passphrase"
        echo "ssh-keygen -t ed25519 -f ${HOME}/.ssh/${BB_SSH_KEY} -C \"${BB_SSH_KEY}\""
        echo ""
        exit 1
    else
        export BORG_RSH="ssh -i ${HOME}/.ssh/${BB_SSH_KEY}"
    fi
fi

# this is used for create commands
BB_CREATE=${BB_CREATE:- --error --exclude-if-present .nobackup --exclude-if-present .bbe --keep-exclude-tags --exclude-caches --exclude-nodump $(ver_ge $BB_VER $BB_VER12 || echo "--noatime")}

# prune config
# hourly only runs every 4h in default cron setup
BB_PRUNE_HOURLY=${BB_PRUNE_HOURLY:-13}
BB_PRUNE_DAILY=${BB_PRUNE_DAILY:-8}
BB_PRUNE_WEEKLY=${BB_PRUNE_WEEKLY:-6}
BB_PRUNE_MONTHLY=${BB_PRUNE_MONTHLY:-18}
# only monthly backups will be used as yearly, there is no extra yearly backup type
BB_PRUNE_YEARLY=${BB_PRUNE_YEARLY:-3}

# cache in /var/cache at least for root
if [ "$(id -u)" = "0" ]; then
    export BORG_CACHE_DIR=${BORG_CACHE_DIR:-/var/cache/borg/root/${BB_S2D}}
fi

if [ -n "$BB_NOT_QUIET" -a ! "${ONLY}" = "export" ]; then
    show_env
fi

# just list backup or show archive info and exit
if [ -n "${ONLY}" -a "${ONLY}" = "export" ]; then
    echo ""
    echo "# to export your borg config to your shell for borg command line use"
    echo "# execute the next line or copy & paste the BORG_* line to your shell"
    echo ""
    echo "eval \$($0 ${ALL} | egrep -v '^\$|^#|^eval')"
    echo ""
    echo "export BB_S2D=$BB_S2D"
    show_env | grep ^BORG | sed -E 's|^|export |g ; s|=|="|g ; s|$|"|g'
    exit 0
elif [ -n "${ONLY}" ]; then
    borg ${ONLY} $@
    exit $?
fi

if [ -z "$BB_DEST" -o -z "$BB_HOST" -o -z "$BB_TYPE" -o -z "$BORG_REPO" ]; then
    echo ""
    echo "ERROR: please make sure all needed variables are defined"
    show_env
    exit 2
fi


# what type of backup is it
case "${BB_TYPE}" in
    hourly)
        # dont run at midnight
        if [ "$(date +%H)" = "00" ]; then exit 0 ; fi
        BB_PRUNE="--keep-hourly ${BB_PRUNE_HOURLY}"
        ;;
    daily)
        # dont run on the 01 day in the month
        if [ "$(date +%d)" = "01" ]; then exit 0 ; fi
        # dont run on monday
        if [ "$(date +%w)" = "1" ]; then exit 0 ; fi
        BB_PRUNE="--keep-daily ${BB_PRUNE_DAILY}"
        ;;
    weekly)
        # dont run on the 01 day in the month
        if [ "$(date +%d)" = "01" ]; then exit 0 ; fi
        BB_PRUNE="--keep-weekly ${BB_PRUNE_WEEKLY}"
        ;;
    monthly)
        BB_PRUNE="--keep-monthly ${BB_PRUNE_MONTHLY} --keep-yearly ${BB_PRUNE_YEARLY}"
        ;;
    *)
        BB_PRUNE=
        ;;
esac

# collecting mountpoint to backup
BB_MOUNTS=()
for i in $(df --no-sync -lPT -x tmpfs -x devtmpfs | awk '/^\/dev\//''{ print $NF }'); do
  BB_MOUNTS+=("$i")
done
for include in ${FHS}/etc/include.list ${FHS}/etc/include.list.${BB_TYPE} ; do
  if [ -f "$include" ]; then
    for i in $(egrep -v '^$|^#' "$include"); do
      BB_MOUNTS+=("$i")
    done
  fi
done

[ -n "$BB_NOT_QUIET" ] && echo "start ${BB_TYPE} borg backup for ${BB_HOST}"
[ -n "$BB_NOT_QUIET" ] && echo -e "\nborg create ${BB_NOT_QUIET} -x ${BB_CREATE} --exclude-from ${FHS}/etc/exclude.pattern ::{now:%Y-%m-%dT%H:%M}.${BB_TYPE} ${BB_MOUNTS[*]}"

borg create ${BB_NOT_QUIET} -x ${BB_CREATE} --exclude-from ${FHS}/etc/exclude.pattern ::{now:%Y-%m-%dT%H:%M}.${BB_TYPE} ${BB_MOUNTS[*]}
BB_EXIT=$?

if [ $BB_EXIT -gt 1 ]; then
    echo "ERROR exit code $BB_EXIT ${BB_TYPE} borg backup for ${BB_HOST} ${BB_MOUNTS[*]}"
else
    env | egrep '^BORG_REPO|^BORG_RSH' | sort >/run/borgbackup-list-${BB_S2D}
    echo "cmd: borg create ${BB_NOT_QUIET} -x ${BB_CREATE} --exclude-from ${FHS}/etc/exclude.pattern ::{now:%Y-%m-%dT%H:%M}.${BB_TYPE} ${BB_MOUNTS[*]}" >>/run/borgbackup-list-${BB_S2D}
    if [ -n "${BB_PRUNE}" ]; then
        [ -n "$BB_NOT_QUIET" ] && echo "borg prune ${BB_NOT_QUIET} ${BB_PRUNE} -a \"*.${BB_TYPE}\""
        borg prune ${BB_NOT_QUIET} ${BB_PRUNE} -a "*.${BB_TYPE}"
        echo "cmd: borg prune ${BB_NOT_QUIET} ${BB_PRUNE} -a \"*.${BB_TYPE}\"" >>/run/borgbackup-list-${BB_S2D}
        if ver_ge $BB_VER $BB_VER12 ; then
            borg compact ${BB_NOT_QUIET}
            echo "cmd: borg compact ${BB_NOT_QUIET}" >>/run/borgbackup-list-${BB_S2D}
        fi
    fi
    [ -n "$BB_NOT_QUIET" ] && echo "borg list >/run/borgbackup-list-${BB_S2D}"
    borg list >>/run/borgbackup-list-${BB_S2D}
fi

[ -n "$BB_NOT_QUIET" ] && echo -e "\ndone ${BB_TYPE} borg backup for ${BB_HOST}\n"


