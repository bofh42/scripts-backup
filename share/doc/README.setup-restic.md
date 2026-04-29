
## to finish setup


#### on the source host set destination host 1
```
# git clone setup (not packaged)
cd /opt
git clone https://github.com/bofh42/scripts-backup
cd /opt/scripts-backup/
mkdir etc/
cp share/config/restic.conf etc/
```
set CFG_DEST_1 in /opt/scripts-backup/etc/restic.conf  
if needed set optional parameter *_1=  
you can setup up to 9 target servers, but you need a cron jobs for every target server

#### on the source host create key and password
follow the instructions suggested for
password an key creation when calling the following line most likely 4 times
```
/opt/scripts-backup/bin/resticbackup.sh -1 -e
```


#### on the target host
```
dnf install rclone

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

# setup for every new repo (shared repo only the authorized_keys)
DSTREPO=foobar
mkdir ${DSTDIR}/repos/${DSTREPO}
chmod 0750 ${DSTDIR}/repos/${DSTREPO} ; chown zrestic:zrestic ${DSTDIR}/repos/${DSTREPO}
# write example to authorized_keys
echo "# example # from=\"<your source ip>\",command=\"rclone serve restic --stdio ./repos/${DSTREPO}\",restrict ssh-ed25519 AAAA.... your full key here ...." >>${DSTDIR}/.ssh/authorized_keys
```
Edit your .ssh/authorized_keys on the target host with the correct data.


#### new repo -> initialize, shared repo -> add key
```
# to source the config
# for a new repo on the new source host
# for a shared repo an a already working sourcve host
eval $(/opt/scripts-backup/bin/resticbackup.sh -1 -e | grep '^export ')
eval $(/opt/scripts-backup/bin/resticbackup.sh -1 -e | grep '^alias ')
# for a shared repo you need to add the created pass to the repo for this host
# go to a already working host (you neew the new  host pass file)
restic key add --new-password-file restic_<new host>2<target host>.pass --host <new host>
restic key list
# if not a shared repo you need to initialise the repo
restic init
# logout from the source server
# (to get rid of sourced RESTIC_* variables)
# login again
# check with (for shared repo use -l instead -i)
/opt/scripts-backup/bin/resticbackup.sh -1 -i
# if it shows a valid archive your are done with this part
```


## BACKUP !!!!!!!!! key and passphrase ##
## on the source host BACKUP the passphrase
```
# the passpharse you created is in /root/.ssh/restic_<source>2<destination>.pass
# now save all the files for this backup
scp /root/.ssh/restic_* <where ever you want it to be save>
```


#### on the source host do your first backup
```
# adjust /opt/scripts-backup/etc/restic.exclude.pattern
# adjust /opt/scripts-backup/etc/restic.include.list
# and now we do a backup of type hourly
/opt/scripts-backup/bin/resticbackup.sh -1 -t hourly -v
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
