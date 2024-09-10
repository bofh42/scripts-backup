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

need_cmd ${run}

## what is supported to run with some config
declare -A CFG
declare -A CMD
declare -A OPT
declare -A VAR
case "${run}" in
  borg)
    CFG[need]="1.2.8"
    CFG[version]="$(borg -V | awk '/^borg /{ print $2 }')"
    CFG[pass]="37"
    CFG[create]="--error --exclude-if-present .nobackup --keep-exclude-tags --exclude-caches --exclude-nodump"
    CMD[verbose]="--verbose --progress"
    CMD[info]="info"
    CMD[create]="create -x"
    CMD[list]="list"
    CMD[mount]="mount --foreground :: /mnt/${run}backup"
    CMD[forget]="prune"
    CMD[compact]="compact"
    VAR[repo]="BORG_REPO"
    VAR[passcmd]="BORG_PASSCOMMAND"
    ;;
  restic)
    CFG[need]="0.16.5"
    CFG[version]="$(restic version | awk '/^restic /{ print $2 }')"
    CFG[pass]="257"
    CFG[create]="--exclude-if-present .nobackup --exclude-caches"
    CMD[verbose]="--verbose"
    CMD[info]="cat config"
    CMD[create]="backup -x"
    CMD[list]="snapshots -c"
    CMD[mount]="mount /mnt/${run}backup"
    CMD[forget]="forget"
    CMD[compact]="prune"
    VAR[repo]="RESTIC_REPOSITORY"
    VAR[passcmd]="RESTIC_PASSWORD_COMMAND"
    ;;
  *)    echo "ERROR: this script does not support backup with \"${run}\""; exit 1;;
esac

usage() {
echo ""
echo "usage: $0 [--server <fqdn> | -<1-9> ] --type <type> | --info | --list | --mount | --export [--verbose]"
cat << EOF

    -t|--type <type>        : set backup type to hourly, daily, weekly, monthly
    -1 up to -9             : backup target server (set in ${run}.conf and 1 is default)
    --server <fqdn>         : backup target server
    -v|--verbose            : more output
    -i|--info               : just do ${run} info
    -l|--list               : just do ${run} list
    -m|--mount              : mount ${run} backup repo to /mnt/${run}backup
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

run_command() {
  if [ -n "${USE}" ]; then
    ( ${SETX} ; ${run} -o ${USE}="${OPT[$USE]}" "$@" )
  else
    ( ${SETX} ; ${run} "$@" )
  fi
  return $?
}

log_command() {
  if [ -n "${USE}" ]; then
    echo "cmd: ${run} -o ${USE}=\"${OPT[$USE]}\" $@" >>/run/${run}backup-list-${CFG_S2D}
  else
    echo "cmd: ${run} $@" >>/run/${run}backup-list-${CFG_S2D}
  fi
}

if [ $# -lt 1 ] ; then
    usage
    exit 1
fi

# version check
ver_ge() { [ "$1" = "`echo -e "$1\n$2" | sort -rV | head -n1`" ]; }
if ver_ge ${CFG[version]} ${CFG[need]} ; then
  [ -n "$debug42" ] && echo "${run} version is ${CFG[version]}, we need at least ${CFG[need]}"
else
  echo "ERROR ${run} version ${CFG[version]} is less than ${CFG[need]}"
  exit 1
fi

# copy default config files
for i in ${run}.conf exclude.pattern include.list ; do
  if [ -f "${FHS}/etc/${i}" ]; then
    : # this is fine we have a config file
  else
    cp "${FHS}/share/config/${i}" "${FHS}/etc/${i}" \
      && echo "INFO: copied ${FHS}/share/config/${i} to ${FHS}/etc/${i}" \
      || exit $?
  fi
done
# check for include and exclude files
for i in include.list exclude.pattern ; do
  if [ ! -f "${FHS}/etc/${run}.${i}" ]; then
    echo "ERROR: ${FHS}/etc/${run}.${i} is missing, maybe symlink it"
    echo "       ln -s ${i} ${FHS}/etc/${run}.${i}"
    exit 1
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
            CFG_NOT_QUIET="${CMD[verbose]}"
            ;;
        -l|--list) shift
            ONLY="${CMD[list]}"
            ;;
        -m|--mount) shift
            ONLY="${CMD[mount]}"
            [ -d "/mnt/${run}backup" ] || mkdir /mnt/${run}backup || exit $?
            # force verbose
            CFG_NOT_QUIET="${CMD[verbose]}"
            ;;
        -e|--export) shift
            ONLY=export
            ;;
        -i|--info) shift
            ONLY="${CMD[info]}"
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
            for i in CFG_DEST ${VAR[repo]} CFG_CREATE CFG_FORGET_HOURLY CFG_FORGET_DAILY CFG_FORGET_WEEKLY CFG_FORGET_MONTHLY CFG_FORGET_YEARLY ; do
                eval $(grep "^${i}_${CFG_NR}=" ${FHS}/etc/${run}.conf | sed -E "s|^${i}_[1-9]=|${i}=|")
                eval CFG_WHAT=\$${i}
                case "$i" in
                    "CFG_DEST")
                        if [ -z "$CFG_WHAT" ]; then
                            echo "ERROR destination host CFG_DEST_${CFG_NR} not defined in ${FHS}/etc/${run}.conf"
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
    eval $(grep "^CFG_DEST_1=" ${FHS}/etc/${run}.conf | sed -E 's|^CFG_DEST_1=|CFG_DEST=|')
fi

# check for the target host
if [ -z "${CFG_DEST}" ]; then
    echo ""
    echo "ERROR backup target host not defined"
    echo "      not as CFG_DEST_1 in ${FHS}/etc/${run}.conf"
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
  borg)   export BORG_REPO=${BORG_REPO:-ssh://z${run}@${CFG_DEST}/~/hosts/${CFG_HOST}} ;;
  restic) export RESTIC_REPOSITORY=${RESTIC_REPOSITORY:-rclone:} ;;
esac

# do we have a password/passphrase
CFG_KEY_PASSWORD="${run}_${CFG_S2D}.pass"
if [ ! -f ${HOME}/.ssh/${CFG_KEY_PASSWORD} ]; then
    echo ""
    echo "ERROR missig ${CFG_KEY_PASSWORD}"
    echo "create with next line"
    echo "head -c ${CFG[pass]} /dev/urandom | base64 -w 0 > ${HOME}/.ssh/${CFG_KEY_PASSWORD} ; chmod 0400 ${HOME}/.ssh/${CFG_KEY_PASSWORD}"
    echo ""
    exit 1
else
    export ${VAR[passcmd]}="cat ${HOME}/.ssh/${CFG_KEY_PASSWORD}"
fi

# is it a ssh repo
eval CFG_REPO=\$${VAR[repo]}
echo "$CFG_REPO" | grep -Eq '^(ssh|sftp):|^rclone:$'
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
        case "${run}" in
            borg)   export BORG_RSH="ssh -o IdentitiesOnly=yes -i ${HOME}/.ssh/${CFG_SSH_KEY}" ;;
            restic)
                if [ "$CFG_REPO" = "rclone:" ]; then
                    # rclone without any remote/path is used for ssh with forced command
                    USE=rclone.program
                    OPT[${USE}]="ssh zrestic@${CFG_DEST} -o IdentitiesOnly=yes -i ${HOME}/.ssh/${CFG_SSH_KEY} forced-command"
                else
                    # extra sftp parameter
                    USE=sftp.command
                    OPT[${USE}]="ssh zrestic@${CFG_DEST} -o IdentitiesOnly=yes -i ${HOME}/.ssh/${CFG_SSH_KEY} -s sftp"
                fi
                ;;
        esac
    fi
fi

# this is used for create commands
CFG_CREATE="${CFG_CREATE:-${CFG[create]}}"

# hourly only runs every 4h in default cron setup
CFG_FORGET_HOURLY=${CFG_FORGET_HOURLY:-13}
CFG_FORGET_DAILY=${CFG_FORGET_DAILY:-8}
CFG_FORGET_WEEKLY=${CFG_FORGET_WEEKLY:-6}
CFG_FORGET_MONTHLY=${CFG_FORGET_MONTHLY:-18}
# only monthly backups will be used as yearly, there is no extra yearly backup type
CFG_FORGET_YEARLY=${CFG_FORGET_YEARLY:-3}


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
    echo "eval \$($0 ${ALL} | grep '^export ')"
    if [ ${#OPT[@]} -gt 0 ]; then
        echo -e "\nAND define a alias like the next line\n"
        echo "alias ${run}='/usr/bin/${run}$(for i in ${!OPT[@]} ; do echo -n " -o ${i}=\"${OPT[$i]}\"" ; done)'"
    fi
    echo ""
    echo "export CFG_S2D=$CFG_S2D"
    show_env | grep ^${run^^} | sed -E 's|^|export |g ; s|=|="| ; s|$|"|g'
    exit 0
elif [ -n "${ONLY}" ]; then
    run_command ${ONLY} ${CFG_NOT_QUIET} "$@"
    exit $?
fi

if [ -z "$CFG_DEST" -o -z "$CFG_HOST" -o -z "$CFG_TYPE" -o -z "$CFG_REPO" ]; then
    echo ""
    echo "ERROR: please make sure all needed variables are defined"
    show_env
    exit 2
fi

# set forget, tag and other options
case "${run}" in
  borg)
    CMD[exclude.file]="--exclude-from ${FHS}/etc/${run}.exclude.pattern"
    CMD[forget.hourly]="--keep-hourly ${CFG_FORGET_HOURLY} -a *.hourly"
    CMD[forget.daily]="--keep-daily ${CFG_FORGET_DAILY} -a *.daily"
    CMD[forget.weekly]="--keep-weekly ${CFG_FORGET_WEEKLY} -a *.weekly"
    CMD[forget.monthly]="--keep-monthly ${CFG_FORGET_MONTHLY} --keep-yearly ${CFG_FORGET_YEARLY} -a *.monthly"
    CMD[tag]="::{now:%Y-%m-%dT%H:%M}.${CFG_TYPE}"
    CMD[extra]=""
    ;;
  restic)
    # dirty workaround for fuse that root cant read
    mount | awk '/ fuse\./{ print $3 }' >/run/${run}backup-exclude-fuse
    CMD[exclude.file]="--exclude-file ${FHS}/etc/${run}.exclude.pattern --exclude-file /run/${run}backup-exclude-fuse"
    CMD[forget.hourly]="--host ${CFG_HOST} --tag hourly --keep-hourly ${CFG_FORGET_HOURLY} --keep-within-hourly $((${CFG_FORGET_HOURLY}*4))h"
    CMD[forget.daily]="--host ${CFG_HOST} --tag daily --keep-daily ${CFG_FORGET_DAILY} --keep-within-daily ${CFG_FORGET_DAILY}d"
    CMD[forget.weekly]="--host ${CFG_HOST} --tag weekly --keep-weekly ${CFG_FORGET_WEEKLY} --keep-within-weekly $((${CFG_FORGET_WEEKLY}*7))d"
    CMD[forget.monthly]="--host ${CFG_HOST} --tag monthly --keep-monthly ${CFG_FORGET_MONTHLY} --keep-within-monthly ${CFG_FORGET_MONTHLY}m --keep-yearly ${CFG_FORGET_YEARLY} --keep-within-yearly ${CFG_FORGET_YEARLY}y"
    CMD[tag]="--host ${CFG_HOST} --tag ${CFG_TYPE}"
    CMD[extra]="${QUIET}"
    ;;
esac

# what type of backup is it
CFG_FORGET="${CMD[forget.${CFG_TYPE}]}"
case "${CFG_TYPE}" in
    hourly)
        # dont run at midnight
        if [ "$(date +%H)" = "00" ]; then exit 0 ; fi
        ;;
    daily)
        # dont run on the 01 day in the month
        if [ "$(date +%d)" = "01" ]; then exit 0 ; fi
        # dont run on monday
        if [ "$(date +%w)" = "1" ]; then exit 0 ; fi
        ;;
    weekly)
        # dont run on the 01 day in the month
        if [ "$(date +%d)" = "01" ]; then exit 0 ; fi
        ;;
    monthly)
        ;;
    *)
        CFG_FORGET=
        ;;
esac

# collecting mountpoint to backup
CFG_MOUNTS=()
for i in $(df --no-sync -lPT -x tmpfs -x devtmpfs | awk '/^\/dev\//''{ print $NF }'); do
  CFG_MOUNTS+=("$i")
done
# build mountpoint list
for include in ${FHS}/etc/${run}.include.list ${FHS}/etc/${run}.include.list.${CFG_TYPE} ; do
  if [ -f "$include" ]; then
    for i in $(egrep -v '^$|^#' "$include"); do
      CFG_MOUNTS+=("$i")
    done
  fi
done


[ -n "$CFG_NOT_QUIET" ] && echo "start ${run} backup type ${CFG_TYPE} for ${CFG_HOST}"

run_command ${CMD[create]} ${CMD[extra]} ${CFG_NOT_QUIET} ${CFG_CREATE} ${CMD[exclude.file]} ${CMD[tag]} ${CFG_MOUNTS[*]}
RUN_EXIT=$?

if [ $RUN_EXIT -gt 1 ]; then
    echo "ERROR: exit code $RUN_EXIT ${run} backup type ${CFG_TYPE} for ${CFG_HOST} ${CFG_MOUNTS[*]}"
else
    env | grep -E "^${run^^}_REPO|^${run^^}_RSH" | sort >/run/${run}backup-list-${CFG_S2D}
    log_command ${CMD[create]} ${CMD[extra]} ${CFG_NOT_QUIET} ${CFG_CREATE} ${CMD[exclude.file]} ${CMD[tag]} ${CFG_MOUNTS[*]}
    if [ -n "${CFG_FORGET}" ]; then
        log_command ${CMD[forget]} ${CMD[extra]} ${CFG_NOT_QUIET} ${CFG_FORGET}
        run_command ${CMD[forget]} ${CMD[extra]} ${CFG_NOT_QUIET} ${CFG_FORGET}
        RUN_EXIT=$?
        if [ $RUN_EXIT -gt 1 ]; then
            [ -n "$CFG_NOT_QUIET" ] && echo "WARN: exit code $RUN_EXIT ${run} ${CMD[forget]} for ${CFG_HOST} (maybe append only repo)"
        elif [ "${CFG_TYPE}" = "monthly" ]; then
            log_command ${CMD[compact]} ${CMD[extra]} ${CFG_NOT_QUIET}
            run_command ${CMD[compact]} ${CMD[extra]} ${CFG_NOT_QUIET}
        fi
    fi
    run_command ${CMD[list]} >>/run/${run}backup-list-${CFG_S2D}
fi

[ -n "$CFG_NOT_QUIET" ] && echo -e "\ndone ${CFG_TYPE} ${run} backup for ${CFG_HOST}\n"
