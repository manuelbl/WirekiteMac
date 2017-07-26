//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#import <Foundation/Foundation.h>


@class WirekiteDevice;

typedef uint16_t PortID;


typedef NS_OPTIONS(NSUInteger, DigitalInputPinAttributes) {
    DigitalInputPinAttributesDefault        = 0,
    DigitalInputPinAttributesPullup         = 4,
    DigitalInputPinAttributesPulldown       = 8,
    DigitalInputPinAttributesTriggerRaising = 16,
    DigitalInputPinAttributesTriggerFalling = 32
};

typedef NS_OPTIONS(NSUInteger, DigitalOutputPinAttributes) {
    DigitalOutputPinAttributesDefault       = 0,
    DigitalOutputPinAttributesLowCurrent    = 4,
    DigitalOutputPinAttributesHighCurrent   = 8
};

typedef NS_ENUM(NSInteger, InputCommunication) {
    InputCommunicationOnDemand,
    InputCommunicationPrecached
};

typedef NS_ENUM(NSInteger, AnalogPin) {
    AnalogPinA0  = 0,
    AnalogPinA1  = 1,
    AnalogPinA2  = 2,
    AnalogPinA3  = 3,
    AnalogPinA4  = 4,
    AnalogPinA5  = 5,
    AnalogPinA6  = 6,
    AnalogPinA7  = 7,
    AnalogPinA8  = 8,
    AnalogPinA9  = 9,
    AnalogPinA10 = 10,
    AnalogPinA11 = 11,
    AnalogPinA12 = 12,
    AnalogPinVREF = 128,
    AnalogPinTemp = 129,
    AnalogPinVREFL = 130,
    AnalogPinBandGap = 131
};

typedef NS_ENUM(NSInteger, PWMPin) {
    PWMPin3 = 0,
    PWMPin4 = 1,
    PWMPin6 = 2,
    PWMPin9 = 3,
    PWMPin10 = 4,
    PWMPin16 = 5,
    PWMPin17 = 6,
    PWMPin20 = 7,
    PWMPin22 = 8,
    PWMPin23 = 9
};

typedef NS_OPTIONS(NSUInteger, PWMTimerAttributes) {
    PWMTimerAttributesDefault = 0,
    PWMTimerAttributesEdgeAligned = 0,
    PWMTimerAttributesCenterAligned = 1
};

typedef NS_OPTIONS(NSUInteger, PWMChannelAttributes) {
    PWMChannelAttributesDefault = 0,
    PWMChannelAttributesHighPulse = 0,
    PWMChannelAttributesLowPulse = 1
};


typedef void (^DigitalInputPinCallback)(PortID, BOOL);
typedef void (^AnalogInputPinCallback)(PortID, int16_t);

extern uint16_t InvalidPortID;


@protocol WirekiteDeviceDelegate

- (void) deviceRemoved: (WirekiteDevice*) device;

@end


/*! @brief Wirekit device
 */
@interface WirekiteDevice : NSObject

@property (weak) id<WirekiteDeviceDelegate> delegate;

/*! @brief Creates a device
 
    @discussion Do not create devices yourself. Instead have the @[WirekiteService] create them.
 */
- (instancetype) init;

/*! @brief Closes the communication to the device.
 
    @discussion After the device is closed, it is no longer possible to communicate with it.
        You will have to unplug and reattach it.
 */
- (void) close;

/*! @brief Resets the device to its initial state.
 
    @discussion Releases all ports
 */
- (void) resetConfiguration;


/*! @brief Configures a pin as a digital output.
 
    @param pin the pin number
 
    @param attributes attributes of the digital output (such as current strength)
 
    @return the port ID
*/
- (PortID) configureDigitalOutputPin: (int)pin attributes: (DigitalOutputPinAttributes)attributes;

/*! @brief Configures a pin as a digital input.
 
    @discussion The digital input is either read on-demand (requiring an I/O transaction with the device) or is pre-cached (all changes are immediately sent from the device and the last value is cached). Pre-cached requires that the selected pin supports interrupts.
 
    @param pin the pin number

    @param attributes attributes of the digital input (such as pull-up, pull-down)

    @param communication the type of communication used, either @[InputCommunicationOnDemand] or @c[InputCommunicationPrecached]

    @return the port ID
 */
- (PortID) configureDigitalInputPin: (int)pin attributes: (DigitalInputPinAttributes)attributes
                      communication: (InputCommunication) communication;

/*! @brief Configures a pin as a digital input and notifies about all changes.
 
 @discussion When the digital input changes, the new value is sent to the host
 and the specified notifcation block is called on the main thread.
 Specify as an attribute if notifications should be triggered on the raising,
 the falling or both edges.
 
 Notifications require that the selected pin supports interrupts.
 
 @param pin the pin number
 
 @param attributes attributes of the digital input (such as pull-up, pull-down)
 
 @param notifyBlock the notification block called when the input changes
 
 @return the port ID
 */
- (PortID) configureDigitalInputPin: (int)pin attributes: (DigitalInputPinAttributes)attributes notification: (DigitalInputPinCallback)notifyBlock;

/*! @brief Configures a pin as a digital input and notifies about all changes.
 
 @discussion When the digital input changes, the new value is sent to the host
 and the specified notifcation block is dispatched to the specified queue.
 Specify as an attribute if notifications should be triggered on the raising,
 the falling or both edges.
 
 @param pin the pin number
 
 @param attributes attributes of the digital input (such as pull-up, pull-down)
 
 @param dispatchQueue the queue for dispatching the notifications
 
 @param notifyBlock the notification block called when the input changes
 
 @return the port ID
 */
- (PortID) configureDigitalInputPin: (int)pin attributes: (DigitalInputPinAttributes)attributes dispatchQueue: (dispatch_queue_t)dispatchQueue notification: (DigitalInputPinCallback)notifyBlock;

/*! @brief Releases the digital input or output pin
 
    @param port the port ID of the pin
 */
- (void) releaseDigitalPinOnPort: (PortID)port;

/*! @brief Writes a value to the digital output pin
 
    @discussion Writing a value is an asynchronous operations. The function returns immediately
        without awaiting a confirmation that it has been succeeded.
 
    @param port the port ID of the pin
 
    @param value value to set the pin to: YES / true / 1 for high, NO / false / 0 for low
 */
- (void) writeDigitalPinOnPort: (PortID)port value:(BOOL)value;

/*! @brief Read the current value of a digital input.
 
 @discussion For a digital input with communication mode @[InputCommunicationOnDemand], this
    action will require a communication round-trip to the device and back to the host. For inputs
    configured with communication mode @[InputCommunicationPrecached] or with notifications,
    the value is cached in returned immediately.
 
 @param port the port ID of the pin
 */
- (BOOL) readDigitalPinOnPort: (PortID)port;

/*! @brief Configures a pin as an analog input pin.
 
 @discussion The analog value is read on-demand (requiring an I/O transaction with the device).
 
 @param pin the analog pin
 
 @return the port ID
 */
- (PortID) configureAnalogInputPin: (AnalogPin)pin;

/*! @brief Configures a pin as an analog input pin with automatic sampling at a specified interval.
 
 @discussion The analog value is sampled automatically at the specified interval.
 The new value is sent to the host and the notification block is called. The
 notification block is called on the main thread.
 
 @param pin the analog pin
 
 @param interval interval between two samples (in ms)
 
 @param notifyBlock the notification block to be called for each sample
 
 @return the port ID
 */
- (PortID) configureAnalogInputPin: (AnalogPin)pin interval:(uint32_t)interval notification: (AnalogInputPinCallback)notifyBlock;

/*! @brief Configures a pin as an analog input pin with automatic sampling at a specified interval.
 
 @discussion The analog value is sampled automatically at the specified interval.
 The new value is sent to the host and the notification block is called.
 The notification block is dispatched to the specified queue.
 
 @param pin the analog pin
 
 @param interval interval between two samples (in ms)
 
 @param dispatchQueue the dispatch queue for the notification block
 
 @param notifyBlock the notification block to be called for each sample
 
 @return the port ID
 */
- (PortID) configureAnalogInputPin: (AnalogPin)pin interval:(uint32_t)interval dispatchQueue: (dispatch_queue_t)dispatchQueue notification: (AnalogInputPinCallback)notifyBlock;

/*! @brief Releases the analog input or output pin
 
 @param port the port ID of the pin
 */
- (void) releaseAnalogPinOnPort: (PortID)port;

/*! @brief Reads the current analog value on the specified pin.
 
 @discussion Read an analog values takes some time. It requires a communication between
    the host and the device and the digital-to-analog conversion also takes noticeable time.
 
 @param port the port ID of the pin
 
 @return returns the read value (in the range [-32,768 to 32,767])
 */
- (int16_t) readAnalogPinOnPort: (PortID)port;


/*! @brief Configures a pin as a PWM output.
 
 @param pin the PWM pin
 
 @return the port ID
 */
- (PortID) configurePWMOutputPin: (PWMPin)pin;

/*! @brief Releases the PWM output
 
 @param port the port ID of the pin
 */
- (void) releasePWMPinOnPort: (PortID)port;

/*! @brief Configures a timer associated with PWM outputs.
 
 @discussion Each timer is associated with several PWM outputs.
 
 @param timer the timer index (0 .. n, depending on the board)
 
 @param frequency the frequency of the PWM signal (in Hz)
 
 @param attributes PWM attributes such as edge/center aligned
 */

- (void) configurePWMTimer: (uint8_t) timer frequency: (uint32_t) frequency attributes: (PWMTimerAttributes) attributes;

/*! @brief Configures a timer associated with PWM outputs.
 
 @discussion Each channel can be associated with several PWM outputs.
 
 @param timer the timer index (0 .. n, depending on the board)
 
 @param channel the channel index (0 .. n, depending on the board and the timer)
 
 @param attributes PWM attributes such as edge/center aligned
 */
- (void) configurePWMChannel: (uint8_t) timer channel: (uint8_t) channel attributes: (PWMChannelAttributes) attributes;

/*! @brief Sets the duty cycle of a PWM output
 
    @param dutyCycle the duty cycle between 0 (for 0%) and 32,767 (for 100%)
 */
- (void) writePWMPinOnPort: (PortID)port dutyCycle:(int16_t)dutyCycle;



@end
