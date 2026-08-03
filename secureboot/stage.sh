#!/bin/bash
#
# Stage the Secure Boot asset set from pinned upstream releases.
#
# WHY THIS EXISTS
# ---------------
# The alternative was having installfog.sh fetch these from ipxe/shim and
# ipxe/ipxe at install time. That puts a network dependency on two third-party
# release URLs into every install, on every site, unsupervised. Doing it here
# moves the same dependency to one supervised moment -- a release -- where a
# failure is seen by a human instead of surfacing weeks later as a machine that
# will not PXE boot. The installer then gets these from the fog-ipxe release it
# already downloads, so staging them costs it no extra network calls and works
# offline the moment someone pre-places the tarball.
#
# WHAT IT GUARANTEES
# ------------------
# Republishing someone else's Microsoft-signed binary is normal -- every distro
# does it -- but it is only defensible if anyone can check we did not touch the
# bytes. So every artefact is checked twice:
#
#   1. sha256 against secureboot/upstream.lock. Catches an upstream asset
#      silently republished under the same tag, which a bare version pin does
#      not catch.
#   2. Signer identity, read out of the PE certificate table. Catches upstream
#      publishing a test-signed or unsigned build. Without this the bad binary
#      propagates to every install and surfaces at a client as "Security Policy
#      Violation" with nothing server-side to explain it -- one of the worst
#      failure shapes in this whole area.
#
# ...and the MANIFEST records what was taken from where, so the check is
# reproducible by a third party and so a future SBAT revocation can be traced
# to the releases that carry the affected shim generation.
#
# Usage: secureboot/stage.sh <output-dir>
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(dirname "$here")"
out="${1:?usage: stage.sh <output-dir>}"

# shellcheck source=secureboot/upstream.lock
. "$here/upstream.lock"

for tool in curl tar sha256sum sbverify; do
    command -v "$tool" >/dev/null || { echo "stage.sh: missing $tool" >&2; exit 1; }
done

# The lock pins the iPXE release, but buildipxe.sh owns the real one. Assert
# rather than derive so bumping one without the other is a loud failure at
# release time instead of a silent version skew between the Secure Boot path
# and every other client.
buildver="$(sed -n 's/^IPXEVER="\${IPXEVER:-\(.*\)}"/\1/p' "$repo/buildipxe.sh")"
if [[ -z $buildver ]]; then
    echo "stage.sh: could not read IPXEVER from buildipxe.sh" >&2
    exit 1
fi
if [[ $buildver != "$IPXE_RELEASE" ]]; then
    echo "stage.sh: IPXE_RELEASE ($IPXE_RELEASE) != IPXEVER ($buildver)." >&2
    echo "  The signed snponly.efi and the locally built binaries must come" >&2
    echo "  from the same upstream release. Bump both, and refresh" >&2
    echo "  IPXEBOOT_SHA256 in secureboot/upstream.lock." >&2
    exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

SHIM_BASE="https://github.com/ipxe/shim/releases/download/${SHIM_RELEASE}"
IPXE_BASE="https://github.com/ipxe/ipxe/releases/download/${IPXE_RELEASE}"

fetch() {  # fetch <url> <dest> <expected-sha256>
    local url="$1" dest="$2" want="$3" got
    echo "  fetch $(basename "$dest")"
    curl -fsSL --retry 3 --retry-delay 2 -o "$dest" "$url"
    got="$(sha256sum "$dest" | cut -d' ' -f1)"
    if [[ $got != "$want" ]]; then
        echo "stage.sh: sha256 mismatch for $url" >&2
        echo "  expected $want" >&2
        echo "  got      $got" >&2
        echo "  Upstream republished this asset, or the pin is wrong." >&2
        echo "  Do NOT just update the hash -- work out which it was first." >&2
        exit 1
    fi
}

assert_signer() {  # assert_signer <file> <expected-string>...
    local file="$1"; shift
    local listing want
    # sbverify warns "data remaining ... gaps between PE/COFF sections?" on the
    # shim. That is normal for these binaries and is not a signature problem,
    # so only the CN assertions below decide pass/fail.
    listing="$(sbverify --list "$file" 2>/dev/null)" || {
        echo "stage.sh: $file carries no readable signature" >&2
        exit 1
    }
    for want in "$@"; do
        if ! grep -qF "$want" <<<"$listing"; then
            echo "stage.sh: $file is not signed by the expected key" >&2
            echo "  expected to find: $want" >&2
            echo "  sbverify --list said:" >&2
            sed 's/^/    /' <<<"$listing" >&2
            exit 1
        fi
    done
    echo "  signer ok: $(basename "$file")"
}

echo "Fetching pinned upstream artefacts"
fetch "${SHIM_BASE}/ipxe-shimx64.efi"  "$work/ipxe-shimx64.efi"  "$SHIM_X64_SHA256"
fetch "${SHIM_BASE}/ipxe-shimaa64.efi" "$work/ipxe-shimaa64.efi" "$SHIM_AA64_SHA256"
fetch "${SHIM_BASE}/mmx64.efi"         "$work/mmx64.efi"         "$MM_X64_SHA256"
fetch "${SHIM_BASE}/mmaa64.efi"        "$work/mmaa64.efi"        "$MM_AA64_SHA256"
fetch "${IPXE_BASE}/ipxeboot.tar.gz"   "$work/ipxeboot.tar.gz"   "$IPXEBOOT_SHA256"

tar xzf "$work/ipxeboot.tar.gz" -C "$work" \
    ipxeboot/x86_64-sb/snponly.efi ipxeboot/x86_64-sb/ipxe.efi \
    ipxeboot/arm64-sb/snponly.efi  ipxeboot/arm64-sb/ipxe.efi

echo "Verifying signers"
assert_signer "$work/ipxe-shimx64.efi"  "$SHIM_SIGNER_2011" "$SHIM_SIGNER_2023"
assert_signer "$work/ipxe-shimaa64.efi" "$SHIM_SIGNER_2011" "$SHIM_SIGNER_2023"
assert_signer "$work/ipxeboot/x86_64-sb/snponly.efi" \
    "$IPXE_SIGNER_SUBJECT" "$IPXE_SIGNER_ISSUER"
assert_signer "$work/ipxeboot/x86_64-sb/ipxe.efi" \
    "$IPXE_SIGNER_SUBJECT" "$IPXE_SIGNER_ISSUER"
assert_signer "$work/ipxeboot/arm64-sb/snponly.efi" \
    "$IPXE_SIGNER_SUBJECT" "$IPXE_SIGNER_ISSUER"
assert_signer "$work/ipxeboot/arm64-sb/ipxe.efi" \
    "$IPXE_SIGNER_SUBJECT" "$IPXE_SIGNER_ISSUER"

# The rename IS the mechanism, so it happens here -- once, in a reviewed file
# -- rather than in the installer where a typo would be a silent TFTP 404.
#
# shim picks its second stage from its own filename: automatic_next_path() in
# shim.c rewrites a "-shim[arch].efi" suffix to ".efi". So snponly-shimx64.efi
# loads snponly.efi, where the stock name would load ipxe.efi (the all-drivers
# build, which hangs wherever native NIC takeover fails). Upstream ships the
# same binary under both ipxe-shim.efi and snponly-shim.efi as symlinks for
# this reason; we materialise real files because some TFTP daemons refuse to
# follow symlinks.
#
# The suffix match allows "-shim" plus up to four more characters before
# ".efi". "-shimaa64" is exactly nine and therefore exactly at the limit --
# do not lengthen these names. Only the suffix is matched, so the "ipxe-"
# prefix below costs nothing.
#
# BOTH pairs are published, because neither loader works everywhere:
#   snponly.efi drives the NIC through the firmware's own UEFI SNP protocol.
#   Right answer by default -- it is whatever the vendor shipped and tested --
#   but it is dead in the water on firmware whose SNP is broken or absent.
#   ipxe.efi carries iPXE's native drivers and takes the NIC over from the
#   firmware. Recovers exactly those machines, and hangs on the ones where the
#   takeover fails.
#
# Non-Secure-Boot installs have had both since forever and admins switch
# between them by changing DHCP option 67. Publishing only the snponly pair
# made Secure Boot the one path with no fallback, so a site whose firmware SNP
# is broken had nothing to move to. Each pair is self-contained -- shim resolves
# its second stage from its OWN name -- so the two sit side by side in the same
# directory and DHCP alone picks which chain runs.
echo "Staging"
mkdir -p "$out/secureboot/arm64-efi"
install -m 0644 "$work/ipxeboot/x86_64-sb/snponly.efi" "$out/secureboot/snponly.efi"
install -m 0644 "$work/ipxe-shimx64.efi"  "$out/secureboot/snponly-shimx64.efi"
install -m 0644 "$work/ipxeboot/x86_64-sb/ipxe.efi"    "$out/secureboot/ipxe.efi"
install -m 0644 "$work/ipxe-shimx64.efi"  "$out/secureboot/ipxe-shimx64.efi"
install -m 0644 "$work/mmx64.efi"         "$out/secureboot/mmx64.efi"
install -m 0644 "$work/ipxeboot/arm64-sb/snponly.efi" "$out/secureboot/arm64-efi/snponly.efi"
install -m 0644 "$work/ipxe-shimaa64.efi" "$out/secureboot/arm64-efi/snponly-shimaa64.efi"
install -m 0644 "$work/ipxeboot/arm64-sb/ipxe.efi"    "$out/secureboot/arm64-efi/ipxe.efi"
install -m 0644 "$work/ipxe-shimaa64.efi" "$out/secureboot/arm64-efi/ipxe-shimaa64.efi"
install -m 0644 "$work/mmaa64.efi"        "$out/secureboot/arm64-efi/mmaa64.efi"

# autoexec.ipxe has to sit beside the binaries: iPXE resolves the bare name
# against cwuri, the directory the running .efi was fetched from. The installer
# hard-links the copies it places under /tftpboot; here they are plain files
# because a tarball cannot carry a hard link across extraction reliably.
install -m 0644 "$repo/autoexec.ipxe" "$out/secureboot/autoexec.ipxe"
install -m 0644 "$repo/autoexec.ipxe" "$out/secureboot/arm64-efi/autoexec.ipxe"

{
    echo "# fog-ipxe Secure Boot asset set"
    echo "#"
    echo "# Republished byte-for-byte from the upstream releases below. Verify"
    echo "# any file here by downloading the source URL and comparing sha256."
    echo "#"
    echo "# iPXE release: ${IPXE_RELEASE}   (matches IPXEVER in buildipxe.sh)"
    echo "# shim release: ${SHIM_RELEASE}"
    echo "#"
    printf '# %-34s %-64s %s\n' "staged as" "sha256" "source"
    manifest_row() {  # manifest_row <staged-path> <source-url>
        printf '%-36s %-64s %s\n' \
            "$1" "$(sha256sum "$out/$1" | cut -d' ' -f1)" "$2"
    }
    manifest_row "secureboot/snponly.efi"                    "${IPXE_BASE}/ipxeboot.tar.gz!ipxeboot/x86_64-sb/snponly.efi"
    manifest_row "secureboot/snponly-shimx64.efi"            "${SHIM_BASE}/ipxe-shimx64.efi"
    manifest_row "secureboot/ipxe.efi"                       "${IPXE_BASE}/ipxeboot.tar.gz!ipxeboot/x86_64-sb/ipxe.efi"
    manifest_row "secureboot/ipxe-shimx64.efi"               "${SHIM_BASE}/ipxe-shimx64.efi"
    manifest_row "secureboot/mmx64.efi"                      "${SHIM_BASE}/mmx64.efi"
    manifest_row "secureboot/arm64-efi/snponly.efi"          "${IPXE_BASE}/ipxeboot.tar.gz!ipxeboot/arm64-sb/snponly.efi"
    manifest_row "secureboot/arm64-efi/snponly-shimaa64.efi" "${SHIM_BASE}/ipxe-shimaa64.efi"
    manifest_row "secureboot/arm64-efi/ipxe.efi"             "${IPXE_BASE}/ipxeboot.tar.gz!ipxeboot/arm64-sb/ipxe.efi"
    manifest_row "secureboot/arm64-efi/ipxe-shimaa64.efi"    "${SHIM_BASE}/ipxe-shimaa64.efi"
    manifest_row "secureboot/arm64-efi/mmaa64.efi"           "${SHIM_BASE}/mmaa64.efi"
    echo
    echo "# Signers asserted at release time:"
    echo "#   shim     ${SHIM_SIGNER_2011}"
    echo "#   shim     ${SHIM_SIGNER_2023}"
    echo "#   loaders  ${IPXE_SIGNER_SUBJECT}"
    echo "#"
    echo "# autoexec.ipxe is FOG's own, from this repo, not upstream."
} > "$out/secureboot/MANIFEST"

echo
cat "$out/secureboot/MANIFEST"
