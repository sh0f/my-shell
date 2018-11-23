#!/bin/bash
timedatectl set-timezone Asia/Shanghai
update_engine_client -update
[ -n "$(grep ^REBOOT_STRATEGY /etc/coreos/update.conf)" ] && sed -i "s@^REBOOT_STRATEGY.*@REBOOT_STRATEGY=off@" /etc/coreos/update.conf || echo 'REBOOT_STRATEGY=off' >>/etc/coreos/update.conf
systemctl restart update-engine
[ ! -d /opt/bin ] && mkdir -p /opt/bin
wget -O /opt/bin/docker-compose https://github.com/docker/compose/releases/download/1.23.1/docker-compose-Linux-x86_64
cat >/opt/bin/lrzsz <<EOF
#!/bin/bash
docker run -ti --rm -v /root/upload:/upload sh0f/lrzsz
EOF
cat >/opt/bin/update-window.sh <<EOF
#!/bin/bash
# If etcd is active, this uses locksmith. Otherwise, it randomly delays. 
delay=\$(/usr/bin/expr \$RANDOM % 3600 )
rebootflag='NEED_REBOOT'
if update_engine_client -status | grep \$rebootflag; then
    echo -n "etcd is "
    if systemctl is-active etcd; then
        echo "Update reboot with locksmithctl."
        locksmithctl reboot
    else
        echo "Update reboot in \$delay seconds."
        sleep \$delay
        reboot
    fi
fi
EOF
chmod +x /opt/bin/docker-compose
chmod +x /opt/bin/lrzsz
chmod +x /opt/bin/update-window.sh
cat >/etc/systemd/system/update-window.service <<EOF
[Unit]
Description=Reboot if an update has been downloaded
[Service]
ExecStart=/opt/bin/update-window.sh
EOF
cat >/etc/systemd/system/update-window.timer <<EOF
[Unit]
Description=Reboot timer
[Timer]
OnCalendar=*-*-* 05,06:00,30:00
[Install]
WantedBy=multi-user.target
EOF
cat >/etc/systemd/system/disable-transparent-huge-pages.service <<EOF
[Unit]
Description=Disable Transparent Huge Pages
[Service]
Type=oneshot
ExecStart=/usr/bin/sh -c "/usr/bin/echo "never" | tee /sys/kernel/mm/transparent_hugepage/enabled"
ExecStart=/usr/bin/sh -c "/usr/bin/echo "never" | tee /sys/kernel/mm/transparent_hugepage/defrag"
[Install]
WantedBy=multi-user.target
EOF
systemctl start update-window.timer
systemctl start disable-transparent-huge-pages
systemctl enable update-window.timer
systemctl enable docker
systemctl enable disable-transparent-huge-pages
echo 'vm.overcommit_memory=1' >/etc/sysctl.d/overcommit.conf
echo 'tcp_bbr' >/etc/modules-load.d/bbr.conf
echo -e 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr' >/etc/sysctl.d/bbr.conf
echo 'net.ipv4.tcp_fastopen=3' >/etc/sysctl.d/fastopen.conf
[ -z "$(grep ^SystemMaxUse /etc/systemd/journald.conf)" ] && echo 'SystemMaxUse=10M' >>/etc/systemd/journald.conf || sed -i "s@^SystemMaxUse.*@SystemMaxUse=10M@" /etc/systemd/journald.conf
[ ! -d /root/upload ] && mkdir /root/upload
