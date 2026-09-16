#!/usr/bin/env bash
# shellcheck disable=SC2034
# ChiropteraOS live image. Based on archiso's releng profile; see docs/iso.md.

iso_name="chiropteraos"
iso_label="CHIROPTERA_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="ChiropteraOS <https://github.com/george-leonard314/ChiropteraOS>"
iso_application="ChiropteraOS Live"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
# Calamares' unpackfs paths (/run/archiso/bootmnt/arch/...) depend on this.
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-live"]="0:0:440"
  ["/etc/polkit-1/rules.d"]="0:102:750"
  ["/root"]="0:0:750"
  ["/root/.gnupg"]="0:0:700"
  # Staged from calamares/ by ci/build-iso.sh (calamares/stage)
  ["/usr/bin/chiroptera-install"]="0:0:755"
  ["/etc/calamares/scripts/chiroptera-live-cleanup"]="0:0:755"
  ["/etc/calamares/scripts/chiroptera-user-dirs"]="0:0:755"
)
