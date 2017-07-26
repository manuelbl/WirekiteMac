//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#import <Foundation/Foundation.h>

@class WirekiteDevice;


@protocol WirekiteServiceDelegate

- (void) deviceAdded: (WirekiteDevice*) newDevice;
- (void) deviceRemoved: (WirekiteDevice*) removedDevice;

@end


@interface WirekiteService : NSObject

@property (weak) id<WirekiteServiceDelegate> delegate;

;- (instancetype) init;

- (void) start;

@end
