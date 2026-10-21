#include "CPrivate.h"

#include <IOKit/graphics/IOGraphicsLib.h>
#include <IOKit/i2c/IOI2CInterface.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <unistd.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// Looks a symbol up once, in `path` if it loads, else in everything already loaded.
static void *lookup(const char *path, const char *name) {
    void *handle = path ? dlopen(path, RTLD_LAZY | RTLD_GLOBAL) : NULL;
    void *symbol = handle ? dlsym(handle, name) : NULL;
    return symbol ? symbol : dlsym(RTLD_DEFAULT, name);
}

#define DISPLAY_SERVICES "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
#define CORE_DISPLAY "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"
#define SKYLIGHT "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
#define IOKIT_PATH "/System/Library/Frameworks/IOKit.framework/IOKit"

// Declares `static T name(void)`, returning the looked-up function pointer of type T (or NULL).
#define RESOLVE(T, name, path, symbol)                                                                     \
    static T name(void) {                                                                                  \
        static T fn;                                                                                       \
        static dispatch_once_t once;                                                                       \
        dispatch_once(&once, ^{ fn = (T)lookup(path, symbol); });                                         \
        return fn;                                                                                         \
    }

#pragma mark - DisplayServices

typedef bool (*CanChangeFn)(CGDirectDisplayID);
typedef int (*GetBrightnessFn)(CGDirectDisplayID, float *);
typedef int (*SetBrightnessFn)(CGDirectDisplayID, float);
typedef int (*RegisterFn)(CGDirectDisplayID, const void *, CFNotificationCallback);
typedef int (*UnregisterFn)(CGDirectDisplayID, const void *);

RESOLVE(CanChangeFn, dsCanChange, DISPLAY_SERVICES, "DisplayServicesCanChangeBrightness")
RESOLVE(GetBrightnessFn, dsGet, DISPLAY_SERVICES, "DisplayServicesGetBrightness")
RESOLVE(SetBrightnessFn, dsSet, DISPLAY_SERVICES, "DisplayServicesSetBrightness")
RESOLVE(RegisterFn, dsRegister, DISPLAY_SERVICES, "DisplayServicesRegisterForBrightnessChangeNotifications")
RESOLVE(UnregisterFn, dsUnregister, DISPLAY_SERVICES, "DisplayServicesUnregisterForBrightnessChangeNotifications")

bool LunaDSCanChangeBrightness(CGDirectDisplayID display) {
    CanChangeFn fn = dsCanChange();
    return fn && dsGet() && dsSet() && fn(display);
}

int LunaDSGetBrightness(CGDirectDisplayID display, float *brightness) {
    GetBrightnessFn fn = dsGet();
    return fn ? fn(display, brightness) : -1;
}

int LunaDSSetBrightness(CGDirectDisplayID display, float brightness) {
    SetBrightnessFn fn = dsSet();
    return fn ? fn(display, brightness) : -1;
}

int LunaDSRegisterForBrightnessChanges(CGDirectDisplayID display, const void *observer, CFNotificationCallback callback) {
    RegisterFn fn = dsRegister();
    return fn ? fn(display, observer, callback) : -1;
}

void LunaDSUnregisterForBrightnessChanges(CGDirectDisplayID display, const void *observer) {
    UnregisterFn fn = dsUnregister();
    if (fn) fn(display, observer);
}

#pragma mark - CoreDisplay

typedef CFDictionaryRef (*InfoDictionaryFn)(CGDirectDisplayID);
RESOLVE(InfoDictionaryFn, cdInfo, CORE_DISPLAY, "CoreDisplay_DisplayCreateInfoDictionary")

CFDictionaryRef LunaCoreDisplayCreateInfoDictionary(CGDirectDisplayID display) {
    InfoDictionaryFn fn = cdInfo();
    return fn ? fn(display) : NULL;
}

#pragma mark - IOAVService

typedef CFTypeRef (*AVCreateFn)(CFAllocatorRef, io_service_t);
typedef IOReturn (*AVWriteFn)(CFTypeRef, uint32_t, uint32_t, const void *, uint32_t);
typedef IOReturn (*AVReadFn)(CFTypeRef, uint32_t, uint32_t, void *, uint32_t);

RESOLVE(AVCreateFn, avCreate, IOKIT_PATH, "IOAVServiceCreateWithService")
RESOLVE(AVWriteFn, avWrite, IOKIT_PATH, "IOAVServiceWriteI2C")
RESOLVE(AVReadFn, avRead, IOKIT_PATH, "IOAVServiceReadI2C")

bool LunaAVServiceIsAvailable(void) { return avCreate() && avWrite() && avRead(); }

CFTypeRef LunaAVServiceCreate(io_service_t service) {
    AVCreateFn fn = avCreate();
    return fn ? fn(kCFAllocatorDefault, service) : NULL;
}

IOReturn LunaAVServiceWriteI2C(CFTypeRef service, uint32_t chipAddress, uint32_t dataAddress, const void *buffer, uint32_t length) {
    AVWriteFn fn = avWrite();
    return fn ? fn(service, chipAddress, dataAddress, buffer, length) : kIOReturnUnsupported;
}

IOReturn LunaAVServiceReadI2C(CFTypeRef service, uint32_t chipAddress, uint32_t offset, void *buffer, uint32_t length) {
    AVReadFn fn = avRead();
    return fn ? fn(service, chipAddress, offset, buffer, length) : kIOReturnUnsupported;
}

#pragma mark - Intel I2C

typedef void (*ServiceForDisplayFn)(CGDirectDisplayID, io_service_t *);
typedef io_service_t (*IOServicePortFn)(CGDirectDisplayID);
RESOLVE(ServiceForDisplayFn, cgsServiceForDisplay, NULL, "CGSServiceForDisplayNumber")
RESOLVE(IOServicePortFn, cgIOServicePort, NULL, "CGDisplayIOServicePort")

static io_service_t framebufferForDisplay(CGDirectDisplayID display) {
    io_service_t service = 0;
    ServiceForDisplayFn byNumber = cgsServiceForDisplay();
    if (byNumber) byNumber(display, &service);
    if (!service) {
        IOServicePortFn byPort = cgIOServicePort();
        if (byPort) service = byPort(display);
    }
    return service;
}

static bool supportsDDCciReply(io_service_t interface) {
    CFNumberRef types = IORegistryEntryCreateCFProperty(interface, CFSTR(kIOI2CTransactionTypesKey), kCFAllocatorDefault, 0);
    if (!types) return false;
    uint64_t mask = 0;
    CFNumberGetValue(types, kCFNumberSInt64Type, &mask);
    CFRelease(types);
    return (mask & (1 << kIOI2CDDCciReplyTransactionType)) != 0;
}

IOReturn LunaIntelDDCTransfer(CGDirectDisplayID display, const uint8_t *send, uint32_t sendLength,
                              uint8_t *reply, uint32_t replyLength, uint32_t replyDelayMs) {
    io_service_t framebuffer = framebufferForDisplay(display);
    if (!framebuffer) return kIOReturnNotFound;

    IOItemCount buses = 0;
    if (IOFBGetI2CInterfaceCount(framebuffer, &buses) != kIOReturnSuccess) return kIOReturnNotFound;

    IOReturn result = kIOReturnNotFound;
    for (IOOptionBits bus = 0; bus < buses; bus++) {
        io_service_t interface = 0;
        if (IOFBCopyI2CInterfaceForBus(framebuffer, bus, &interface) != kIOReturnSuccess) continue;

        IOI2CConnectRef connect = NULL;
        if (IOI2CInterfaceOpen(interface, kNilOptions, &connect) == kIOReturnSuccess) {
            IOI2CRequest request = {0};
            request.sendAddress = 0x6E;
            request.sendTransactionType = kIOI2CSimpleTransactionType;
            request.sendBuffer = (vm_address_t)send;
            request.sendBytes = sendLength;
            if (reply) {
                request.replyAddress = 0x6F;
                request.replySubAddress = 0x51;
                request.replyTransactionType = supportsDDCciReply(interface) ? kIOI2CDDCciReplyTransactionType
                                                                             : kIOI2CSimpleTransactionType;
                request.replyBuffer = (vm_address_t)reply;
                request.replyBytes = replyLength;
                request.minReplyDelay = (uint64_t)replyDelayMs * 1000000ULL;
            } else {
                request.replyTransactionType = kIOI2CNoTransactionType;
            }
            result = IOI2CSendRequest(connect, kNilOptions, &request);
            if (result == kIOReturnSuccess) result = request.result;
            IOI2CInterfaceClose(connect, kNilOptions);
        }
        IOObjectRelease(interface);
        if (result == kIOReturnSuccess) break;
    }
    return result;
}

#pragma mark - Display enable

typedef CGError (*ConfigureEnabledFn)(CGDisplayConfigRef, CGDirectDisplayID, bool);
RESOLVE(ConfigureEnabledFn, slsConfigureEnabled, SKYLIGHT, "SLSConfigureDisplayEnabled")
RESOLVE(ConfigureEnabledFn, cgsConfigureEnabled, NULL, "CGSConfigureDisplayEnabled")

static ConfigureEnabledFn configureEnabled(void) {
    ConfigureEnabledFn fn = slsConfigureEnabled();
    return fn ? fn : cgsConfigureEnabled();
}

bool LunaCanConfigureDisplayEnabled(void) { return configureEnabled() != NULL; }

CGError LunaConfigureDisplayEnabled(CGDisplayConfigRef config, CGDirectDisplayID display, bool enabled) {
    ConfigureEnabledFn fn = configureEnabled();
    return fn ? fn(config, display, enabled) : kCGErrorNotImplemented;
}
