activating the init state files service

```
cp /opt/scripts-backup/share/systemd/scripts-backup-init-state.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now scripts-backup-init-state.service
```
