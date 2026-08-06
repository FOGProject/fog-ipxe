#ifndef CONFIG_LOCAL_USB_H
#define CONFIG_LOCAL_USB_H

/** @file
 *
 * FOG USB configuration overrides for BIOS builds
 *
 * See src-efi/config/local/usb.h for why these settings are overlaid here
 * rather than patched into upstream's config/usb.h with sed.
 *
 */

/* USB_HCD_USBIO is an EFI construct -- it drives USB through
 * EFI_USB_IO_PROTOCOL -- and has no meaning in a legacy BIOS build.
 *
 * As of v2.0.0 upstream only defines it inside a PLATFORM_efi block, so a BIOS
 * build cannot pick it up by accident and this line is belt-and-braces. It is
 * kept anyway because the sed it replaces was load-bearing against an older
 * upstream layout that did define it unconditionally, and a standing #undef
 * holds whichever way a future refresh moves the default. The alternative is
 * depending on upstream's current arrangement staying put, which is the
 * assumption that produced forums #18213 in the first place.
 */
#undef USB_HCD_USBIO

#endif /* CONFIG_LOCAL_USB_H */
