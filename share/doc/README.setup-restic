
## to finish setup


#### on the source host set destination host 1
set CFG_DEST_1 in /opt/scripts-backup/etc/restic.conf
if needed set optional parameter *_1=
you can setup up to 9 target servers, but you need a cron jobs for every target server

#### on the source host create key and password
follow the instructions suggested for
password an key creation when calling the following line 2 times
```
/opt/scripts-backup/bin/resticbackup.sh -1 -i
```


#### on the target host
```
yum install rclone

# one time setup on the restic server
# if /home/zrestic is the place where you want the backups
DSTDIR=/home/zrestic
IDZRESTIC=2506
groupadd -g ${IDZRESTIC} zrestic
useradd -u ${IDZRESTIC} -g zrestic -M -d ${DSTDIR} zrestic
mkdir -p ${DSTDIR}/.ssh ${DSTDIR}/repos
chmod 0750 ${DSTDIR} ${DSTDIR}/repos ; chown root:zrestic ${DSTDIR} ${DSTDIR}/repos
chmod 0500 ${DSTDIR}/.ssh ; chown zrestic:zrestic ${DSTDIR}/.ssh
touch ${DSTDIR}/.ssh/authorized_keys

# setup for every repo
DSTREPO=foobar
mkdir ${DSTDIR}/repos/${DSTREPO}
chmod 0750 ${DSTDIR}/repos/${DSTREPO} ; chown zrestic:zrestic ${DSTDIR}/repos/${DSTREPO}
# write example to authorized_keys
echo "# example # from=\"<your source ip>\",command=\"rclone serve restic --stdio ./repos/${DSTREPO}\",restrict ssh-ed25519 AAAA.... your full key here ...." >>${DSTDIR}/.ssh/authorized_keys
```
put in ${DSTDIR}/.ssh/authorized_keys
the public key created before as follow
command="rclone serve restic --stdio ./repos/${DSTREPO}",restrict ssh-ed25519 AAAA.... your full key here ....
or with source address
from="<your source ip>",command="rclone serve restic --stdio ./repos/${DSTREPO}",restrict ssh-ed25519 AAAA.... your full key here ....


#### on the source host initialize the archive
```
# to source the config
eval $(/opt/scripts-backup/bin/resticbackup.sh -1 -e | grep '^export ')
eval $(/opt/scripts-backup/bin/resticbackup.sh -1 -e | grep '^alias ')
# now initialise repo
restic init
# logout from the source server
# (to get rid of sourced RESTIC_* variables)
# login again
# check with
/opt/scripts-backup/bin/resticbackup.sh -1 -i
# if it shows a valid archive your are done with this part
```


#### on the source host do your first backup
```
# adjust /opt/scripts-backup/etc/restic.exclude.pattern
# adjust /opt/scripts-backup/etc/restic.include.list
# and now we do a backup of type hourly
/opt/scripts-backup/bin/resticbackup.sh -1 -t hourly -v
```


## BACKUP !!!!!!!!! key and passphrase ##
## on the source host BACKUP the passphrase
```
# the passpharse you created is in /root/.ssh/restic_<source>2<destination>.pass
# now save all the files for this backup pair
scp /root/.ssh/restic_${CFG_S2D}* <where ever you want it to be save>
```


#### on the source host set up cron
this example is just for host 1
you need cron jobs for every target host (if more then 1)
```
cp /opt/scripts-backup/share/doc/cron.example-restic /etc/cron.d/resticbackup
# configure email address in /etc/cron.d/resticbackup
```


#### on the source host daily use
if you want to explore restic your self set the config with
```
eval $(/opt/scripts-backup/bin/resticbackup.sh -1 -e | grep '^export ')
eval $(/opt/scripts-backup/bin/resticbackup.sh -1 -e | grep '^alias ')
# and now you can use restic with already configured environment
restic stats
restic snapshots -c
# dont forget to exit the shell to get rid of the borg config
```


bofh42
have fun
