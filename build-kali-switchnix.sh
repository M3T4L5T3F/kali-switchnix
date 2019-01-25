#!/bin/bash
### Build a Kali Linux filesystem image for Nintendo Switch
if [ "$1" == "--help" ]; then
    echo "Usage $0 [--all]"
    exit 1
fi

# Sources:
# https://wiki.debian.org/Debootstrap
# https://wiki.debian.org/EmDebian/CrossDebootstrap
# https://wiki.debian.org/Arm64Qemu
# https://github.com/cmsj/nintendo-switch-ubuntu-builder
# https://github.com/offensive-security/kali-arm-build-scripts/blob/master/odroid-c2.sh

set -e

### settings
os=kali
arch=arm64
suite=kali-rolling
apt_mirror='http://http.kali.org/kali'
chroot_dir="${1:-/var/chroot/${os}_${arch}_$suite}"
tarball="${2:-${os}_${arch}_${suite}.tar.gz}"

### make sure that the required tools are installed
echo "Installing dependencies..."
apt-get install -qy --reinstall debootstrap qemu-user-static

### Clear chroot_dir to make sure the rebuild is clean
# This is tp prevent a corrupted chroot dir to break repeated failed
# rebuilds that have been observed at the deboostrap minbase stage
echo "Removing existing chroot..."
rm -rf "$chroot_dir"
rm -f "${tarball}"

### install a minbase system with debootstrap
echo "Creating base image chroot, first stage..."
export DEBIAN_FRONTEND=noninteractive

debootstrap --verbose --foreign --keyring=/usr/share/keyrings/kali-archive-keyring.gpg --include=kali-archive-keyring --arch=$arch $suite "$chroot_dir" $apt_mirror

echo "Creating base image chroot, second stage..."
cp /usr/bin/qemu-aarch64-static "$chroot_dir/usr/bin/"
LC_ALL=C LANGUAGE=C LANG=C chroot "$chroot_dir" /debootstrap/debootstrap --second-stage
LC_ALL=C LANGUAGE=C LANG=C chroot "$chroot_dir" dpkg --configure -a

### set the hostname
echo "kali-switch" > "$chroot_dir/etc/hostname"

### update the list of package sources
cat <<EOF > "$chroot_dir/etc/apt/sources.list"
deb $apt_mirror $suite main contrib non-free
#deb-src $apt_mirror $suite main contrib non-free
EOF

cat << EOF > "$chroot_dir/etc/hosts"
127.0.0.1       kali-switch    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

# prevent init scripts from running during install/update
echo '#!/bin/sh' > "$chroot_dir/usr/sbin/policy-rc.d"
echo 'exit 101' >> "$chroot_dir/usr/sbin/policy-rc.d"
chmod +x "$chroot_dir/usr/sbin/policy-rc.d"

# force dpkg not to call sync() after package extraction (speeding up installs)
echo 'force-unsafe-io' > "$chroot_dir/etc/dpkg/dpkg.cfg.d/swikali-apt-speedup"

# _keep_ us lean by effectively running "apt-get clean" after every install
echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' > "$chroot_dir/etc/apt/apt.conf.d/swikali-clean"
echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' >> "$chroot_dir/etc/apt/apt.conf.d/swikali-clean"
echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' >> "$chroot_dir/etc/apt/apt.conf.d/swikali-clean"

# remove apt-cache translations for fast "apt-get update"
# echo 'Acquire::Languages "none";' > "$chroot_dir/etc/apt/apt.conf.d/swikali-no-languages"

# store Apt lists files gzipped on-disk for smaller size
echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' > "$chroot_dir/etc/apt/apt.conf.d/swikali-gzip-indexes"

# man-db does not work via qemu-user
chroot "$chroot_dir" dpkg-divert --local --rename --add /usr/bin/mandb
chroot "$chroot_dir" ln -sf /bin/true /usr/bin/mandb


mount -o bind /proc "$chroot_dir/proc"

### install kali

arm="abootimg cgpt fake-hwclock ntpdate u-boot-tools vboot-utils"
base="apt-transport-https apt-utils console-setup e2fsprogs firmware-linux firmware-realtek firmware-atheros firmware-libertas firmware-brcm80211 ifupdown initramfs-tools iw kali-defaults man-db mlocate netcat-traditional net-tools parted psmisc rfkill screen snmpd snmp sudo tftp tmux unrar usbutils vim wget zerofree"
desktop="kali-menu fonts-croscore fonts-crosextra-caladea fonts-crosextra-carlito gnome-theme-kali gtk3-engines-xfce kali-desktop-xfce kali-root-login lightdm network-manager network-manager-gnome accountsservice florence at-spi2-core"

tools="aircrack-ng crunch cewl dnsrecon dnsutils ethtool exploitdb hydra john libnfc-bin medusa metasploit-framework mfoc ncrack nmap passing-the-hash proxychains recon-ng sqlmap tcpdump theharvester tor tshark usbutils pciutils xinput xserver-xorg-input-libinput xserver-xorg-video-nouveau libgl1-mesa-dri bluez driconf whois windows-binaries winexe wpscan wireshark"
services="apache2 atftpd openssh-server openvpn tightvncserver"
extras="libnss-systemd xfce4-goodies xfce4-terminal wpasupplicant"

packages="${arm} ${base} ${services} ${extras}"

cat << EOF > "$chroot_dir/debconf.set"
console-common console-data/keymap/policy select Select keymap from full list
console-common console-data/keymap/full select en-latin1-nodeadkeys
EOF

chroot "$chroot_dir" apt-get update
chroot "$chroot_dir" apt-get --yes --allow-change-held-packages install locales-all
chroot "$chroot_dir" debconf-set-selections /debconf.set
chroot "$chroot_dir" rm -f /debconf.set
chroot "$chroot_dir" apt-get update
chroot "$chroot_dir" apt-get -y install git-core binutils ca-certificates initramfs-tools u-boot-tools
chroot "$chroot_dir" apt-get -y install locales console-common less nano git
chroot "$chroot_dir" rm -f /etc/udev/rules.d/70-persistent-net.rules
chroot "$chroot_dir" apt-get --yes --allow-change-held-packages install ${packages} || chroot "$chroot_dir" apt-get --yes --fix-broken install
chroot "$chroot_dir" apt-get --yes --allow-change-held-packages install ${packages} || chroot "$chroot_dir" apt-get --yes --fix-broken install
chroot "$chroot_dir" apt-get --yes --allow-change-held-packages install ${desktop} ${tools} || chroot "$chroot_dir" apt-get --yes --fix-broken install
chroot "$chroot_dir" apt-get --yes --allow-change-held-packages install ${desktop} ${tools} || chroot "$chroot_dir" apt-get --yes --fix-broken install
chroot "$chroot_dir" apt-get --yes --allow-change-held-packages dist-upgrade
chroot "$chroot_dir" apt-get --yes --allow-change-held-packages autoremove

# Because copying in authorized_keys is hard for people to do, let's make the
# image insecure and enable root login with a password.
echo "Making the image insecure"
chroot "$chroot_dir" sed -i -e 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Copy bashrc
chroot "$chroot_dir" cp /etc/skel/.bashrc /root/.bashrc

# Configuration: DNS
cat <<EOF > "$chroot_dir/etc/resolv.conf"
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

#Configuration: network interfaces
mkdir -p "$chroot_dir/etc/network/"
cat << EOF > "$chroot_dir/etc/network/interfaces"
auto lo
iface lo inet loopback

auto wlan0
iface wlan0 inet dhcp
EOF

mkdir -p "$chroot_dir/lib/systemd/system/"
cat << 'EOF' > "$chroot_dir/lib/systemd/system/regenerate_ssh_host_keys.service"
[Unit]
Description=Regenerate SSH host keys
Before=ssh.service
[Service]
Type=oneshot
ExecStartPre=-/bin/dd if=/dev/hwrng of=/dev/urandom count=1 bs=4096
ExecStartPre=-/bin/sh -c "/bin/rm -f -v /etc/ssh/ssh_host_*_key*"
ExecStart=/usr/bin/ssh-keygen -A -v
ExecStartPost=/bin/sh -c "for i in /etc/ssh/ssh_host_*_key*; do actualsize=$(wc -c <\"$i\") ;if [ $actualsize -eq 0 ]; then echo size is 0 bytes ; exit 1 ; fi ; done ; /bin/systemctl disable regenerate_ssh_host_keys"
[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$chroot_dir/lib/systemd/system/regenerate_ssh_host_keys.service"

# Configuration: user (username: switch password: switch)
chroot "$chroot_dir" useradd -m -s /bin/bash -d /home/switch -p Q4OiRew2o/3Fk switch
if ! [ -d "$chroot_dir/home/switch" ]; then
  mkdir -p "$chroot_dir/home/switch"
  chown 1000:1000 "$chroot_dir/home/switch"
fi
chroot "$chroot_dir" adduser switch sudo

# Configuration: touchscreen config
cat <<EOF > "$chroot_dir/etc/udev/rules.d/01-nintendo-switch-libinput-matrix.rules"
ATTRS{name}=="stmfts", ENV{LIBINPUT_CALIBRATION_MATRIX}="0 1 0 -1 0 1"
EOF

mkdir -p "$chroot_dir/home/switch/.config"
cat <<EOF > "$chroot_dir/home/switch/.config/monitors.xml"
<monitors version="2">
  <configuration>
    <logicalmonitor>
      <x>0</x>
      <y>0</y>
      <scale>1</scale>
      <primary>yes</primary>
      <transform>
        <rotation>none</rotation>
        <flipped>no</flipped>
      </transform>
      <monitor>
        <monitorspec>
          <connector>DSI-1</connector>
          <vendor>unknown</vendor>
          <product>unknown</product>
          <serial>unknown</serial>
        </monitorspec>
        <mode>
          <width>1280</width>
          <height>720</height>
          <rate>60</rate>
        </mode>
      </monitor>
    </logicalmonitor>
  </configuration>
</monitors>
EOF
chroot "$chroot_dir" chown -R 1000:1000 /home/switch/.config

mkdir -p "$chroot_dir/var/lib/gdm3/.config"
cp "$chroot_dir/home/switch/.config/monitors.xml" "$chroot_dir/var/lib/gdm3/.config"
#chroot "$chroot_dir" chown -R gdm:gdm /var/lib/gdm3/.config

# Configuration: disable crazy ambient backlight
mkdir -p "$chroot_dir/etc/dconf/db/local.d"
cat <<EOF > "$chroot_dir/etc/dconf/db/local.d/01-nintendo-switch-disable-ambient-backlight.conf"
[org/gnome/settings-daemon/plugins/power]
ambient-enabled=false
EOF

# Configuration: Add missing firmware definition file for Broadcom driver
# https://bugzilla.kernel.org/show_bug.cgi?id=185661
cat <<EOF > "$chroot_dir/lib/firmware/brcm/brcmfmac4356-pcie.txt"
# Sample variables file for BCM94356Z NGFF 22x30mm iPA, iLNA board with PCIe for production package
NVRAMRev=\$Rev: 492104 $
#4356 chip = 4354 A2 chip
sromrev=11
boardrev=0x1102
boardtype=0x073e
boardflags=0x02400201
#0x2000 enable 2G spur WAR
boardflags2=0x00802000
boardflags3=0x0000000a
#boardflags3 0x00000100 /* to read swctrlmap from nvram*/
#define BFL3_5G_SPUR_WAR   0x00080000   /* enable spur WAR in 5G band */
#define BFL3_AvVim   0x40000000   /* load AvVim from nvram */
macaddr=00:90:4c:1a:10:01
ccode=0x5854
regrev=205
antswitch=0
pdgain5g=4
pdgain2g=4
tworangetssi2g=0
tworangetssi5g=0
paprdis=0
femctrl=10
vendid=0x14e4
devid=0x43ec
manfid=0x2d0
#prodid=0x052e
nocrc=1
otpimagesize=502
xtalfreq=37400
rxgains2gelnagaina0=0
rxgains2gtrisoa0=7
rxgains2gtrelnabypa0=0
rxgains5gelnagaina0=0
rxgains5gtrisoa0=11
rxgains5gtrelnabypa0=0
rxgains5gmelnagaina0=0
rxgains5gmtrisoa0=13
rxgains5gmtrelnabypa0=0
rxgains5ghelnagaina0=0
rxgains5ghtrisoa0=12
rxgains5ghtrelnabypa0=0
rxgains2gelnagaina1=0
rxgains2gtrisoa1=7
rxgains2gtrelnabypa1=0
rxgains5gelnagaina1=0
rxgains5gtrisoa1=10
rxgains5gtrelnabypa1=0
rxgains5gmelnagaina1=0
rxgains5gmtrisoa1=11
rxgains5gmtrelnabypa1=0
rxgains5ghelnagaina1=0
rxgains5ghtrisoa1=11
rxgains5ghtrelnabypa1=0
rxchain=3
txchain=3
aa2g=3
aa5g=3
agbg0=2
agbg1=2
aga0=2
aga1=2
tssipos2g=1
extpagain2g=2
tssipos5g=1
extpagain5g=2
tempthresh=255
tempoffset=255
rawtempsense=0x1ff
pa2ga0=-147,6192,-705
pa2ga1=-161,6041,-701
pa5ga0=-194,6069,-739,-188,6137,-743,-185,5931,-725,-171,5898,-715
pa5ga1=-190,6248,-757,-190,6275,-759,-190,6225,-757,-184,6131,-746
subband5gver=0x4
pdoffsetcckma0=0x4
pdoffsetcckma1=0x4
pdoffset40ma0=0x0000
pdoffset80ma0=0x0000
pdoffset40ma1=0x0000
pdoffset80ma1=0x0000
maxp2ga0=76
maxp5ga0=74,74,74,74
maxp2ga1=76
maxp5ga1=74,74,74,74
cckbw202gpo=0x0000
cckbw20ul2gpo=0x0000
mcsbw202gpo=0x99644422
mcsbw402gpo=0x99644422
dot11agofdmhrbw202gpo=0x6666
ofdmlrbw202gpo=0x0022
mcsbw205glpo=0x88766663
mcsbw405glpo=0x88666663
mcsbw805glpo=0xbb666665
mcsbw205gmpo=0xd8666663
mcsbw405gmpo=0x88666663
mcsbw805gmpo=0xcc666665
mcsbw205ghpo=0xdc666663
mcsbw405ghpo=0xaa666663
mcsbw805ghpo=0xdd666665
mcslr5glpo=0x0000
mcslr5gmpo=0x0000
mcslr5ghpo=0x0000
sb20in40hrpo=0x0
sb20in80and160hr5glpo=0x0
sb40and80hr5glpo=0x0
sb20in80and160hr5gmpo=0x0
sb40and80hr5gmpo=0x0
sb20in80and160hr5ghpo=0x0
sb40and80hr5ghpo=0x0
sb20in40lrpo=0x0
sb20in80and160lr5glpo=0x0
sb40and80lr5glpo=0x0
sb20in80and160lr5gmpo=0x0
sb40and80lr5gmpo=0x0
sb20in80and160lr5ghpo=0x0
sb40and80lr5ghpo=0x0
dot11agduphrpo=0x0
dot11agduplrpo=0x0
phycal_tempdelta=255
temps_period=15
temps_hysteresis=15
rssicorrnorm_c0=4,4
rssicorrnorm_c1=4,4
rssicorrnorm5g_c0=1,2,3,1,2,3,6,6,8,6,6,8
rssicorrnorm5g_c1=1,2,3,2,2,2,7,7,8,7,7,8
EOF

# Configuration: Configure GPU clock automatically based on power source state
cat <<'EOF' > "$chroot_dir/etc/udev/rules.d/02-nintendo-switch-gpu-power.rules"
SUBSYSTEM=="power_supply", ENV{POWER_SUPPLY_NAME}=="bq24190-charger", ENV{POWER_SUPPLY_ONLINE}=="1", RUN+="/usr/local/bin/gpu_power.sh high"
SUBSYSTEM=="power_supply", ENV{POWER_SUPPLY_NAME}=="bq24190-charger", ENV{POWER_SUPPLY_ONLINE}=="0", RUN+="/usr/local/bin/gpu_power.sh medium"
EOF

cat <<'EOF' > "$chroot_dir/usr/local/bin/gpu_power.sh"
#!/bin/bash

VALUE="04"

case $1 in
  "--help")
    echo "Usage: $0 [low|medium|high]"
    echo "  low    - underclock GPU (153MHz)"
    echo "  medium - normal GPU speed (307MHz)"
    echo "  high   - docked GPU speed (768MHz)"
    exit 0
    ;;
  "low")
    VALUE="02"
    ;;
  "medium")
    VALUE="04"
    ;;
  "high")
    VALUE="0a"
    ;;
  *)
    echo "Your input was not recognised, assuming 'medium'"
    ;;
esac

pstate_file=$(find /sys/kernel/debug/dri/ -name pstate | head -1)
echo "${VALUE}" > $pstate_file
EOF
chmod +x "$chroot_dir/usr/local/bin/gpu_power.sh"

cat <<'EOF' > "$chroot_dir/etc/rc.local"
#!/bin/sh
/sbin/udevadm trigger -s power_supply
EOF
chmod +x "$chroot_dir/etc/rc.local"

### generate at least a basic locale
chroot "$chroot_dir" locale-gen en_GB.UTF-8 en_US.UTF-8

# Cleanup: man-db does not work via qemu-user
chroot "$chroot_dir" rm /usr/bin/mandb
chroot "$chroot_dir" dpkg-divert --local --rename --remove /usr/bin/mandb

### cleanup and unmount /proc
chroot "$chroot_dir" apt-get autoclean
chroot "$chroot_dir" apt-get clean
chroot "$chroot_dir" apt-get autoremove
umount "$chroot_dir/proc"

### create a tar archive from the chroot directory
TAROPTS="cf"
if [[ "${tarball}" == *z ]]; then
    TAROPTS="${TAROPTS}z"
fi
tar ${TAROPTS} "${tarball}" -C "$chroot_dir" .

# ### cleanup
#rm $os_$arch_$suite.tar.gz
#rm -rf "$chroot_dir"

echo "Finished building kali switch rootfs."