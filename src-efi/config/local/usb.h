#ifndef CONFIG_LOCAL_USB_H
#define CONFIG_LOCAL_USB_H

/** @file
 *
 * FOG USB configuration overrides for EFI builds
 *
 * upstream's config/usb.h includes this file last, after its own
 * PLATFORM_efi block, so everything here wins. That is the whole reason it
 * exists: buildipxe.sh used to patch these same three settings with sed
 * against upstream's config/usb.h, and when v2.0.0 restructured that file --
 * one space where there had been a tab, "#undef USB_KEYBOARD" active rather
 * than commented out -- all three patterns stopped matching and silently did
 * nothing. Every published EFI binary was then built with upstream's defaults
 * instead of FOG's, which is what killed the keyboard on ipxe.efi
 * (forums #18213). An overlaid file cannot half-apply the way a sed pattern
 * can, so the next upstream refresh can only ever break this loudly.
 *
 */

/* Drive the USB keyboard ourselves rather than relying on the firmware's.
 *
 * ipxe.efi carries the native xHCI/EHCI/UHCI drivers and efi_driver_connect_all()
 * binds them, which takes the controller away from the firmware and with it the
 * firmware's SimpleTextInput. Upstream's default for EFI is to leave USB_KEYBOARD
 * undefined and re-expose the devices through USB_EFI so the firmware's own
 * keyboard driver can re-bind on top; on hardware where that re-bind does not
 * happen (Lenovo M70t/M80t Gen3, and this is not a new class of firmware bug)
 * there is then no keyboard driver at all and the machine is unusable at the
 * boot menu. snponly.efi is unaffected either way -- it has no native host
 * controller drivers, so the firmware keeps USB.
 *
 * This is the configuration FOG shipped and tested for years, restored rather
 * than invented. USB_HCD_USBIO is upstream-labelled "very slow", which it is,
 * but it only ever drives the keyboard, and correctness at a boot menu beats
 * throughput.
 */
#define USB_HCD_USBIO		/* EFI USB pseudo-host controller */
#define USB_KEYBOARD		/* USB keyboards */
#undef USB_EFI			/* Conflicts with driving USB ourselves */

#endif /* CONFIG_LOCAL_USB_H */
