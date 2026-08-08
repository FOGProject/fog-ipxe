#ifndef CONFIG_CONSOLE_H
#define CONFIG_CONSOLE_H

/** @file
 *
 * Console configuration
 *
 * These options specify the console types that iPXE will use for
 * interaction with the user.
 *
 */

FILE_LICENCE ( GPL2_OR_LATER_OR_UBDL );
FILE_SECBOOT ( PERMITTED );

#include <config/defaults.h>

/*****************************************************************************
 *
 * Console types
 *
 */

/* Console types supported on all platforms */
#define CONSOLE_FRAMEBUFFER	/* Graphical framebuffer console */
//#define CONSOLE_SYSLOG		/* Syslog console */
//#define CONSOLE_SYSLOGS		/* Encrypted syslog console */

/* Console types supported only on systems with serial ports */
#if ! defined ( SERIAL_NULL )
  //#define CONSOLE_SERIAL	/* Serial port console */
#endif

/* Console types supported only on BIOS platforms */
#if defined ( PLATFORM_pcbios )
  //#define CONSOLE_INT13	/* INT13 disk log console */
  #define CONSOLE_PCBIOS	/* Default BIOS console */
#endif

/* Console types supported only on EFI platforms */
#if defined ( PLATFORM_efi )
  #define CONSOLE_EFI		/* Default EFI console */
#endif

/* Console types supported only on RISC-V SBI platforms */
#if defined ( PLATFORM_sbi )
  #define CONSOLE_SBI		/* RISC-V SBI debug console */
#endif

/* Console types supported only on Linux platforms */
#if defined ( PLATFORM_linux )
  #define CONSOLE_LINUX		/* Default Linux console */
#endif

/* Console types supported only on x86 CPUs */
#if defined ( __i386__ ) || defined ( __x86_64__ )
  //#define CONSOLE_DEBUGCON	/* Bochs/QEMU/KVM debug port console */
  //#define CONSOLE_DIRECT_VGA	/* Direct access to VGA card */
  //#define CONSOLE_PC_KBD	/* Direct access to PC keyboard */
  #define CONSOLE_VMWARE	/* VMware logfile console */
#endif

/* Enable serial console on platforms that are typically headless */
#if defined ( CONSOLE_SBI )
  #define CONSOLE_SERIAL
#endif

/* Disable console types not historically included in BIOS builds */
#if defined ( PLATFORM_pcbios )
  #undef CONSOLE_FRAMEBUFFER
  #undef CONSOLE_SYSLOG
  #undef CONSOLE_SYSLOGS
#endif

/* FOG deviation: restore the framebuffer console on BIOS builds.
 *
 * Same cause and same shape as the command trim list in general.h -- this is
 * upstream's console-type trim list, and it arrived with the same wholesale
 * header copy in f61a90d97 (fogproject, 2026-01-26). FOG's console.h carried a
 * plain "#define CONSOLE_FRAMEBUFFER" and no PLATFORM_pcbios block at all
 * before that commit, so BIOS builds have always had it. Restoring the eight
 * commands (fog-ipxe#3, v2.0.0-fog.4) fixed the trim list one file over but
 * left this one, so CONSOLE_CMD came back while the console it drives did not.
 *
 * CONSOLE_FRAMEBUFFER is what pulls in vesafb (arch/x86/interface/pcbios/) and
 * fbcon -- the only graphical console a BIOS build can have; EFI gets its own
 * via efifb, which is why this is invisible to UEFI testing.
 *
 * bootmenu.class.php emits "console --picture <booturl>/ipxe/bg.png --left 100
 * --right 80 && goto console_set || goto alt_console". Without a console that
 * implements .configure, console_configure() has nothing to hand the pixbuf to
 * and returns success, so the command *silently* succeeds having drawn
 * nothing: the picture is downloaded, PNG-decoded, and dropped. The menu then
 * renders as unstyled text on black and the alt_console fallback -- the thing
 * meant to catch exactly this -- never fires because nothing reported failure.
 * Reported on the forums for dev-branch/undionly.kpxe, 2026-08-08.
 *
 * Only CONSOLE_FRAMEBUFFER is restored; FOG has never used the syslog consoles
 * and leaving those undefined keeps the BIOS binary's size increase to what
 * the boot menu actually needs.
 *
 * Kept as an explicit override AFTER upstream's block, matching general.h, so
 * the next refresh onto a new upstream tag diffs cleanly and this reads as a
 * FOG choice rather than more drift.
 */
#if defined ( PLATFORM_pcbios )
  #define CONSOLE_FRAMEBUFFER	/* Graphical framebuffer console */
#endif

/*****************************************************************************
 *
 * Keyboard maps
 *
 * See hci/keymap/keymap_*.c for available keyboard maps.
 *
 */

#define KEYBOARD_MAP	us	/* Default US keyboard map */
//#define KEYBOARD_MAP	dynamic	/* Runtime selectable keyboard map */

/*****************************************************************************
 *
 * Log levels
 *
 * Control which syslog() messages are generated.  Note that this is
 * not related in any way to CONSOLE_SYSLOG.
 *
 */

#define LOG_LEVEL	LOG_NONE

#include <config/named.h>
#include NAMED_CONFIG(console.h)
#include <config/local/console.h>
#include LOCAL_NAMED_CONFIG(console.h)

#endif /* CONFIG_CONSOLE_H */
