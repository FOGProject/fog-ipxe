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

# The output tree is emitted in exactly fogproject's packages/tftp layout, so
# the installer can copy it over its tftpdir unchanged.
mkdir -p "$BASE" ${OUTDIR}/{10secdelay/{i386-efi,arm64-efi},i386-efi,arm64-efi,autoexec/{i386-efi,arm64-efi}}

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

# Overlay this repository's headers and boot scripts onto the clone.
echo "Copy (overwrite) iPXE headers and scripts..."
cp ${FOGDIR}/src-efi/ipxescript .
cp ${FOGDIR}/src-efi/ipxescript10sec .
cp ${FOGDIR}/src-efi/config/general.h config/
cp ${FOGDIR}/src-efi/config/settings.h config/
cp ${FOGDIR}/src-efi/config/console.h config/
# USB keyboard support. Overlaid rather than sed-patched into upstream's
# config/usb.h -- v2.0.0 restructured that file and every sed pattern silently
# stopped matching, which is what broke the keyboard on ipxe.efi. See
# src-efi/config/local/usb.h.
mkdir -p config/local
cp ${FOGDIR}/src-efi/config/local/usb.h config/local/

# Build the files
make -j$(nproc) EMBED=ipxescript bin-{i386,x86_64}-efi/{snp{,only},ipxe,intel,realtek}.efi ${BUILDOPTS}
[[ $? -eq 0 ]] || exit 80

# Apply USB configuration for ARM64 build
make -j$(nproc) CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 EMBED=ipxescript bin-arm64-efi/{snp{,only},ipxe,intel,realtek}.efi ${BUILDOPTS}
[[ $? -eq 0 ]] || exit 82

# Collect into the output tree
cp bin-arm64-efi/{snp{,only},ipxe,intel,realtek}.efi ${OUTDIR}/arm64-efi/
cp bin-i386-efi/{snp{,only},ipxe,intel,realtek}.efi ${OUTDIR}/i386-efi/
cp bin-x86_64-efi/{snp{,only},ipxe,intel,realtek}.efi ${OUTDIR}/

# Build with 10 second delay
make -j$(nproc) EMBED=ipxescript10sec bin-{i386,x86_64}-efi/{snp{,only},ipxe,intel,realtek}.efi ${BUILDOPTS}
[[ $? -eq 0 ]] || exit 91

make -j$(nproc) CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 EMBED=ipxescript10sec bin-arm64-efi/{snp{,only},ipxe,intel,realtek}.efi ${BUILDOPTS}
[[ $? -eq 0 ]] || exit 93

# Collect into the output tree
cp bin-arm64-efi/{snp{,only},ipxe,intel,realtek}.efi ${OUTDIR}/10secdelay/arm64-efi/
cp bin-i386-efi/{snp{,only},ipxe,intel,realtek}.efi ${OUTDIR}/10secdelay/i386-efi/
cp bin-x86_64-efi/{snp{,only},ipxe,intel,realtek}.efi ${OUTDIR}/10secdelay/

# Build the EMBED-less EFI variant.
#
# With no embedded script, first_image() finds nothing at INIT_LATE, so
# efi_probe()'s efi_autoexec_load() gets to register autoexec.ipxe and ipxe()
# executes that instead. The script is then a file on the TFTP server rather
# than something compiled in, so a site can change its boot logic without a
# toolchain. This is also the only build that can work under Secure Boot, since
# efi_autoexec.c is FILE_SECBOOT ( PERMITTED ) while an embedded script is not.
#
# Shipped alongside the embedded binaries rather than replacing them: an
# existing server has no autoexec.ipxe in its TFTP root, and a binary that
# finds none falls through to plain netboot(), losing FOG's multi-NIC and
# proxyDHCP handling. Opting in is a DHCP filename change. Refs GH-957.
#
# There is deliberately no 10secdelay counterpart -- with the script on disk,
# the delay is a two-line edit to autoexec.ipxe.
make -j$(nproc) bin-{i386,x86_64}-efi/{snp{,only},ipxe,intel,realtek}.efi ${BUILDOPTS}
[[ $? -eq 0 ]] || exit 95

make -j$(nproc) CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 bin-arm64-efi/{snp{,only},ipxe,intel,realtek}.efi ${BUILDOPTS}
[[ $? -eq 0 ]] || exit 97

cp bin-arm64-efi/{snp{,only},ipxe,intel,realtek}.efi ${OUTDIR}/autoexec/arm64-efi/
cp bin-i386-efi/{snp{,only},ipxe,intel,realtek}.efi ${OUTDIR}/autoexec/i386-efi/
cp bin-x86_64-efi/{snp{,only},ipxe,intel,realtek}.efi ${OUTDIR}/autoexec/

# One copy per directory: efi_autoexec_network() asks for autoexec.ipxe
# relative to the binary's own URI first and only then retries at the TFTP
# root, so a per-directory copy saves a failed request on every boot.
for d in autoexec autoexec/i386-efi autoexec/arm64-efi; do
  cp ${FOGDIR}/autoexec.ipxe ${OUTDIR}/$d/
done
