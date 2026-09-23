#!/usr/bin/bash
set -euo pipefail

IMAGE=ghcr.io/louisbl/uranicorn
KEY=/etc/pki/containers/uranicorn.pub

die() { echo "ERROR: $*" >&2; exit 1; }
rpms() { find /tmp/akmods /tmp/akmods-nvidia -name "$1" | awk -F/ '!seen[$NF]++'; }

grep -q 'BEGIN PUBLIC KEY' "$KEY" || die "cosign.pub is a placeholder"

dnf -y remove \
    firefox firefox-langpacks opensc \
    open-vm-tools open-vm-tools-desktop hyperv-daemons qemu-guest-agent \
    spice-vdagent spice-webdavd virtualbox-guest-additions \
    sddm sddm-wayland-sway lxqt-policykit dunst rofi rofi-themes \
    orca brltty speech-dispatcher \
    ibus-anthy ibus-hangul ibus-libpinyin ibus-m17n ibus-chewing ibus-typing-booster \
    gamemode sos fpaste tuned-switcher b43-openfwwf b43-fwcutter \
    fedora-workstation-repositories fedora-third-party fedora-chromium-config fedora-bookmarks

dnf -y install --setopt=install_weak_deps=False \
    niri xwayland-satellite xdg-desktop-portal-gnome fuzzel foot foot-terminfo waybar \
    mako swaybg swayidle swaylock playerctl brightnessctl tuigreet wl-mirror mate-polkit \
    xdg-native-messaging-proxy keepassxc fish vim-enhanced parted tcpdump just \
    clamav clamav-freshclam clamd distrobox crun-krun \
    libvirt-daemon-kvm libvirt-daemon-config-network \
    virt-install virt-top guestfs-tools
systemctl enable virtqemud.socket virtnetworkd.socket virtstoraged.socket

ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service

# Desktop defaults: compile dconf, validate configs shipped in system_files
dconf update

# Kernel must match the one the NVIDIA kmod was built for
KMOD=$(rpms 'kmod-nvidia-*.rpm' | tail -n1)
[[ -n $KMOD ]] || die "no kmod-nvidia rpm in akmods image"
KVER=$(rpm -qp --requires "$KMOD" 2>/dev/null | awk '$1 == "kernel-uname-r" { print $3; exit }')
[[ -n $KVER ]] || die "cannot read target kernel of $KMOD"

if [[ $(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core) != "$KVER" ]]; then
    mapfile -t KRPMS < <(rpms "kernel-*${KVER}.rpm" | grep -vE '/kernel-(devel|headers|tools|uki|debug)')
    [[ ${#KRPMS[@]} -gt 0 ]] || die "no cached kernel $KVER in akmods images"
    mapfile -t OLD < <(rpm -qa kernel kernel-core 'kernel-modules*')
    rpm -e --nodeps "${OLD[@]}"
    rm -rf /usr/lib/modules/*
    dnf -y install "${KRPMS[@]}"
fi
[[ $(ls /usr/lib/modules) == "$KVER" ]] || die "image kernel is not $KVER"

# NVIDIA: ublue signing key and repos, signed kmod, matching userspace (negativo17 only)
REPOS_BEFORE=$(ls /etc/yum.repos.d)
mapfile -t ADDONS < <(rpms 'ublue-os-akmods-addons*.rpm'; rpms 'ublue-os-nvidia-addons*.rpm')
dnf -y install "${ADDONS[@]}"
NEW_REPOS=$(comm -13 <(echo "$REPOS_BEFORE") <(ls /etc/yum.repos.d) || true)

mapfile -t KMOD_DEPS < <(rpms 'nvidia-kmod-common*.rpm')
dnf -y install --enablerepo=fedora-nvidia "$KMOD" "${KMOD_DEPS[@]}"
NV=$(modinfo -k "$KVER" -F version nvidia)
[[ -n $(modinfo -k "$KVER" -F signer nvidia) ]] || die "nvidia module is unsigned"

dnf -y install --enablerepo=fedora-nvidia "nvidia-driver-$NV" "nvidia-driver-cuda-$NV" libva-nvidia-driver
[[ $(rpm -q --qf '%{VERSION}' nvidia-driver) == "$NV" ]] || die "nvidia userspace is not $NV"

for f in $NEW_REPOS; do sed -i 's/^enabled=1/enabled=0/' "/etc/yum.repos.d/$f"; done

# Boot splash (only once system_files/usr/share/plymouth/themes/uranicorn exists)
THEME=/usr/share/plymouth/themes/uranicorn
if [[ -d $THEME ]]; then
    cp --update=none /usr/share/plymouth/themes/spinner/*.png "$THEME/"
    plymouth-set-default-theme uranicorn
fi

# Initramfs: always rebuilt (kernel swap, plymouth theme)
mkdir -p /var/roothome
DRACUT_NO_XATTR=1 dracut --no-hostonly --kver "$KVER" --reproducible --zstd \
    --add ostree -f "/usr/lib/modules/$KVER/initramfs.img"
chmod 0600 "/usr/lib/modules/$KVER/initramfs.img"

# Host verifies this image's signature
python3 - "$IMAGE" "$KEY" <<'PY'
import json, sys
path = "/etc/containers/policy.json"
policy = json.load(open(path))
policy.setdefault("transports", {}).setdefault("docker", {})[sys.argv[1]] = [{
    "type": "sigstoreSigned",
    "keyPath": sys.argv[2],
    "signedIdentity": {"type": "matchRepository"},
}]
json.dump(policy, open(path, "w"), indent=2)
PY

# Cleanup, including the stale lock shipped by the base image
dnf clean all
rm -f /etc/{passwd,group,shadow,gshadow,subuid,subgid}.lock
rm -rf /run/dnf /var/log/dnf5.log*
