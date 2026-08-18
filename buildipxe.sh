#!/bin/bash
#
# Build FOG's iPXE binaries.
#
#   ./buildipxe.sh [cert] [outdir]
#
# Both arguments are optional. With none, it builds against the FOG CA if one
# is present on this machine and writes to ./output.
#
# The only per-site input to an iPXE build is the CA certificate: CERT=/TRUST=
# bake it into the binary so iPXE can fetch boot.php over TLS. Everything else
# is identical for every FOG server, which is why these binaries are published
# as release assets and only HTTPS-with-your-own-CA installs need to run this
# script at all. See FOGProject/fogproject#959.
#
# GH-850: runnable standalone, so resolve the base path from the pointer the
# installer wrote rather than assuming /opt/fog. An explicit cert argument
# still wins.
[[ -z $fogprogramdir && -r /etc/fog/fog.conf ]] && . /etc/fog/fog.conf
[[ -z $fogprogramdir ]] && fogprogramdir="/opt/fog"
if [[ -r $1 ]]; then
  cert=$1
elif [[ -r ${fogprogramdir%/}/snapins/ssl/CA/.fogCA.pem ]]; then
  cert="${fogprogramdir%/}/snapins/ssl/CA/.fogCA.pem"
fi

# NO_WERROR=1: iPXE builds with -Werror, and newer compilers keep finding new
# things to warn about in drivers nobody has touched in a decade -- gcc 16
# fails the whole build on an unused-but-set variable in w89c840.c. That is a
# toolchain-vs-upstream problem, not a FOG one, and it stopped -S/--force-https
# installs building iPXE at all. The knob is upstream's own; FOG simply never
# passed it. Refs GH-955.
BUILDOPTS="CERT=${cert} TRUST=${cert} NO_WERROR=1"
IPXEGIT="https://github.com/ipxe/ipxe"
# Pinned to a release tag rather than tracking master. Building from whatever
# upstream pushed that morning means two people running this script on the same
# day can get different binaries, and it is what let the stale
# Makefile.housekeeping overlay (since deleted) go unnoticed for two years. New
# hardware support now arrives when this line is bumped, which is the trade we
# want: iPXE has tagged releases again as of v2.0.0 (March 2026). Export
# IPXEVER to build something else for testing. Refs GH-957.
IPXEVER="${IPXEVER:-v2.0.0}"

# This script lives at the root of its own repository rather than three levels
# down inside fogproject, and it keeps its upstream clones and its output
# inside that repository instead of scattering them into the parent directory
# of wherever a tarball happened to be unpacked. An installer that places this
# checkout at $fogprogramdir/ipxe therefore gets everything under one
# predictable path -- which is also the path an offline site pre-populates.
SCRIPT=$(readlink -f "$BASH_SOURCE")
FOGDIR=$(dirname "$SCRIPT")
BASE="${FOGDIR}/build"
OUTDIR="${2:-${FOGDIR}/output}"

# FOG-carried patches against the pinned upstream tag.
#
# This repository overlays CONFIGURATION onto a pristine upstream checkout; it
# does not fork it. patches/ is the one place a C change can live, and it earns
# that only when upstream cannot yet supply the behaviour and FOG cannot ship
# without it.
#
# Applied after the reset/checkout above, never before: an existing clone is
# reset --hard and clean -fd'd on every run, so each build starts from pristine
# upstream and re-applies the full set. Nothing accumulates, and a patch that
# has stopped applying fails the build loudly instead of silently producing a
# binary without it.
#
# Because IPXEVER is a fixed tag these do not rot between builds. They need
# revisiting only when the pin moves, which is a deliberate edit.
apply_fog_patches() {
  local repo="$1" p
  [[ -d ${FOGDIR}/patches ]] || return 0
  shopt -s nullglob
  for p in ${FOGDIR}/patches/*.patch; do
    echo "Applying $(basename "$p") to $(basename "$repo")..."
    git -C "$repo" apply "$p" || {
      echo "ERROR: $(basename "$p") does not apply to ${IPXEVER}." >&2
      echo "       Rebase it, or drop it if upstream has taken the change." >&2
      exit 41
    }
  done
  shopt -u nullglob
}

# The output tree is emitted in exactly fogproject's packages/tftp layout, so
# the installer can copy it over its tftpdir unchanged.
mkdir -p "$BASE" ${OUTDIR}/{10secdelay,i386-efi,arm64-efi}

if [[ -d ${BASE}/ipxe ]]; then
  cd ${BASE}/ipxe
  git clean -fd
  git reset --hard
  # fetch+checkout rather than pull: an existing clone from before the pin is
  # sitting on master, and pull would just advance it.
  git fetch --tags --force ${IPXEGIT}
  git checkout -q ${IPXEVER} || exit 39
  cd src/
  # make sure this is being re-compiled in case the CA has changed!
  touch crypto/rootcert.c
else
  git clone --branch ${IPXEVER} ${IPXEGIT} ${BASE}/ipxe
  cd ${BASE}/ipxe/src/
fi
apply_fog_patches ${BASE}/ipxe


# Overlay this repository's headers and boot scripts onto the clone.
#
# Makefile.housekeeping is deliberately NOT among these. FOG carried a copy
# from 2024 and pasted it over every fresh clone, which meant a 2024 build
# system driving 2026 sources. It never held a single FOG-specific line -- each
# "fix" to it was just re-pinning a newer upstream snapshot after the mismatch
# broke something -- and the last re-pin reverted upstream's newer Secure Boot
# build mode, which excludes known-insecure drivers, back to the older scheme.
# The clone already ships the right one. Refs GH-955.
echo "Copy (overwrite) iPXE headers and scripts..."
cp ${FOGDIR}/src/ipxescript .
cp ${FOGDIR}/src/ipxescript10sec .
cp ${FOGDIR}/src/config/general.h config/
cp ${FOGDIR}/src/config/settings.h config/
cp ${FOGDIR}/src/config/console.h config/
# USB settings go in as an overlaid config/local/usb.h, which upstream's
# config/usb.h includes last so our values win. This used to be a sed against
# upstream's file; see src-efi/config/local/usb.h for why that had to go.
mkdir -p config/local
cp ${FOGDIR}/src/config/local/usb.h config/local/

# Build the files
make -j$(nproc) EMBED=ipxescript bin/ipxe.iso bin/{undionly,ipxe,intel,realtek}.{,k,kk}pxe bin/ipxe.lkrn bin/ipxe.usb ${BUILDOPTS}
[[ $? -eq 0 ]] || exit 40

# Collect into the output tree
cp bin/ipxe.iso bin/{undionly,ipxe,intel,realtek}.{,k,kk}pxe bin/ipxe.lkrn bin/ipxe.usb ${OUTDIR}/
cp bin/ipxe.lkrn ${OUTDIR}/ipxe.krn

# Build with 10 second delay
make -j$(nproc) EMBED=ipxescript10sec bin/ipxe.iso bin/{undionly,ipxe,intel,realtek}.{,k,kk}pxe bin/ipxe.lkrn bin/ipxe.usb ${BUILDOPTS}
[[ $? -eq 0 ]] || exit 48

# Collect into the output tree
cp bin/ipxe.iso bin/{undionly,ipxe,intel,realtek}.{,k,kk}pxe bin/ipxe.lkrn bin/ipxe.usb ${OUTDIR}/10secdelay/
cp bin/ipxe.lkrn ${OUTDIR}/10secdelay/ipxe.krn

# Change to the efi layout
if [[ -d ${BASE}/ipxe-efi ]]; then
  cd ${BASE}/ipxe-efi/
  git clean -fd
  git reset --hard
  # See the note on the BIOS tree above.
  git fetch --tags --force ${IPXEGIT}
  git checkout -q ${IPXEVER} || exit 79
  cd src/
  # make sure this is being re-compiled in case the CA has changed!
  touch crypto/rootcert.c
else
  git clone --branch ${IPXEVER} ${IPXEGIT} ${BASE}/ipxe-efi
  cd ${BASE}/ipxe-efi/src/
fi
apply_fog_patches ${BASE}/ipxe-efi

# Overlay this repository's headers and boot scripts onto the clone.
echo "Copy (overwrite) iPXE headers and scripts..."
cp ${FOGDIR}/src-efi/config/general.h config/
cp ${FOGDIR}/src-efi/config/settings.h config/
cp ${FOGDIR}/src-efi/config/console.h config/
# USB keyboard support. Overlaid rather than sed-patched into upstream's
# config/usb.h -- v2.0.0 restructured that file and every sed pattern silently
# stopped matching, which is what broke the keyboard on ipxe.efi. See
# src-efi/config/local/usb.h.
mkdir -p config/local
cp ${FOGDIR}/src-efi/config/local/usb.h config/local/

# Build the EFI binaries. One pass, no EMBED.
#
# WHY NO EMBED HERE
#
# With no script compiled in, first_image() finds nothing at INIT_LATE, so
# efi_probe()'s efi_autoexec_load() gets to register autoexec.ipxe and ipxe()
# executes that instead. Three things follow, and they are the whole reason
# this is the only EFI build now:
#
#   1. A site can change its boot logic without a toolchain. The script is a
#      file on the TFTP server, not bytes inside 15 binaries.
#
#   2. It is the only shape that works under Secure Boot: efi_autoexec.c is
#      FILE_SECBOOT ( PERMITTED ), an embedded script is not.
#
#   3. It is the only shape that can safely share a directory with
#      autoexec.ipxe. An EMBED-marked binary still DOWNLOADS the script --
#      efi_probe() registers it unconditionally -- but never executes it,
#      because first_image() returns the embedded one ahead of it. Nothing
#      unregisters it, so initrd_load_all() concatenates it into the ramdisk
#      ahead of init.xz and the kernel panics on the missing compression
#      magic. An EMBED-less binary EXECUTES the script, and image_exec()
#      unregisters it for the duration, so it is gone by the time boot runs.
#
# (3) is why the previous layout had to keep the EMBED-less binaries in a
# separate autoexec/ directory and delete any autoexec.ipxe from the TFTP
# root: efi_autoexec_network() falls back to /autoexec.ipxe when the
# binary's own directory has none, so ONE embedded EFI binary anywhere in the
# tree was enough to poison every client that fell back to the root. Removing
# EMBED from every EFI target removes that constraint, which is what lets the
# autoexec/ duplicate tree go away and autoexec.ipxe become the normal
# mechanism rather than an opt-in.
#
# The 10-second delay variant goes with it. It differed from the default by
# two lines -- an echo and a sleep -- which is now an edit the installer makes
# to autoexec.ipxe rather than a second copy of every binary. 10secdelay/
# keeps its BIOS files, which genuinely do need a separate build because BIOS
# has no efi_autoexec_load() and therefore no script to edit.
make -j$(nproc) bin-{i386,x86_64}-efi/{snp{,only},ipxe,intel,realtek}.efi ${BUILDOPTS}
[[ $? -eq 0 ]] || exit 80

make -j$(nproc) CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 bin-arm64-efi/{snp{,only},ipxe,intel,realtek}.efi ${BUILDOPTS}
[[ $? -eq 0 ]] || exit 82

# Collect into the output tree
cp bin-arm64-efi/{snp{,only},ipxe,intel,realtek}.efi ${OUTDIR}/arm64-efi/
cp bin-i386-efi/{snp{,only},ipxe,intel,realtek}.efi ${OUTDIR}/i386-efi/
cp bin-x86_64-efi/{snp{,only},ipxe,intel,realtek}.efi ${OUTDIR}/

# One copy per directory holding an EFI binary. efi_autoexec_network() asks for
# autoexec.ipxe relative to the binary's own URI first and only then retries at
# the TFTP root, so a per-directory copy saves a failed request on every boot.
# The installer hard-links these together afterwards so they cannot drift.
for d in . i386-efi arm64-efi; do
  cp ${FOGDIR}/autoexec.ipxe ${OUTDIR}/$d/
done
