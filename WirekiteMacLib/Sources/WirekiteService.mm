//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#import "WirekiteService.h"
#import "WirekiteDevice.h"
#import "WirekiteDeviceInternal.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/usb/IOUSBLib.h>

#define kVendorID         0x16c0
#define kProductID        0x2701


static void DeviceAdded(void *refCon, io_iterator_t iterator);


@interface WirekiteService ()
{
    IONotificationPortRef notifyPort;
    CFRunLoopSourceRef runLoopSource;
    io_iterator_t addedIter;
}

@end


@implementation WirekiteService

- (instancetype) init
{
    self = [super init];
    
    if (self != nil)
    {
        notifyPort = NULL;
        runLoopSource = NULL;
        addedIter = NULL;
    }
    
    return self;
}

- (void) dealloc
{
    _delegate = nil;
    
    IOObjectRelease(addedIter);
    addedIter = NULL;
    
    IONotificationPortDestroy(notifyPort);
    runLoopSource = NULL;
    notifyPort = NULL;
}


- (void) start
{
    int32_t vendorID = kVendorID;
    int32_t productID = kProductID;
    
    CFMutableDictionaryRef matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
    
    CFNumberRef numberRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &vendorID);
    CFDictionarySetValue(matchingDict, CFSTR(kUSBVendorID), numberRef);
    CFRelease(numberRef);
    
    numberRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &productID);
    CFDictionarySetValue(matchingDict, CFSTR(kUSBProductID), numberRef);
    CFRelease(numberRef);
    numberRef = NULL;
    
    notifyPort = IONotificationPortCreate(kIOMasterPortDefault);
    runLoopSource = IONotificationPortGetRunLoopSource(notifyPort);
    
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);
    
    // Now set up a notification to be called when a device is first matched by I/O Kit.
    // This method consume the matchingDict reference.
    kern_return_t kr = IOServiceAddMatchingNotification(notifyPort,// notifyPort
                                     kIOFirstMatchNotification,    // notificationType
                                     matchingDict,                 // matching
                                     DeviceAdded,                  // callback
                                     (__bridge void*) self,        // refCon
                                     &addedIter                    // notification
                                     );
    if (kr) {
        NSLog(@"Wirekite: IOServiceAddMatchingNotification failed with code 0x%08x", kr);
        return;
    }
    
    // Iterate the already connected devices
    DeviceAdded((__bridge void*) self, addedIter);
}


/**
 * Called when a device was added
 */
- (void) onDeviceAdded: (io_iterator_t) iterator
{
    kern_return_t kr;
    io_service_t usbDevice;
    
    while ((usbDevice = IOIteratorNext(iterator))) {
        
        IOCFPlugInInterface **plugInInterface = NULL;
        SInt32 score;
        HRESULT res;

        // We need to create an IOUSBDeviceInterface for our device. This will create the necessary
        // connections between our userland application and the kernel object for the USB Device.
        kr = IOCreatePlugInInterfaceForService(usbDevice, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID,
                                               &plugInInterface, &score);
        
        if (kIOReturnSuccess != kr || !plugInInterface) {
            NSLog(@"Wirekite: IOCreatePlugInInterfaceForService failed with code 0x%08x", kr);
            IOObjectRelease(usbDevice);
            continue;
        }
        
        WirekiteDevice* device = [[WirekiteDevice alloc] init];
        
        if (! [device registerNotificationOnPart:notifyPort device: usbDevice]) {
            IOObjectRelease(usbDevice);
            continue;
        }

        IOUSBDeviceInterface** deviceInterface = NULL;
        
        // Use the plugin interface to retrieve the device interface.
        res = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
                                                 (LPVOID*) &deviceInterface);
        
        // Now done with the plugin interface.
        (*plugInInterface)->Release(plugInInterface);
        plugInInterface = NULL;
        
        if (res || deviceInterface == NULL) {
            NSLog(@"Wirekite: QueryInterface failed with result %d", (int) res);
            IOObjectRelease(usbDevice);
            continue;
        }
        
        if (! [device openDevice:deviceInterface]) {
            (*deviceInterface)->Release(deviceInterface);
            IOObjectRelease(usbDevice);
            continue;
        }
        
        (*deviceInterface)->Release(deviceInterface);
        
        if (_delegate)
            [_delegate deviceAdded: device];

        IOObjectRelease(usbDevice);
    }
}


@end


/**
  * Called when a device was added
  */
void DeviceAdded(void *refCon, io_iterator_t iterator)
{
    WirekiteService* service = (__bridge WirekiteService*) refCon;
    [service onDeviceAdded: iterator];
}

