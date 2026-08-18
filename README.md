# fog-ipxe

iPXE sources, build configuration and prebuilt binaries for [FOG Project](https://github.com/FOGProject/fogproject).

FOG boots clients with [iPXE](https://ipxe.org). This repository holds everything FOG layers on top of upstream iPXE — the feature selection, the boot scripts, and the build script — and publishes the resulting binaries as release assets.

It exists so that `fogproject` does not have to carry 22 MB of build output in git, and so that "which iPXE is this server running?" has an answer. See [fogproject#959](https://github.com/FOGProject/fogproject/issues/959).

## Most people do not need to build anything

The FOG installer downloads these binaries from a release, checksums them, and drops them in the TFTP root. That is the whole story for an HTTP install, or an HTTPS install using a publicly trusted certificate.

**There is exactly one reason to build locally:** HTTPS with your own CA. `CERT=`/`TRUST=` bake that certificate into the binary so iPXE can fetch `boot.php` over TLS, which makes it a per-server artifact no release can supply. The installer handles this for you when `httpproto` is `https`.

## Layout

```
src/            BIOS build   — config headers + embedded boot scripts
src-efi/        EFI build    — same, with EFI-specific feature selection
                               (config headers only; EFI embeds no script)
autoexec.ipxe   the boot script every EFI binary downloads and runs
buildipxe.sh    the build
secureboot/     pinned upstream signed binaries — republished, not built
```

`src/` and `src-efi/` are near-identical, because most of what differs between them sits inside `#if defined ( PLATFORM_* )` guards and is inert in the other tree.

### The config headers

These are the FOG-specific part. They are **generated**, not hand-edited: start from the pristine upstream headers for whatever `IPXEVER` is pinned to, then apply an explicit table of FOG's deviations, each carrying the reason it exists.

Do it that way and the next refresh is a re-run rather than a three-way diff, and "is this a FOG choice or is it drift?" is answerable by looking at one table. FOG previously refreshed these by copying upstream's wholesale, which silently disabled the BIOS console for anyone who rebuilt — see [fogproject#958](https://github.com/FOGProject/fogproject/issues/958).

## Building

```bash
./buildipxe.sh [cert] [outdir]
```

Both arguments optional; defaults are the FOG CA if one is present and `./output`. Upstream clones land in `./build/`.

The output tree mirrors FOG's `packages/tftp/` layout exactly, so it can be copied over a TFTP root unchanged:

```
output/                 BIOS (script embedded) + x86_64 EFI + autoexec.ipxe
output/i386-efi/        32-bit EFI + autoexec.ipxe
output/arm64-efi/       arm64 EFI + autoexec.ipxe
output/10secdelay/      BIOS only, with a 10 second pre-DHCP sleep
```

Requirements: `git`, `make`, `gcc`, `binutils`, `perl`, `liblzma`, `mtools`, `xorriso`, and `gcc-aarch64-linux-gnu` for the arm64 binaries.

### `IPXEVER`

The upstream clone is pinned to a tag. Bumping it is a deliberate act — FOG spent years tracking `master`, which meant two people building on the same day could get different binaries.

```bash
IPXEVER=v2.0.1 ./buildipxe.sh
```

### Boot scripts: EFI reads `autoexec.ipxe`, BIOS embeds one

No EFI binary here is built with `EMBED=`. Each one downloads `autoexec.ipxe`
from the directory it was itself loaded from — falling back to the TFTP root —
and executes it, because with nothing compiled in `first_image()` finds no
image ahead of it. Changing the boot logic is therefore editing one text file,
with no toolchain and no rebuild. It is also the only shape that works under
UEFI Secure Boot, since an embedded script is not permitted in a Secure Boot
build. See the [Secure Boot how-to](https://docs.fogproject.org/kb/how-tos/secure-boot-signing/).

A copy of `autoexec.ipxe` ships in every directory holding an EFI binary. FOG's
installer hard-links them so there is exactly one script however many paths
reach it.

**Do not put an `EMBED=` binary in a directory an EMBED-less one can fall back
to.** An embedded binary still *downloads* `autoexec.ipxe` — `efi_probe()`
registers it before any driver is connected — but never runs it, so nothing
unregisters it and `initrd_load_all()` concatenates it into the ramdisk ahead
of `init.xz`. The kernel then panics on the missing compression magic. This is
why `EMBED=` is gone from every EFI target rather than most of them.

Legacy BIOS is the exception and keeps `EMBED=`: it has no
`efi_autoexec_load()`, so there is no downloaded script for it to read. That is
also why `10secdelay/` still exists and now holds BIOS files only — on EFI the
delay is an installer option that inserts a `sleep` into `autoexec.ipxe`.

## Secure Boot

A second release asset, `fog-ipxe-secureboot-<tag>.tar.gz`, carries the pieces a Secure Boot chain needs that FOG **cannot build**: they have to be signed by keys FOG does not hold — Microsoft's, for the shim, and iPXE's, for the loader it chains to.

```
secureboot/snponly-shimx64.efi   ipxe/shim, signed by Microsoft (2011 + 2023)
secureboot/snponly.efi           upstream's signed iPXE
secureboot/mmx64.efi             MokManager, for enrolling your own key
secureboot/autoexec.ipxe         this repo's own boot script
secureboot/arm64-efi/…           the same set for arm64
secureboot/MANIFEST              what was taken from where, with hashes
```

Everything but `autoexec.ipxe` is upstream's, republished byte for byte. `secureboot/upstream.lock` pins the release tags and the sha256 of every file; `secureboot/stage.sh` fetches them, checks those hashes, and reads the PE certificate table back to assert each binary is signed by the key it should be. A mismatch fails the release rather than shipping — an unsigned or test-signed binary that reaches an install surfaces at the client as "Security Policy Violation" with nothing server-side to explain it.

Staging runs on **every** build, not just tags, so a pull request proves the pins still resolve.

Two things worth knowing about the layout:

- **`snponly-shimx64.efi` is a rename, and the name is the mechanism.** shim picks its second stage by rewriting its own `-shim<arch>.efi` filename suffix to `.efi`, so this one loads `snponly.efi`. Under shim's stock name it would load `ipxe.efi` — the all-drivers build, which hangs wherever native NIC takeover fails. The suffix match allows `-shim` plus at most four more characters, and `-shimaa64` is exactly at that limit: do not lengthen these names.
- **`autoexec.ipxe` must sit beside the binaries**, because iPXE resolves the bare name against `cwuri`.

A Secure Boot chain still needs one thing this release cannot supply: the FOS kernel is unsigned, so it has to be signed with your own key and that key enrolled via MokManager. See the [Secure Boot how-to](https://docs.fogproject.org/kb/how-tos/secure-boot-signing/).

Bumping a pin is a reviewable one-file diff. `IPXE_RELEASE` is asserted against `IPXEVER` in `buildipxe.sh` rather than derived from it — if the two drift, Secure Boot clients run a different iPXE release from every other client on the same server.

## Offline installs

Pre-place this checkout — and its `build/` clones — at `$fogprogramdir/ipxe` (default `/opt/fog/ipxe`). `buildipxe.sh` reuses an existing clone rather than fetching, so a machine with no internet access can still build.

## Licence

iPXE is GPLv2 (with a UBDL option); see upstream. The FOG-specific files here are GPLv3, matching `fogproject`.
