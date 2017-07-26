//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>

@interface WirekiteDevice (Internal)

- (BOOL) registerNotificationOnPart: (IONotificationPortRef)notifyPort device: (io_service_t) usbDevice;
- (BOOL) openDevice: (IOUSBDeviceInterface**) devInterface;

@end
