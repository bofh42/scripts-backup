
## to finish setup

#### on the source host set destination host 1
```
# git clone setup (not packaged)
cd /opt
git clone https://github.com/bofh42/scripts-backup
cd /opt/scripts-backup/
mkdir etc/
cp share/config/borg.conf etc/
```
set CFG_DEST_1 in /opt/scripts-backup/etc/borg.conf
if needed set optional parameter *_1=
you can setup up to 9 target servers, but you need a cron jobs for every target server


#### on the source host create config, key and password
follow the instructions suggested for config, password
and key creation when calling the following line most likely 4 times
```
/opt/scripts-backup/bin/borgbackup.sh -1 -e
```

#### on the target host
```
dnf install /usr/bin/borg
# one time setup on the borg server
# if /data/borg is the place where you want the backups
DSTDIR=/data/borg
IDZBORG=2505
groupadd -g ${IDZBORG} zborg
useradd -u ${IDZBORG} -g zborg -M -d ${DSTDIR} zborg
mkdir -p ${DSTDIR}/.ssh ${DSTDIR}/hosts
chmod 0750 ${DSTDIR} ${DSTDIR}/hosts ; chown root:zborg ${DSTDIR} ${DSTDIR}/hosts
chmod 0500 ${DSTDIR}/.ssh ; chown zborg:zborg ${DSTDIR}/.ssh
touch ${DSTDIR}/.ssh/authorized_keys
# setup for every source host
SRCHOST=foobar
mkdir ${DSTDIR}/hosts/${SRCHOST}
chmod 0750 ${DSTDIR}/hosts/${SRCHOST} ; chown zborg:zborg ${DSTDIR}/hosts/${SRCHOST}
# write 2 examples to authorized_keys
echo "# example # command=\"/usr/bin/borg serve --restrict-to-path ${DSTDIR}/hosts/${SRCHOST}\",restrict ssh-ed25519 AAAA.... your full key here ...." >>${DSTDIR}/.ssh/authorized_keys
echo "# example # from=\"<your source ip>\",command=\"/usr/bin/borg serve --restrict-to-path ${DSTDIR}/hosts/${SRCHOST}\",restrict ssh-ed25519 AAAA.... your full key here ...." >>${DSTDIR}/.ssh/authorized_keys
```
Edit your .ssh/authorized_keys on the target host with the correct data.


#### on the source host initialize the archive
check out [borg init](https://borgbackup.readthedocs.io/en/stable/usage/init.html)
```
# to source the config
eval $(/opt/scripts-backup/bin/borgbackup.sh -1 -e | grep -Ev '^$|^#|^eval')
# now initialise repo with the encryption key on the backup server
borg init --encryption=repokey-blake2 ::
# or  initialise repo with the encryption key on the local system
borg init --encryption=keyfile-blake2 ::
# export the key AND save it
borg key export :: /root/.ssh/borg_${CFG_S2D}.key
# logout from the source server
# (to get rid of sourced BORG_* variables)
# login again
# check with
/opt/scripts-backup/bin/borgbackup.sh -1 -i
# if it shows a valid archive your are done with this part
```

## BACKUP !!!!!!!!! key and passphrase ##
## on the source host BACKUP the passphrase an the key
## you NEED the passpharse and the key to restore
```
# now save all the files for this backup
# /root/.ssh/borg_<source>2<destination>*
scp /root/.ssh/borg_* <where ever you want it to be save>
```


#### on the source host do your first backup
```
# adjust /opt/scripts-backup/etc/exclude.pattern
# adjust /opt/scripts-backup/etc/include.list
# and now we do a backup of type hourly
/opt/scripts-backup/bin/borgbackup.sh -1 -t hourly -v
```


#### on the source host set up cron
this example is just for host 1
you need cron jobs for every target host (if more then 1)
```
cp /opt/scripts-backup/share/doc/cron.example-borg /etc/cron.d/borgbackup
# configure email address in /etc/cron.d/borgbackup
```


#### on the source host daily use
if you want to explore borg your self set the config with
```
/opt/scripts-backup/bin/borgbackup.sh -1 -e
# and now you can use borg with already configured environment
env | grep -E '^BORG|^CFG_'
borg info
borg list
# dont forget to exit the shell to get rid of the borg config
```


bofh42
have fun
