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

/*! @brief Called after a device has been added.
 
 @param newDevice the added device
 */
-(void)deviceAdded: (WirekiteDevice*) newDevice;


/*! @brief Called after a device has been removed.

    @remark If a device is removed, both the service delegate and 
        the device delegate are called.
 
 @param removedDevice the removed device
 */
-(void)deviceRemoved: (WirekiteDevice*) removedDevice;

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
