//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#import <Foundation/Foundation.h>


@class WirekiteDevice;
@class WirekiteService;

typedef long PortID;


/*! @brief Additional features of digital inputs.*/
typedef NS_OPTIONS(NSUInteger, DigitalInputPinAttributes) {
    /*! @brief Default. No special features enabled. */
    DigitalInputPinAttributesDefault        = 0,
    /*! @brief Enable pull-up. */
    DigitalInputPinAttributesPullup         = 4,
    /*! @brief Enable pull-down. */
    DigitalInputPinAttributesPulldown       = 8,
    /*! @brief Trigger notification on raising edge of signal. */
    DigitalInputPinAttributesTriggerRaising = 16,
    /*! @brief Trigger notification on failling edge of signal. */
    DigitalInputPinAttributesTriggerFalling = 32
};


/*! @brief Additional features of digital outputs. */
typedef NS_OPTIONS(NSUInteger, DigitalOutputPinAttributes) {
    /*! @brief Default. No special features enabled. */
    DigitalOutputPinAttributesDefault       = 0,
    /*! @brief Drive signal with low current. */
    DigitalOutputPinAttributesLowCurrent    = 4,
    /*! @brief Drive signal with high current. */
    DigitalOutputPinAttributesHighCurrent   = 8
};


/*! @brief Communication type for input pins. */
typedef NS_ENUM(NSInteger, InputCommunication) {
    /*! @brief Read input value on demand. */
    InputCommunicationOnDemand,
    /*! @brief Precache input value. */
    InputCommunicationPrecached
};


/*! @brief Analog pin */
typedef NS_ENUM(NSInteger, AnalogPin) {
    /*! @brief Analog pin A0 */
    AnalogPinA0  = 0,
    /*! @brief Analog pin A1 */
    AnalogPinA1  = 1,
    /*! @brief Analog pin A2 */
    AnalogPinA2  = 2,
    /*! @brief Analog pin A3 */
    AnalogPinA3  = 3,
    /*! @brief Analog pin A4 */
    AnalogPinA4  = 4,
    /*! @brief Analog pin A5 */
    AnalogPinA5  = 5,
    /*! @brief Analog pin A6 */
    AnalogPinA6  = 6,
    /*! @brief Analog pin A7 */
    AnalogPinA7  = 7,
    /*! @brief Analog pin A8 */
    AnalogPinA8  = 8,
    /*! @brief Analog pin A9 */
    AnalogPinA9  = 9,
    /*! @brief Analog pin A10 */
    AnalogPinA10 = 10,
    /*! @brief Analog pin A11 */
    AnalogPinA11 = 11,
    /*! @brief Analog pin A12 */
    AnalogPinA12 = 12,
    /*! @brief Analog pin A13 */
    AnalogPinA13 = 13,
    /*! @brief Analog pin A14 */
    AnalogPinA14 = 14,
    /*! @brief Analog pin A15 */
    AnalogPinA15 = 15,
    /*! @brief Analog pin A16 */
    AnalogPinA16 = 16,
    /*! @brief Analog pin A17 */
    AnalogPinA17 = 17,
    /*! @brief Analog pin A18 */
    AnalogPinA18 = 18,
    /*! @brief Analog pin A19 */
    AnalogPinA19 = 19,
    /*! @brief Analog pin A20 */
    AnalogPinA20 = 20,
    /*! @brief Vref / Vref high */
    AnalogPinVREF = 128,
    /*! @brief Temperature */
    AnalogPinTemp = 129,
    /*! @brief Vref low */
    AnalogPinVREFL = 130,
    /*! @brief Band gap */
    AnalogPinBandGap = 131
};


/*! @brief Additional features of PWM timers */
typedef NS_OPTIONS(NSUInteger, PWMTimerAttributes) {
    /*! @brief Default. No special features enabled. */
    PWMTimerAttributesDefault = 0,
    /*! @brief Edge-aligned PWM signals. */
    PWMTimerAttributesEdgeAligned = 0,
    /*! @brief Center-aligned PWM signals. */
    PWMTimerAttributesCenterAligned = 1
};


/*! @brief Additional features of PWM channels */
typedef NS_OPTIONS(NSUInteger, PWMChannelAttributes) {
    /*! @brief Default. No special features enabled. */
    PWMChannelAttributesDefault = 0,
    /*! @brief Output high on pulse */
    PWMChannelAttributesHighPulse = 0,
    /*! @brief Output low on pulse */
    PWMChannelAttributesLowPulse = 1
};

/*! @brief I2C SCL/SDA pin pairs */
typedef NS_ENUM(NSInteger, I2CPins) {
    /*! @brief SCL/SDA pin pair 16/17 for I2C module 0 */
    I2CPinsSCL16_SDA17 = 0,
    /*! @brief SCL/SDA pin pair 19/18 for I2C module 0 */
    I2CPinsSCL19_SDA18 = 1,
    /*! @brief SCL/SDA pin pair 22/23 for I2C module 1 (Teensy LC only) */
    I2CPinsSCL22_SDA23 = 2,
    /*! @brief SCL/SDA pin pair 29/30 for I2C module 1 (Teensy 3.2 only)*/
    I2CPinsSCL29_SDA30 = 2
};

/*! @brief Result code for I2C send and receive transactions */
typedef NS_ENUM(NSInteger, I2CResult) {
    /*! @brief Action was successful */
    I2CResultOK = 0,
    /*! @brief Action timed out */
    I2CResultTimeout = 1,
    /*! @brief Action was cancelled due to a lost bus arbitration */
    I2CResultArbitrationLost = 2,
    /*! @brief Slave address was not acknowledged */
    I2CResultAddressNAK = 3,
    /*! @brief Transmitted data was not acknowledged */
    I2CResultDataNAK = 4,
    /*! @brief Wirekite has insufficient memory to buffer the data */
    I2CResultOutOfMemory = 5,
    /*! @brief I2C bus is budy */
    I2CResultBusBusy = 6,
    /*! @brief Unknown error occurred */
    I2CResultUnknownError = 7,
    /*! @brief An invalid parameter was specified */
    I2CResultInvalidParameter = 8
};

/*! @brief Additional settings for SPI bus */
typedef NS_OPTIONS(NSUInteger, SPIAttributes) {
    /*! @brief Default. No special features enabled. */
    SPIAttributesDefault = 0,
    /*! @brief Transmit/receive most significant bit (MSB) first */
    SPIAttributesMSBFirst = 0,
    /*! @brief Transmit/receive least significant bit (LSB) first */
    SPIAttributesLSBFirst = 1,
    /*! @brief Transmit/receive in SPI mode 0 (CPOL = 0 / clock idles in low / CPHA = 0 / "out" changes on trailing clock edge / "in" is cpatured on leading clock edge  */
    SPIAttributesMode0 = 0,
    /*! @brief Transmit/receive in SPI mode 1 (CPOL = 0 / clock idles in low / CPHA = 1 / "out" changes on leading clock edge / "in" is cpatured on trailing clock edge  */
    SPIAttributesMode1 = 4,
    /*! @brief Transmit/receive in SPI mode 2 (CPOL = 1 / clock idles in high / CPHA = 0 / "out" changes on trailing clock edge / "in" is cpatured on leading clock edge  */
    SPIAttributesMode2 = 8,
    /*! @brief Transmit/receive in SPI mode 3 (CPOL = 1 / clock idles in high / CPHA = 1 / "out" changes on leading clock edge / "in" is cpatured on trailing clock edge  */
    SPIAttributesMode3 = 16
};

/*! @brief Result code for SPI send and receive transactions */
typedef NS_ENUM(NSInteger, SPIResult) {
    /*! @brief Action was successful */
    SPIResultOK = 0,
    /*! @brief Action timed out */
    SPIResultTimeout = 1,
    /*! @brief Unknown error occurred */
    SPIResultUnknownError = 7,
    /*! @brief An invalid parameter was specified */
    SPIResultInvalidParameter = 8
};


/*! @brief Board information item that can be queried */
typedef NS_ENUM(NSInteger, BoardInfo) {
    /*! @brief Number of bytes available for buffering messages */
    BoardInfoAvailableMemory = 1,
    /*! @brief Maxium message size that can currently be buffered */
    BoardInfoMaximumMemoryBlock = 2,
    /*! @brief Board type: 1 for Teensy LC, 2 for Teensy 3.2 */
    BoardInfoBoardType = 3,
    /*! @brief Firmware version in BCD */
    BoardInfoFirmwareVersion = 4
};


typedef void (^DigitalInputPinCallback)(PortID, BOOL);
typedef void (^AnalogInputPinCallback)(PortID, double);


/*! @brief Invalid port ID
 */
extern long InvalidPortID;


/*! @brief Delegate protocol for notifications about the device
 */
@protocol WirekiteDeviceDelegate

/*! @brief Called after the device has been disconnected from the computer.
 
    @discussions All ports are invalid and no longer work.
 
    If a device is disconnected, both the service delegate and
    the device delegate are called.
 
    @param device the removed device
 */
- (void) disconnectedDevice: (WirekiteDevice* _Nonnull) device;

@end


/*! @brief Wirekit device
 */
@interface WirekiteDevice : NSObject


/*!
    @name Life-cycle
 */


/*! @brief Delegate for notifications about the device.
 */
@property (weak) id<WirekiteDeviceDelegate> _Nullable delegate;

/*! @brief Wirekite serivce that created this device.
 */
@property WirekiteService* _Nullable wirekiteService;

/*! @brief Creates a device
 
    @discussion Do not create devices yourself. Instead have the @[WirekiteService] create them.
 */
- (instancetype _Nonnull ) init;

/*! @brief Closes the communication to the device.
 
    @discussion After the device is closed, it is no longer possible to communicate with it.
        You will have to unplug and reattach it.
 */
- (void) close;

/*! @brief Resets the device to its initial state.
 
    @discussion Releases all ports
 */
- (void) resetConfiguration;

/*! @brief Indicates if the device has been closed (or disconnected).
 */
-(bool)isClosed;


/*!
    @name Board information
 */

/*!
    @brief Queries an information item of the board.
 
    @param boardInfo the information item to query
 
    @return the value of the information item
 */
- (long) boardInfo:(BoardInfo)boardInfo;

/*!
    @name Working with digital input and output pins
 */


/*! @brief Configures a pin as a digital output.
 
    @param pin the pin number
 
    @param attributes attributes of the digital output (such as current strength)
 
    @return the port ID
 */
- (PortID) configureDigitalOutputPin: (long)pin attributes: (DigitalOutputPinAttributes)attributes;

/*! @brief Configures a pin as a digital output.
 
    @param pin the pin number
 
    @param attributes attributes of the digital output (such as current strength)
 
    @param initialValue the initial value of the output: YES / true / 1 for high, NO / false / 0 for low
 
    @return the port ID
 */
- (PortID) configureDigitalOutputPin: (long)pin attributes: (DigitalOutputPinAttributes)attributes initialValue: (BOOL)initialValue;

/*! @brief Configures a pin as a digital input.
 
    @discussion The digital input is either read on-demand (requiring an I/O transaction with the device) or is pre-cached (all changes are immediately sent from the device and the last value is cached). Pre-cached requires that the selected pin supports interrupts.
 
    @param pin the pin number

    @param attributes attributes of the digital input (such as pull-up, pull-down)

    @param communication the type of communication used, either @[InputCommunicationOnDemand] or @c[InputCommunicationPrecached]

    @return the port ID
 */
- (PortID) configureDigitalInputPin: (long)pin attributes: (DigitalInputPinAttributes)attributes
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
- (PortID) configureDigitalInputPin: (long)pin attributes: (DigitalInputPinAttributes)attributes notification: (DigitalInputPinCallback _Nullable)notifyBlock;

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
- (PortID) configureDigitalInputPin: (long)pin attributes: (DigitalInputPinAttributes)attributes dispatchQueue: (dispatch_queue_t _Nonnull)dispatchQueue notification: (DigitalInputPinCallback _Nullable)notifyBlock;

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


/*!
 @name Working with analog input pins
 */


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
- (PortID) configureAnalogInputPin: (AnalogPin)pin interval:(long)interval notification: (AnalogInputPinCallback _Nullable)notifyBlock;

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
- (PortID) configureAnalogInputPin: (AnalogPin)pin interval:(long)interval dispatchQueue: (dispatch_queue_t _Nonnull)dispatchQueue notification: (AnalogInputPinCallback _Nullable)notifyBlock;

/*! @brief Releases the analog input or output pin
 
    @param port the port ID of the pin
 */
- (void) releaseAnalogPinOnPort: (PortID)port;

/*! @brief Reads the current analog value on the specified pin.
 
    @discussion Read an analog values takes some time. It requires a communication between
        the host and the device and the digital-to-analog conversion also takes noticeable time.
 
    @param port the port ID of the pin
 
    @return returns the read value (in the range [-1 to 1])
 */
- (double) readAnalogPinOnPort: (PortID)port;


/*!
 @name Working with PWM output
 */


/*! @brief Configures a pin as a PWM output.
 
    @param pin the pin number as labelled on board
 
    @return the port ID
 */
- (PortID) configurePWMOutputPin: (long)pin;

/*! @brief Configures a pin as a PWM output.
 
    @param pin the pin number as labelled on board
 
    @param initialDutyCycle intitial duty cycle between 0 (for 0%) and 1 (for 100%)
 
    @return the port ID
 */
- (PortID) configurePWMOutputPin: (long)pin initialDutyCycle: (double)initialDutyCycle;

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

- (void) configurePWMTimer: (long) timer frequency: (long) frequency attributes: (PWMTimerAttributes) attributes;

/*! @brief Configures a timer associated with PWM outputs.
 
    @discussion Each channel can be associated with several PWM outputs.
 
    @param timer the timer index (0 .. n, depending on the board)
 
    @param channel the channel index (0 .. n, depending on the board and the timer)
 
    @param attributes PWM attributes such as edge/center aligned
 */
- (void) configurePWMChannel:(long)timer channel:(long)channel attributes: (PWMChannelAttributes) attributes;

/*! @brief Sets the duty cycle of a PWM output
 
    @param dutyCycle the duty cycle between 0 (for 0%) and 1 (for 100%)
 */
- (void) writePWMPinOnPort: (PortID)port dutyCycle:(double)dutyCycle;


/*!
 @name I2C communication
 */

/*! @brief Configures an I2C port as a master.
 
    @discussion Each pin pair belongs to a specific I2C module. A single module can only
        be conntected to a single pin pair at a time.
 
    @param pins the SCL/SDA pin pair for the port
 
    @frequency the frequency of for the I2C communication (in Hz). If in doubt, use 100,000 Hz.
 
    @return the I2C port ID
 */
- (PortID) configureI2CMaster: (I2CPins)pins frequency:(long)frequency;


/*! @brief Releases the I2C output
 
    @param port the I2C port ID
 */
- (void) releaseI2CPort: (PortID)port;

/*! @brief Send data to an I2C slave
 
     @discussion The operation performs a complete I2C transaction, starting with a START condition
        and ending with a STOP condition.
     
     @discussion The request is executed sychnronously, i.e. the call blocks until the data
        has been transmitted or the transmission has failed.
     
     @discussion If less than the specified number of bytes are transmitted,
        [WirekiteDevice lastI2CResult:] returns the associated reason.
     
     @param port the I2C port ID
     
     @param data the data to transmit
     
     @param slave the slave address
     
     @return the number of sent bytes
 */
- (long) sendOnI2CPort: (PortID)port data: (NSData* _Nonnull)data toSlave: (long)slave;

/*! @brief Submits data to be sent to an I2C slave
 
     @discussion The operation performs a complete I2C transaction, starting with a START condition
        and ending with a STOP condition.
     
     @discussion The request is executed asychnronously, i.e. the call returns immediately. If the
        transaction fails, a message appears in the log.
     
     @param port the I2C port ID
     
     @param data the data to transmit
     
     @param slave the slave address
 */
- (void) submitOnI2CPort: (PortID)port data: (NSData* _Nonnull)data toSlave: (long)slave;

/*! @brief Request data from an I2C slave
 
    @discussion The operation performs a complete I2C transaction, starting with a START condition
        and ending with a STOP condition.
 
    @discussion The operation is executed sychnronously, i.e. the call blocks until the
        transaction has been completed or has failed. If the transaction fails,
        use [WirekiteDevice lastI2CResult:] to retrieve the reason.
 
    @param port the I2C port ID
 
    @param slave the slave address
 
    @param length the number of bytes of data requested from the slave
 
    @return the received data or `nil` if it fails
 */
- (NSData* _Nullable) requestDataOnI2CPort: (PortID)port fromSlave: (long)slave length: (long)length;

/*! @brief Send data to and request data from an I2C slave in a single operation
 
    @discussion The operation performs a complete I2C transaction, starting with a START condition,
        a RESTART condition when switching from transmission to receipt, and ending with
        a STOP condition.
 
    @discussion The request is executed sychnronously, i.e. the call blocks until the data
        has been transmitted and received, or the transmission has failed.
 
    @discussion If less than the specified number of bytes are transmitted, `nil` is returned and
        [WirekiteDevice lastI2CResult:] returns the associated reason.

    @param port the I2C port ID

    @param data the data to transmit

    @param slave the slave address
 
    @param receiveLength the number of bytes of data request from the slave

    @return the received data or `nil` if the transaction fails
 */
- (NSData* _Nullable) sendAndRequestOnI2CPort: (PortID)port data: (NSData* _Nonnull)data toSlave: (long)slave receiveLength: (long)receiveLength;

/*! @brief Result code of the last send or receive
 
    @param port the I2C port ID
 
    @return the result code of the last operation on this port
 */
- (I2CResult) lastResultOnI2CPort: (PortID)port;


/*!
 @name SPI communication
 */

/*! @brief Configures a SPI port as a master.
 
    @discussion The pins are specified with the index as printed on the Teensy board.
         The MISO pin is optional and can be ommitted if there is no communication from
         the slave to the master.
 
    @param sckPin the index of the pin to use for the SCK signal (serial clock)
 
    @param mosiPin the index of the pin to use for the MOSI signal (master out - slave in)
 
    @param misoPin the index of the pin to use for the MISO signal (master in - slave out) or -1 if not used
 
    @frequency the frequency for the SPI communication (in Hz). If in doubt, use 100,000 Hz.
 
    @attributes additional settings of the SPI bus
 
    @return the SPI port ID
 */
-(PortID) configureSPIMasterForSCKPin: (long)sckPin mosiPin:(long)mosiPin misoPin:(long)misoPin frequency:(long)frequency attributes:(SPIAttributes)attributes;


/*! @brief Releases the SPI port
 
    @param port the SPI port ID
 */
-(void) releaseSPIPort: (PortID)port;


/*! @brief Transmit data to a SPI slave
 
    @discussion The operation performs a complete SPI transaction, i.e. enables the clock for the duration of
        transation and transmits the data. Optionally, a digital output can be used as the chip select (CS),
        which is then held low for the duration of the transaction and set to high at the end of the transaction.
 
     @discussion The request is executed sychnronously, i.e. the call blocks until the data
         has been transmitted or the transmission has failed.
 
     @discussion If less than the specified number of bytes are transmitted,
         [WirekiteDevice lastSPIResult:] returns the associated reason.
 
    @param port the SPI port ID
 
    @param data the data to transmit
 
    @param chipSelect the digital output port ID to use as chip select (or `InvalidPortID` if not used)
 
    @return the number of sent bytes
 */
-(long) transmitOnSPIPort:(PortID)port data:(NSData* _Nonnull)data chipSelect:(PortID)chipSelect;


/*! @brief Submits data to be transmitted to an SPI slave
 
    @discussion The operation performs a complete SPI transaction, i.e. enables the clock for the duration of
        transation and transmits the data. Optionally, a digital output can be used as the chip select (CS),
        which is then held low for the duration of the transaction and set to high at the end of the transaction.

    @discussion The request is executed asychnronously, i.e. the call returns immediately. If the
        transaction fails, a message appears in the log.
 
    @param port the SPI port ID
 
    @param data the data to transmit
 
    @param chipSelect the digital output port ID to use as chip select (or `InvalidPortID` if not used)
 */
-(void) submitOnSPIPort:(PortID)port data:(NSData* _Nonnull)data chipSelect:(PortID)chipSelect;

/*! @brief Result code of the last transmission or receipt
 
    @param port the SPI port ID
 
    @return the result code of the last operation on this port
 */
-(SPIResult) lastResultOnSPIPort:(PortID)port;


@end
