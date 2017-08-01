//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#import <Foundation/Foundation.h>

@class WirekiteDevice;


/*! @brief Delegate called if a device has been added or removed.
 */
@protocol WirekiteServiceDelegate

/*! @brief Called after a device has been connected.
 
    @param device the connected device
 */
-(void)connectedDevice: (WirekiteDevice*) device;


/*! @brief Called after a device has been disconnected.

    @Discussion If a device is disconnected, both the service delegate and
        the device delegate are called.
 
    @param device the disconnected device
 */
-(void)disconnectedDevice: (WirekiteDevice*) device;

@end


/*! @brief Service that notifies about added and removed devices.
 
    @discussion When the service is started, a notification for all
        already connected devices is triggered.
 */
@interface WirekiteService : NSObject

/*! @brief Delegate called when a device is added or removed.
 */
@property (weak) id<WirekiteServiceDelegate> delegate;

/*! @brief Creates a new service instance
 */
-(instancetype)init;

/*! @brief Starts the service
 */
-(void)start;

@end
