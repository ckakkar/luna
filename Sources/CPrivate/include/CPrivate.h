// Private macOS display APIs, resolved at runtime.
//
// Every function here looks its symbol up once with dlsym. When macOS doesn't have it (an older or
// newer release, or Intel vs Apple Silicon), the wrapper reports that instead of crashing, and Luna
// falls back to another way of controlling the display.
#ifndef LUNA_CPRIVATE_H
#define LUNA_CPRIVATE_H

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOKitLib.h>
#include <stdbool.h>
#include <stdint.h>

CF_ASSUME_NONNULL_BEGIN

#pragma mark - DisplayServices (built-in and Apple displays)

bool LunaDSCanChangeBrightness(CGDirectDisplayID display);
/// 0 on success. `brightness` is 0–1.
int LunaDSGetBrightness(CGDirectDisplayID display, float *brightness);
int LunaDSSetBrightness(CGDirectDisplayID display, float brightness);
/// Calls `callback` whenever the display's brightness changes (keys, Control Center, ambient light).
/// The new value (0–1) is under "value" in the userInfo dictionary.
int LunaDSRegisterForBrightnessChanges(CGDirectDisplayID display, const void *observer, CFNotificationCallback callback);
void LunaDSUnregisterForBrightnessChanges(CGDirectDisplayID display, const void *observer);

#pragma mark - CoreDisplay

/// The display's info dictionary (vendor, product, serial, IODisplayLocation, AirPlay/virtual flags…), or NULL.
CFDictionaryRef _Nullable LunaCoreDisplayCreateInfoDictionary(CGDirectDisplayID display) CF_RETURNS_RETAINED;

#pragma mark - IOAVService (DDC on Apple Silicon)

bool LunaAVServiceIsAvailable(void);
/// Wraps a DCPAVServiceProxy registry entry. NULL if the service can't be created.
CFTypeRef _Nullable LunaAVServiceCreate(io_service_t service) CF_RETURNS_RETAINED;
IOReturn LunaAVServiceWriteI2C(CFTypeRef service, uint32_t chipAddress, uint32_t dataAddress, const void *buffer, uint32_t length);
IOReturn LunaAVServiceReadI2C(CFTypeRef service, uint32_t chipAddress, uint32_t offset, void *buffer, uint32_t length);

#pragma mark - I2C over IOFramebuffer (DDC on Intel)

/// Sends `send` (which starts with the 0x51 source byte) to the display's DDC address. When `reply` is
/// non-NULL, waits `replyDelayMs` and reads `replyLength` bytes back. Tries each I2C bus until one works.
IOReturn LunaIntelDDCTransfer(CGDirectDisplayID display, const uint8_t *send, uint32_t sendLength,
                              uint8_t *_Nullable reply, uint32_t replyLength, uint32_t replyDelayMs);

#pragma mark - Turning displays off and on

bool LunaCanConfigureDisplayEnabled(void);
/// Within CGBeginDisplayConfiguration/CGCompleteDisplayConfiguration: detach (`enabled` false) or reattach a display.
CGError LunaConfigureDisplayEnabled(CGDisplayConfigRef config, CGDirectDisplayID display, bool enabled);

CF_ASSUME_NONNULL_END

#endif
