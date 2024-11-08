#!/bin/bash
set -e  # Azonnali kilépés, ha egy parancs nem nullával tér vissza
set -x  # Hibakeresés engedélyezése, a végrehajtott parancsok megjelenítéséhez

# Frissítsük a csomaglistát
PATH=$PATH:"/sbin"
apt-get update -y

# Telepítsük a szükséges csomagokat
DEBIAN_FRONTEND=noninteractive apt-get install -y ufw ssh nmap apache2 libapache2-mod-php mariadb-server phpmyadmin curl mosquitto mosquitto-clients nodejs npm mc mdadm nfs-kernel-server samba samba-common-bin

# Node-RED telepítése (without --unsafe-perm flag)
npm install -g node-red@latest

# VirtualBox telepítése Oracle Repositoryből
# echo "deb http://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib" | tee /etc/apt/sources.list.d/virtualbox.list
# wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | apt-key add -
# apt-get update -y
# apt-get install -y virtualbox-6.1

# Node-RED unit file létrehozása
cat <<EOF > /etc/systemd/system/nodered.service
[Unit]
Description=Node-RED graphical event wiring tool
Wants=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=/home/$(whoami)/.node-red
ExecStart=/usr/bin/env node-red-pi --max-old-space-size=256
Restart=always
Environment="NODE_OPTIONS=--max-old-space-size=256"
# Nice options
Nice=10
EnvironmentFile=-/etc/nodered/.env
# Make available to all devices
SyslogIdentifier=Node-RED
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

# Node-RED indítása
systemctl daemon-reload
systemctl enable nodered.service
systemctl start nodered.service

# Kérem, várjon néhány másodpercet, amíg minden szolgáltatás elindul...
echo "Kérem, várjon néhány másodpercet, amíg minden szolgáltatás elindul..."
sleep 5

# Ellenőrizzük a telepített szolgáltatások állapotát
echo "Telepített szolgáltatások állapota:"
all_services_ok=true
for service in ssh apache2 mariadb mosquitto nodered nfs-kernel-server samba; do
    echo -n "$service: "
    if systemctl is-active --quiet $service; then
        echo "fut"
    else
        echo "nem fut"
        all_services_ok=false
    fi
done

# NFS konfiguráció - megosztott könyvtár létrehozása
echo "NFS fájlmegosztás beállítása..."

# Készítsünk egy megosztott könyvtárat
mkdir -p /mnt/nfs_share

# A /etc/exports fájlban hozzáadjuk a megosztásokat, biztonságos IP-címekre korlátozva
# Itt csak a 192.168.1.0/24 alhálózat gépei férhetnek hozzá
echo "/mnt/nfs_share 192.168.1.0/24(rw,sync,no_subtree_check)" >> /etc/exports

# Az NFS szolgáltatás újraindítása, hogy a beállítások érvényesüljenek
exportfs -a
systemctl restart nfs-kernel-server

# Samba megosztás konfigurálása
echo "Samba fájlmegosztás beállítása..."

# Samba konfigurálása
mkdir -p /srv/samba/share

# Samba konfiguráció hozzáadása
cat <<EOF >> /etc/samba/smb.conf

[share]
   path = /srv/samba/share
   browseable = yes
   read only = no
   guest ok = yes
   force user = nobody
   force group = nogroup
EOF

# A Samba szolgáltatás újraindítása
systemctl restart smbd
systemctl enable smbd

# Ellenőrző üzenet a telepítés után
if $all_services_ok; then
    echo "Minden szolgáltatás sikeresen telepítve és fut."
else
    echo "Néhány szolgáltatás nem fut. Kérjük, ellenőrizze a hibaüzeneteket és próbálja újra."
fi

echo "A telepítés sikeresen befejeződött!"
