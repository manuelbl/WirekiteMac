//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#import "WirekiteDevice.h"
#import "WirekiteDeviceInternal.h"
#import "WirekiteService.h"
#import "proto.h"
#import "PendingRequestList.hpp"
#import "PortList.hpp"
#import "Throttler.hpp"
#import "MessageDump.hpp"

#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/usb/IOUSBLib.h>



#define EndpointTransmit 2
#define EndpointReceive  1

#define RX_BUFFER_SIZE 512


static void DeviceNotification(void *refCon, io_service_t service, natural_t messageType, void *messageArgument);
static void WriteCompletion(void *refCon, IOReturn result, void *arg0);
static void ReadCompletion(void *refCon, IOReturn result, void *arg0);

long InvalidPortID = 0xffff;


enum DeviceStatus {
    StatusInitializing,
    StatusReady,
    StatusClosed
};

typedef struct {
    WirekiteDevice* device;
    void* buffer;
} Transfer;


@interface WirekiteDevice ()
{
    io_object_t notification;
    IOUSBDeviceInterface** device;
    IOUSBInterfaceInterface** interface;
    uint8_t rxBuffer[2][RX_BUFFER_SIZE];
    int pendingBuffer;
    wk_msg_header* partialMessage;
    UInt32 partialMessageSize;
    UInt32 partialSize;
    
    DeviceStatus deviceStatus;

    PendingRequestList pendingRequests;
    PortList portList;
    Throttler throttler;
    NSThread* workerThread;
    
    NSMutableDictionary<NSNumber*, DigitalInputPinCallback>* digitalInputPinCallbacks;
    NSMutableDictionary<NSNumber*, dispatch_queue_t>* digitalInputDispatchQueues;
    NSMutableDictionary<NSNumber*, AnalogInputPinCallback>* analogInputPinCallbacks;
    NSMutableDictionary<NSNumber*, dispatch_queue_t>* analogInputDispatchQueues;
}

- (void) writeMessage:(wk_msg_header*)msg;

@end



@implementation WirekiteDevice

- (instancetype) init
{
    self = [super init];
    
    if (self != nil) {
        _delegate = nil;
        _wirekiteService = nil;
        notification = NULL;
        device = NULL;
        interface = NULL;
        deviceStatus = StatusInitializing;
    }
    
    return self;
}


- (void) dealloc
{
    _delegate = nil;

    [self close];

    _wirekiteService = nil;
}


- (void) close
{
    [self stopWorkerThread];
    
    if (interface) {
        (*interface)->USBInterfaceClose(interface);
        (*interface)->Release(interface);
        interface = NULL;
    }
    if (device) {
        (*device)->USBDeviceClose(device);
        (*device)->Release(device);
        device = NULL;
    }
    
    IOObjectRelease(notification);
    notification = NULL;
    
    portList.clear();
    throttler.clear();
    pendingRequests.clear();
    deviceStatus = StatusClosed;
}


-(bool)isClosed {
    return interface == NULL;
}


#pragma mark - Device initialization


- (BOOL) registerNotificationOnPart: (IONotificationPortRef)notifyPort device: (io_service_t) usbDevice
{
    // Register for an interest notification of this device being removed.
    kern_return_t kr = IOServiceAddInterestNotification(notifyPort,         // notifyPort
                                          usbDevice,                        // service
                                          kIOGeneralInterest,               // interestType
                                          DeviceNotification,               // callback
                                          (__bridge void*) self,            // refCon
                                          &notification                     // notification
                                          );

    if (kr != KERN_SUCCESS)
        NSLog(@"Wirekite: IOServiceAddInterestNotification failed with code 0x%08x", kr);
    
    return kr == KERN_SUCCESS;
}

    
- (BOOL) openDevice: (IOUSBDeviceInterface**) dev
{
    int retryCount = 20;
    
retry:
    // Open the device to change its state
    kern_return_t kr = (*dev)->USBDeviceOpen(dev);
    
    if (kr == kIOReturnExclusiveAccess && retryCount > 0) {
        // Seems to occur when the device was just plugged in
        // and is not yet read
        
        [NSThread sleepForTimeInterval: 0.1f];
        
        retryCount--;
        goto retry;
    }
    if (kr != kIOReturnSuccess) {
        NSLog(@"Wirekite: Unable to open device: %08x", kr);
        return NO;
    }
    
    device = dev;
    (*device)->AddRef(device);
    
    if (! [self configureDevice])
        return NO;
    
    if (! [self findInterface])
        return NO;
    
    if (! [self setupAsyncComm])
        return NO;
    
    pendingBuffer = 0;
    [self submitRead];
    
    [self resetConfiguration];
    
    return YES;
}


- (BOOL) configureDevice
{
    IOUSBConfigurationDescriptorPtr configDesc;
    
    // Get the configuration descriptor for index 0
    IOReturn kr = (*device)->GetConfigurationDescriptorPtr(device, 0, &configDesc);
    if (kr) {
        NSLog(@"Wirekite: Couldn’t get configuration descriptor for index 0 (err = %08x)", kr);
        return NO;
    }

    // Set configuration
    kr = (*device)->SetConfiguration(device, configDesc->bConfigurationValue);
    if (kr) {
        NSLog(@"Wirekite: Couldn’t set configuration to value %d (err = %08x)", (int)configDesc->bConfigurationValue, kr);
        return NO;
    }

    return YES;
}


- (BOOL) findInterface
{
    IOReturn                    kr;
    IOUSBFindInterfaceRequest   request;
    io_iterator_t               iterator;
    io_service_t                usbInterface;
    IOCFPlugInInterface         **plugInInterface = NULL;
    SInt32                      score;
    HRESULT                     result;

    // Placing the constant kIOUSBFindInterfaceDontCare into the following
    // fields of the IOUSBFindInterfaceRequest structure will allow you
    // to find all the interfaces
    request.bInterfaceClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceSubClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceProtocol = kIOUSBFindInterfaceDontCare;
    request.bAlternateSetting = kIOUSBFindInterfaceDontCare;
    
    //Get an iterator for the interfaces on the device
    kr = (*device)->CreateInterfaceIterator(device, &request, &iterator);
    if (kr) {
        NSLog(@"Wirekite: CreateInterfaceIterator failed with code 0x%08x", kr);
        return NO;
    }
    
    while ((usbInterface = IOIteratorNext(iterator))) {
        // There is only one interface; so this is the desired one.
        
        // Create an intermediate plug-in
        kr = IOCreatePlugInInterfaceForService(usbInterface,
                                               kIOUSBInterfaceUserClientTypeID,
                                               kIOCFPlugInInterfaceID,
                                               &plugInInterface, &score);
        
        // Release the usbInterface object after getting the plug-in
        IOObjectRelease(usbInterface);
        if (kr != kIOReturnSuccess || !plugInInterface) {
            NSLog(@"Wirekite: Unable to create a plug-in (%08x)", kr);
            return NO;
        }
        
        // Now create the device interface for the interface
        result = (*plugInInterface)->QueryInterface(plugInInterface,
                                                    CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),
                                                    (LPVOID *) &interface);
        // No longer need the intermediate plug-in
        (*plugInInterface)->Release(plugInInterface);
        
        if (result || !interface) {
            NSLog(@"Wirekite: Couldn’t create a device interface for the interface (%08x)", (int) result);
            return NO;
        }
        
        // Now open the interface. This will cause the pipes associated with
        // the endpoints in the interface descriptor to be instantiated
        kr = (*interface)->USBInterfaceOpen(interface);
        if (kr != kIOReturnSuccess) {
            NSLog(@"Wirekite: Unable to open interface (%08x)", kr);
            (*interface)->Release(interface);
            break;
        }
    }
    
    return YES;
}


- (void) resetConfiguration
{
    deviceStatus = StatusInitializing;
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.request_id = 0xffff;
    request.action = WK_CFG_ACTION_RESET;
    
    wk_config_response* response = [self executeConfigRequest: &request];
    free(response);
    
    portList.clear();
    pendingRequests.clear();
    throttler.clear();
    [digitalInputPinCallbacks removeAllObjects];
    [digitalInputDispatchQueues removeAllObjects];
    [analogInputPinCallbacks removeAllObjects];
    [analogInputDispatchQueues removeAllObjects];
    deviceStatus = StatusReady;
}


- (void) configureFlowControlMemSize: (int)memSize maxOutstandingRequest: (int)maxRequests
{
    throttler.configure(memSize, maxRequests);
}


#pragma mark - Basic communication


- (BOOL) setupAsyncComm
{
    CFRunLoopSourceRef runLoopSource = NULL;
    IOReturn kr = (*interface)->CreateInterfaceAsyncEventSource(interface, &runLoopSource);
    if (kr != kIOReturnSuccess) {
        NSLog(@"Wirekite: Unable to create asynchronous event source (%08x)", kr);
        return NO;
    }
    
    workerThread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMainRoutine:) object:[NSValue valueWithPointer: runLoopSource]];
    [workerThread start];
    
    return YES;
}


- (void) submitRead
{
    IOReturn result = (*interface)->ReadPipeAsync(interface, EndpointReceive, rxBuffer[pendingBuffer],
                                         RX_BUFFER_SIZE, ReadCompletion, (__bridge void*)self);
    if (result != kIOReturnSuccess)
        NSLog(@"Wirekite: Unable to perform asynchronous bulk read (%08x)", result);
}


- (void) writeMessage:(wk_msg_header*)msg
{
    //NSLog(@"%s", MessageDump::dump(msg).c_str());
    [self writeBytes:(const uint8_t*)msg size:msg->message_size];
}


- (void) writeBytes: (const uint8_t*)bytes size: (uint16_t) size
{
    if (self->interface == NULL)
        return; // has probably been disconnected
    
    // data must be copied
    Transfer* transfer = (Transfer*)malloc(sizeof(Transfer));
    memset(transfer, 0, sizeof(Transfer));
    transfer->device = self;
    transfer->buffer = malloc(size);
    memcpy(transfer->buffer, bytes, size);
    
    IOReturn kr = (*interface)->WritePipeAsync(interface,
                                               EndpointTransmit,
                                               (void*)transfer->buffer,
                                               size,
                                               WriteCompletion,
                                               transfer);
    if (kr)
        NSLog(@"Wirekite: Error on submitting write (0x%08x)", kr);
}


-(wk_config_response*)executeConfigRequest:(wk_config_request*)request
{
    uint16_t requestId = request->header.request_id;
    pendingRequests.announceRequest(requestId);
    [self writeMessage:&request->header];
    return (wk_config_response*)pendingRequests.waitForResponse(requestId);
}


-(wk_port_event*)executePortRequest:(wk_port_request*)request
{
    uint16_t requestId = request->header.request_id;
    pendingRequests.announceRequest(requestId);
    [self writeMessage:&request->header];
    return (wk_port_event*)pendingRequests.waitForResponse(requestId);
}


- (void) onDeviceNotificationForService: (io_service_t)service
                            messageType: (natural_t)messageType
                        messageArgument: (void*)messageArgument
{
    //NSLog(@"Notification: 0x%08x", messageType);
    if (messageType == kIOMessageServiceIsTerminated) {
        [self close];
        if (_delegate)
            [_delegate disconnectedDevice: self];
        if (_wirekiteService.delegate)
            [_wirekiteService.delegate disconnectedDevice: self];
    }
}


- (void) onWriteCompletedWithResult: (IOReturn)result argument: (void*) arg0
{
    if (result)
        NSLog(@"Wirekite: Write error (0x%08x)", result);
}


- (void) onReadCompletedWithResult: (IOReturn)result argument: (void*) arg0
{
    if (result) {
        NSLog(@"Wirekite: Read error (0x%08x)", result);
        return;
    }
    
    uint8_t* data = rxBuffer[pendingBuffer];
    pendingBuffer ^= 1;
    [self submitRead];
    
    UInt32 receivedBytes = (UInt32)(unsigned long) arg0;
    
    if (partialSize > 0) {
        // there is a partial message from the last USB packet
        
        if (partialSize == 1) {
            // super special case: only half of the first word
            // was transmitted
            partialMessageSize += ((UInt32)data[0]) << 8;
            partialMessage = (wk_msg_header*)malloc(partialMessageSize);
            partialMessage->message_size = partialMessageSize;
        }
        
        uint16_t len = receivedBytes;
        if (partialSize + len > partialMessageSize)
            len = partialMessageSize - partialSize;
        
        // append to partial message (buffer is big enough)
        memcpy(((uint8_t*)partialMessage) + partialSize, data, len);
        data += len;
        receivedBytes -= len;
        partialSize += len;
        
        // if message is complete handle it
        if (partialSize == partialMessageSize) {
            [self handleMessage:partialMessage];
            partialSize = 0;
            partialMessageSize = 0;
            partialMessage = NULL;
        }
    }
    
    // Handle entire messages
    while (receivedBytes >= 2) {
        wk_msg_header* header = (wk_msg_header*)data;
        uint16_t msgSize = header->message_size;
        if (receivedBytes < msgSize)
            break; // partial message
        
        if (msgSize < 8) {
            NSLog(@"Wirkeite: Invalid message of size %d received", msgSize);
            return;
        }
        
        // create copy
        wk_msg_header* copy = (wk_msg_header*) malloc(msgSize);
        memcpy(copy, header, msgSize);

        [self handleMessage:copy];
        
        data += msgSize;
        receivedBytes -= msgSize;
    }
    
    // Handle remainder
    if (receivedBytes > 0) {
        // a partial message remains
        
        if (receivedBytes == 1) {
            // super special case: only 1 byte was transmitted;
            // we don't know the size of the message
            partialSize = 1;
            partialMessageSize = data[0];
            
        } else {
            // allocate buffer
            wk_msg_header* header = (wk_msg_header*)data;
            partialMessageSize = header->message_size;
            partialMessage = (wk_msg_header*)malloc(partialMessageSize);
            partialSize = receivedBytes;
            memcpy(partialMessage, data, receivedBytes);
        }
    }
}


- (void)handleMessage: (wk_msg_header*) msg
{
    //NSLog(@"%s", MessageDump::dump(msg).c_str());

    if (msg->message_type == WK_MSG_TYPE_CONFIG_RESPONSE) {
        wk_config_response* config_response = (wk_config_response*)msg;
        if (deviceStatus == StatusReady || config_response->header.request_id == 0xffff)
            [self handleConfigResponse: config_response];
        else
            free(msg);
    } else if (msg->message_type == WK_MSG_TYPE_PORT_EVENT) {
        if (deviceStatus == StatusReady)
            [self handlePortEvent: (wk_port_event*)msg];
        else
            free(msg);
    } else {
        NSLog(@"Wirekite: Message of unknown type %d received", msg->message_type);
        free(msg);
    }
}


#pragma mark - Board information

- (long) boardInfo:(BoardInfo)boardInfo
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.request_id = portList.nextRequestId();
    request.action = WK_CFG_ACTION_QUERY;
    request.port_type = boardInfo;
    
    wk_config_response* response = [self executeConfigRequest: &request];
    
    long result;
    if (response->result == WK_RESULT_OK) {
        result = response->value1;
    } else {
        result = 0;
        NSLog(@"Wirekite: Querying board information failed");
    }
    
    free(response);
    return result;
}


#pragma mark - Digital input / output


- (PortID) configureDigitalOutputPin: (long)pin attributes: (DigitalOutputPinAttributes)attributes
{
    Port* port = [self configureDigitalPin:pin type:PortTypeDigitalOutput attributes:(1 | (uint16_t) attributes) initialValue:0];
    return port != nil ? port->portId() : InvalidPortID;
}


- (PortID) configureDigitalOutputPin: (long)pin attributes: (DigitalOutputPinAttributes)attributes initialValue:(BOOL)initialValue
{
    Port* port = [self configureDigitalPin:pin type:PortTypeDigitalOutput attributes:(1 | (uint16_t) attributes) initialValue:initialValue];
    return port != nil ? port->portId() : InvalidPortID;
}


- (PortID) configureDigitalInputPin: (long)pin attributes: (DigitalInputPinAttributes)attributes communication:(InputCommunication)communication
{
    if (communication != InputCommunicationOnDemand && communication != InputCommunicationPrecached) {
        NSLog(@"Wirekite: Digital input pin witout notification must use communication \"OnDemand\" or \"Precached\"");
        return InvalidPortID;
    }
    if ((attributes & (DigitalInputPinAttributesTriggerRaising | DigitalInputPinAttributesTriggerFalling)) != 0) {
        NSLog(@"Wirekite: Digital input pin without notification must not use attributes DigiInPinTriggerRaising and/or DigiInPinTriggerFalling");
        return InvalidPortID;
    }
    
    PortType type;
    if (communication == InputCommunicationOnDemand) {
        type = PortTypeDigitalInputOnDemand;
    } else {
        type = PortTypeDigitalInputPrecached;
        attributes |= DigitalInputPinAttributesTriggerRaising | DigitalInputPinAttributesTriggerFalling;
    }
    Port* port = [self configureDigitalPin:pin type:type attributes:(uint16_t)attributes initialValue:0];
    return port != nil ? port->portId() : InvalidPortID;
}


- (PortID) configureDigitalInputPin: (long)pin attributes: (DigitalInputPinAttributes)attributes notification: (DigitalInputPinCallback)notifyBlock
{
    return [self configureDigitalInputPin:pin attributes:attributes dispatchQueue:dispatch_get_main_queue() notification:notifyBlock];
}


- (PortID) configureDigitalInputPin: (long)pin attributes: (DigitalInputPinAttributes)attributes dispatchQueue: (dispatch_queue_t) dispatchQueue notification: (DigitalInputPinCallback)notifyBlock
{
    if ((attributes & (DigitalInputPinAttributesTriggerRaising | DigitalInputPinAttributesTriggerFalling)) == 0) {
        NSLog(@"Wirekite: Digital input pin with notification requires attribute DigiInPinTriggerRaising and/or DigiInPinTriggerFalling");
        return InvalidPortID;
    }
    
    Port* port = [self configureDigitalPin:pin type:PortTypeDigitalInputTriggering attributes:(uint16_t)attributes initialValue:0];
    if (port == nil)
        return InvalidPortID;
    
    NSNumber* key = [NSNumber numberWithUnsignedShort:port->portId()];
    if (digitalInputPinCallbacks == nil) {
        digitalInputPinCallbacks = [NSMutableDictionary<NSNumber*, DigitalInputPinCallback> new];
        digitalInputDispatchQueues = [NSMutableDictionary<NSNumber*, dispatch_queue_t> new];
    }
    digitalInputPinCallbacks[key] = notifyBlock;
    digitalInputDispatchQueues[key] = dispatchQueue;
    
    return port->portId();
}


- (Port*) configureDigitalPin: (long)pin type: (PortType)type attributes: (uint16_t)attributes initialValue: (BOOL)initialValue
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.request_id = portList.nextRequestId();
    request.action = WK_CFG_ACTION_CONFIG_PORT;
    request.port_type = WK_CFG_PORT_TYPE_DIGI_PIN;
    request.port_attributes1 = attributes;
    request.pin_config = pin;
    request.value1 = initialValue ? 1 : 0;
    
    wk_config_response* response = [self executeConfigRequest: &request];

    Port* port = NULL;
    if (response->result == WK_RESULT_OK) {
        port = new Port(response->header.port_id, type, 10);
        portList.addPort(port);
        if ((attributes & 1) == 0)
            port->setLastSample(response->optional1);
    } else {
        NSLog(@"Wirekite: Digital pin configuration failed");
    }
    
    free(response);
    return port;
}


- (void) releaseDigitalPinOnPort: (PortID)portId
{
    if ([self isClosed])
        return; // silently ignore
    
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.port_id = portId;
    request.header.request_id = portList.nextRequestId();
    request.action = WK_CFG_ACTION_RELEASE;
    
    wk_config_response* response = [self executeConfigRequest: &request];
    
    NSNumber* key = [NSNumber numberWithUnsignedShort:portId];
    [digitalInputPinCallbacks removeObjectForKey:key];
    [digitalInputDispatchQueues removeObjectForKey:key];
    
    Port* port = portList.getPort(portId);
    portList.removePort(portId);
    free(response);
    delete port;
}


- (void) writeDigitalPinOnPort: (PortID)port value:(BOOL)value
{
    [self writeDigitalPinOnPort:port value:value synchronizedWithSPIPort:0];
}


- (void) writeDigitalPinOnPort: (PortID)port value:(BOOL)value synchronizedWithSPIPort:(PortID)spiPort
{
    if ([self isClosed]) {
        NSLog(@"Wirekite: Device has been closed or disconnected. Digital port operation is ignored.");
        return;
    }

    size_t msg_len = WK_PORT_REQUEST_ALLOC_SIZE(0);
    uint16_t requestId = 0;
    if (spiPort != 0) {
        requestId = portList.nextRequestId();
        throttler.waitUntilAvailable(requestId, msg_len);
    }
    
    wk_port_request request;
    memset(&request, 0, msg_len);
    request.header.message_size = msg_len;
    request.header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request.header.port_id = port;
    request.header.request_id = requestId;
    request.action = WK_PORT_ACTION_SET_VALUE;
    request.value1 = value ? 1 : 0;
    request.action_attribute2 = (uint16_t)spiPort;
    
    [self writeMessage:&request.header];
}


- (BOOL) readDigitalPinOnPort: (PortID)portId
{
    Port* port = portList.getPort(portId);
    if (port == NULL)
        return NO;

    PortType portType = port->type();
    if (portType == PortTypeDigitalInputTriggering || portType == PortTypeDigitalInputPrecached)
        return port->lastSample() != 0;
    
    if (portType != PortTypeDigitalInputOnDemand)
        return NO;
    
    wk_port_request request;
    memset(&request, 0, WK_PORT_REQUEST_ALLOC_SIZE(0));
    request.header.message_size = WK_PORT_REQUEST_ALLOC_SIZE(0);
    request.header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request.header.port_id = portId;
    request.action = WK_PORT_ACTION_GET_VALUE;

    [self writeMessage:&request.header];

    wk_port_event* event = port->waitForEvent();
    
    BOOL result = event->value1 != 0;
    free(event);
    return result;
}


#pragma mark - Analog input


- (PortID) configureAnalogInputPin:(AnalogPin)pin
{
    Port* port = [self configureAnalogInputPin:pin interval:0];
    return port != nil ? port->portId() : InvalidPortID;
}


- (PortID) configureAnalogInputPin: (AnalogPin)pin interval:(long)interval notification: (AnalogInputPinCallback)notifyBlock
{
    return [self configureAnalogInputPin:pin interval:interval dispatchQueue:dispatch_get_main_queue() notification:notifyBlock];
}


- (PortID) configureAnalogInputPin: (AnalogPin)pin interval:(long)interval dispatchQueue: (dispatch_queue_t)dispatchQueue notification: (AnalogInputPinCallback)notifyBlock
{
    if (interval == 0) {
        NSLog(@"Wirekite: Analog inputwith automatic sampling requires interval > 0");
        return InvalidPortID;
    }
    
    Port* port = [self configureAnalogInputPin:pin interval:interval];
    if (port == nil)
        return InvalidPortID;
    
    NSNumber* key = [NSNumber numberWithUnsignedShort:port->portId()];
    if (analogInputPinCallbacks == nil) {
        analogInputPinCallbacks = [NSMutableDictionary<NSNumber*, AnalogInputPinCallback> new];
        analogInputDispatchQueues = [NSMutableDictionary<NSNumber*, dispatch_queue_t> new];
    }
    analogInputPinCallbacks[key] = notifyBlock;
    analogInputDispatchQueues[key] = dispatchQueue;
    
    return port->portId();
}



- (Port*) configureAnalogInputPin:(AnalogPin)pin interval:(long)interval
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_CONFIG_PORT;
    request.port_type = WK_CFG_PORT_TYPE_ANALOG_IN;
    request.header.request_id = portList.nextRequestId();
    request.pin_config = pin;
    request.value1 = (int32_t)interval;
    
    wk_config_response* response = [self executeConfigRequest: &request];
    
    Port* port = NULL;
    if (response->result == WK_RESULT_OK) {
        port = new Port(response->header.port_id, interval == 0 ? PortTypeAnalogInputOnDemand : PortTypeAnalogInputSampling, 10);
        portList.addPort(port);
    } else {
        NSLog(@"Wirekite: Analog input pin configuration failed");
    }
    
    free(response);
    return port;
}


- (void) releaseAnalogPinOnPort: (PortID)portId
{
    if ([self isClosed])
        return; // silently ignore
    
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.port_id = portId;
    request.header.request_id = portList.nextRequestId();
    request.action = WK_CFG_ACTION_RELEASE;

    wk_config_response* response = [self executeConfigRequest: &request];

    NSNumber* key = [NSNumber numberWithUnsignedShort:portId];
    [analogInputPinCallbacks removeObjectForKey:key];
    [analogInputDispatchQueues removeObjectForKey:key];

    Port* port = portList.getPort(portId);
    portList.removePort(portId);
    free(response);
    delete port;
}


- (double) readAnalogPinOnPort: (PortID)portId
{
    Port* port = portList.getPort(portId);
    if (port == NULL)
        return 0;
    
    wk_port_request request;
    memset(&request, 0, WK_PORT_REQUEST_ALLOC_SIZE(0));
    request.header.message_size = WK_PORT_REQUEST_ALLOC_SIZE(0);
    request.header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request.header.port_id = portId;
    request.action = WK_PORT_ACTION_GET_VALUE;
    
    [self writeMessage:&request.header];
    
    wk_port_event* event = port->waitForEvent();
    
    int32_t r = (int32_t)event->value1;
    free(event);

    return r < 0 ? r / 2147483648.0 : r / 2147483647.0;
}


#pragma mark - PWM output


- (PortID) configurePWMOutputPin:(long)pin
{
    return [self configurePWMOutputPin:pin initialDutyCycle:0];
}


- (PortID) configurePWMOutputPin:(long)pin initialDutyCycle:(double)initialDutyCycle
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.request_id = portList.nextRequestId();
    request.action = WK_CFG_ACTION_CONFIG_PORT;
    request.port_type = WK_CFG_PORT_TYPE_PWM;
    request.pin_config = pin;
    request.value1 = (uint32_t)(initialDutyCycle * 2147483647 + 0.5);
    
    wk_config_response* response = [self executeConfigRequest: &request];

    Port* port = NULL;
    PortID portId = 0;
    if (response->result == WK_RESULT_OK) {
        portId = response->header.port_id;
        port = new Port(portId, PortTypePWMOutput, 10);
        portList.addPort(port);
    } else {
        NSLog(@"Wirekite: PWM pin configuration failed");
    }
    
    free(response);
    return portId;
}


- (void) releasePWMPinOnPort:(PortID)portId
{
    if ([self isClosed])
        return; // silently ignore
    
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.port_id = portId;
    request.header.request_id = portList.nextRequestId();
    request.action = WK_CFG_ACTION_RELEASE;

    wk_config_response* response = [self executeConfigRequest: &request];

    Port* port = portList.getPort(portId);
    portList.removePort(portId);
    free(response);
    delete port;
}


- (void) writePWMPinOnPort:(PortID)portId dutyCycle:(double)dutyCycle
{
    if ([self isClosed]) {
        NSLog(@"Wirekite: Device has been closed or disconnected. PWM output operation is ignored.");
        return;
    }
    
    wk_port_request request;
    memset(&request, 0, WK_PORT_REQUEST_ALLOC_SIZE(0));
    request.header.message_size = WK_PORT_REQUEST_ALLOC_SIZE(0);
    request.header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request.header.port_id = portId;
    request.action = WK_PORT_ACTION_SET_VALUE;
    request.value1 = (uint32_t)(dutyCycle * 2147483647 + 0.5);
    
    [self writeMessage:&request.header];
}


- (void) configurePWMTimer: (long) timer frequency: (long) frequency attributes: (PWMTimerAttributes) attributes
{
    if ([self isClosed]) {
        NSLog(@"Wirekite: Device has been closed or disconnected. PWM output operation is ignored.");
        return;
    }
    
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.request_id = portList.nextRequestId();
    request.action = WK_CFG_ACTION_CONFIG_MODULE;
    request.port_type = WK_CFG_MODULE_PWM_TIMER;
    request.pin_config = (uint8_t)timer;
    request.port_attributes1 = attributes;
    request.value1 = (int32_t)frequency;
    
    wk_config_response* response = [self executeConfigRequest: &request];
    free(response);
}


- (void) configurePWMChannel: (long) timer channel: (long) channel attributes: (PWMChannelAttributes) attributes
{
    if ([self isClosed]) {
        NSLog(@"Wirekite: Device has been closed or disconnected. PWM output operation is ignored.");
        return;
    }
    
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.request_id = portList.nextRequestId();
    request.action = WK_CFG_ACTION_CONFIG_MODULE;
    request.port_type = WK_CFG_MODULE_PWM_CHANNEL;
    request.pin_config = (uint8_t)timer;
    request.port_attributes1 = attributes;
    request.value1 = (uint8_t)channel;
    
    wk_config_response* response = [self executeConfigRequest: &request];
    free(response);
}


#pragma mark - I2C communication

- (PortID) configureI2CMaster: (I2CPins)pins frequency: (long)frequency
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.request_id = portList.nextRequestId();
    request.action = WK_CFG_ACTION_CONFIG_PORT;
    request.port_type = WK_CFG_PORT_TYPE_I2C;
    request.pin_config = pins;
    request.value1 = (int32_t)frequency;
    
    wk_config_response* response = [self executeConfigRequest: &request];

    Port* port = NULL;
    PortID portId = 0;
    if (response->result == WK_RESULT_OK) {
        portId = response->header.port_id;
        port = new Port(portId, PortTypeI2C, 10);
        portList.addPort(port);
    } else {
        NSLog(@"Wirekite: I2C configuration failed");
    }
    
    free(response);
    return portId;
}


- (void) releaseI2CPort: (PortID)port
{
    if ([self isClosed])
        return; // silently ignore
    
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.port_id = port;
    request.header.request_id = portList.nextRequestId();
    request.action = WK_CFG_ACTION_RELEASE;
    
    wk_config_response* response = [self executeConfigRequest: &request];
    
    Port* p = portList.getPort(port);
    portList.removePort(port);
    free(response);
    delete p;
}


- (void) resetBusOnI2CPort: (PortID)port
{
    if ([self isClosed])
        return; // silently ignore
    
    Port* p = portList.getPort(port);
    if (p == nil)
        return;
    
    uint16_t requestId = portList.nextRequestId();
    uint16_t msgLen = WK_PORT_REQUEST_ALLOC_SIZE(0);
    wk_port_request request;
    memset(&request, 0, msgLen);
    request.header.message_size = msgLen;
    request.header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request.header.port_id = port;
    request.header.request_id = requestId;
    request.action = WK_PORT_ACTION_RESET;
    
    throttler.waitUntilAvailable(requestId, msgLen);
    
    wk_port_event* response = [self executePortRequest:&request];
    
    I2CResult result = (I2CResult)response->event_attribute1;
    p->setLastSample(result);
    
    free(response);
}


- (long) sendOnI2CPort: (PortID)port data: (NSData*)data toSlave: (long)slave
{
    if ([self isClosed]) {
        NSLog(@"Wirekite: Device has been closed or disconnected. I2C operation is ignored.");
        return 0;
    }
    
    Port* p = portList.getPort(port);
    if (p == nil)
        return 0;
    
    wk_port_request* request = [self createI2CTxRequestForPort:port data:data toSlave:slave];
    wk_port_event* response = [self executePortRequest:request];
    free(request);
    
    uint16_t transmitted = response->event_attribute2;
    p->setLastSample((I2CResult)response->event_attribute1);
    free(response);
    return transmitted;
}


- (void) submitOnI2CPort: (PortID)port data: (NSData*)data toSlave: (long)slave
{
    if ([self isClosed]) {
        NSLog(@"Wirekite: Device has been closed or disconnected. I2C operation is ignored.");
        return;
    }
    
    Port* p = portList.getPort(port);
    if (p == nil)
        return;
    
    wk_port_request* request = [self createI2CTxRequestForPort:port data:data toSlave:slave];
    [self writeMessage:&request->header];
    free(request);
}


-(wk_port_request*)createI2CTxRequestForPort: (PortID)port data: (NSData*)data toSlave: (long)slave
{
    NSUInteger len = data.length;
    size_t msg_len = WK_PORT_REQUEST_ALLOC_SIZE(len);
    uint16_t requestId = portList.nextRequestId();

    throttler.waitUntilAvailable(requestId, msg_len);

    wk_port_request* request = (wk_port_request*)malloc(msg_len);
    memset(request, 0, msg_len);
    request->header.message_size = msg_len;
    request->header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request->header.port_id = port;
    request->header.request_id = requestId;
    request->action = WK_PORT_ACTION_TX_DATA;
    request->action_attribute2 = (uint16_t)slave;
    memcpy(request->data, data.bytes, len);

    return request;
}


- (NSData*) requestDataOnI2CPort: (PortID)port fromSlave: (long)slave length: (long)length
{
    Port* p = portList.getPort(port);
    if (p == nil)
        return nil;
    
    uint16_t requestId = portList.nextRequestId();
    wk_port_request request;
    memset(&request, 0, WK_PORT_REQUEST_ALLOC_SIZE(0));
    request.header.message_size = WK_PORT_REQUEST_ALLOC_SIZE(0);
    request.header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request.header.port_id = port;
    request.header.request_id = requestId;
    request.action = WK_PORT_ACTION_RX_DATA;
    request.action_attribute2 = (uint16_t)slave;
    request.value1 = (uint16_t)length;
    
    throttler.waitUntilAvailable(requestId, WK_PORT_EVENT_ALLOC_SIZE(length));
    
    wk_port_event* response = [self executePortRequest:&request];
    
    I2CResult result = (I2CResult)response->event_attribute1;
    p->setLastSample(result);
    
    NSData* data = nil;
    size_t dataLength = WK_PORT_EVENT_DATA_LEN(response);
    if (dataLength > 0)
        data = [NSData dataWithBytes:response->data length:dataLength];
    
    free(response);
    return data;
}


- (NSData*) sendAndRequestOnI2CPort: (PortID)port data: (NSData*)data toSlave: (long)slave receiveLength: (long)receiveLength
{
    if ([self isClosed]) {
        NSLog(@"Wirekite: Device has been closed or disconnected. I2C operation is ignored.");
        return 0;
    }
    
    Port* p = portList.getPort(port);
    if (p == nil)
        return 0;
    
    NSUInteger len = data.length;
    size_t msg_len = WK_PORT_REQUEST_ALLOC_SIZE(len);
    uint16 requestId = portList.nextRequestId();
    wk_port_request* request = (wk_port_request*)malloc(msg_len);
    memset(request, 0, msg_len);
    request->header.message_size = msg_len;
    request->header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request->header.port_id = port;
    request->header.request_id = requestId;
    request->action = WK_PORT_ACTION_TX_N_RX_DATA;
    request->action_attribute2 = (uint16_t)slave;
    request->value1 = (uint16_t)receiveLength;
    memcpy(request->data, data.bytes, len);
    
    size_t mem_size = WK_PORT_EVENT_ALLOC_SIZE(receiveLength);
    if (msg_len > mem_size)
        mem_size = msg_len;
    throttler.waitUntilAvailable(requestId, mem_size);
    
    wk_port_event* response = [self executePortRequest:request];
    free(request);
    
    I2CResult result = (I2CResult)response->event_attribute1;
    p->setLastSample(result);
    
    NSData* rxData = nil;
    size_t dataLength = WK_PORT_EVENT_DATA_LEN(response);
    if (dataLength > 0)
        rxData = [NSData dataWithBytes:response->data length:dataLength];
    
    free(response);
    return rxData;
}


- (I2CResult) lastResultOnI2CPort: (PortID)port
{
    Port* p = portList.getPort(port);
    if (p == nil)
        return I2CResultInvalidParameter;
    
    return (I2CResult)p->lastSample();
}


#pragma mark - SPI communication

-(PortID)configureSPIMasterForSCKPin:(long)sckPin mosiPin:(long)mosiPin misoPin:(long)misoPin frequency:(long)frequency attributes:(SPIAttributes)attributes
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.request_id = portList.nextRequestId();
    request.action = WK_CFG_ACTION_CONFIG_PORT;
    request.port_type = WK_CFG_PORT_TYPE_SPI;
    request.pin_config = (sckPin & 0xff) | ((mosiPin & 0xff) << 8);
    request.port_attributes2 = (misoPin & 0xff);
    request.port_attributes1 = attributes;
    request.value1 = (int32_t)frequency;
    
    wk_config_response* response = [self executeConfigRequest:&request];
    
    Port* port = NULL;
    PortID portId = 0;
    if (response->result == WK_RESULT_OK) {
        portId = response->header.port_id;
        port = new Port(portId, PortTypeSPI, 10);
        portList.addPort(port);
    } else {
        NSLog(@"Wirekite: SPI configuration failed");
    }
    
    free(response);
    return portId;
}


-(void)releaseSPIPort: (PortID)port
{
    if ([self isClosed])
        return; // silently ignore
    
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.header.port_id = port;
    request.header.request_id = portList.nextRequestId();
    request.action = WK_CFG_ACTION_RELEASE;

    wk_config_response* response = [self executeConfigRequest:&request];
    
    Port* p = portList.getPort(port);
    portList.removePort(port);
    free(response);
    delete p;
}


-(long)transmitOnSPIPort:(PortID)port data:(NSData*)data chipSelect:(PortID)chipSelect
{
    if ([self isClosed]) {
        NSLog(@"Wirekite: Device has been closed or disconnected. SPI operation is ignored.");
        return 0;
    }
    
    Port* p = portList.getPort(port);
    if (p == nil)
        return 0;
    
    wk_port_request* request = [self createSPIRequestForPort:port action:WK_PORT_ACTION_TX_DATA data:data chipSelect:chipSelect];
    wk_port_event* response = [self executePortRequest:request];
    free(request);
    
    uint16_t transmitted = response->event_attribute2;
    p->setLastSample((SPIResult)response->event_attribute1);
    free(response);
    return transmitted;
}


-(void)submitOnSPIPort:(PortID)port data:(NSData*)data chipSelect:(PortID)chipSelect
{
    if ([self isClosed]) {
        NSLog(@"Wirekite: Device has been closed or disconnected. SPI operation is ignored.");
        return;
    }
    
    Port* p = portList.getPort(port);
    if (p == nil)
        return;
    
    wk_port_request* request = [self createSPIRequestForPort:port action:WK_PORT_ACTION_TX_DATA data:data chipSelect:chipSelect];
    [self writeMessage:&request->header];
    free(request);
}


-(NSData* _Nullable)requestOnSPIPort:(PortID)port chipSelect:(PortID)chipSelect length:(long)length
{
    return [self requestOnSPIPort:port chipSelect:chipSelect length:length mosiValue:0xff];
}


-(NSData* _Nullable)requestOnSPIPort:(PortID)port chipSelect:(PortID)chipSelect length:(long)length mosiValue:(long)mosiValue
{
    if ([self isClosed]) {
        NSLog(@"Wirekite: Device has been closed or disconnected. SPI operation is ignored.");
        return nil;
    }
    
    Port* p = portList.getPort(port);
    if (p == nil)
        return nil;
    
    uint16_t requestId = portList.nextRequestId();
    size_t msg_len = WK_PORT_REQUEST_ALLOC_SIZE(0);
    
    throttler.waitUntilAvailable(requestId, msg_len);
    
    wk_port_request* request = (wk_port_request*)malloc(msg_len);
    memset(request, 0, msg_len);
    request->header.message_size = msg_len;
    request->header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request->header.port_id = port;
    request->header.request_id = requestId;
    request->action = WK_PORT_ACTION_RX_DATA;
    request->action_attribute1 = (uint8_t)mosiValue;
    request->action_attribute2 = chipSelect;
    request->value1 = (uint32_t)length;
    
    wk_port_event* response = [self executePortRequest:request];
    free(request);
    
    SPIResult result = (SPIResult)response->event_attribute1;
    p->setLastSample(result);
    
    NSData* rxData = nil;
    size_t dataLength = WK_PORT_EVENT_DATA_LEN(response);
    if (dataLength > 0)
        rxData = [NSData dataWithBytes:response->data length:dataLength];
    
    free(response);
    return rxData;
}


-(NSData* _Nullable)transmitAndRequestOnSPIPort:(PortID)port data:(NSData*)data chipSelect:(PortID)chipSelect
{
    if ([self isClosed]) {
        NSLog(@"Wirekite: Device has been closed or disconnected. SPI operation is ignored.");
        return nil;
    }
    
    Port* p = portList.getPort(port);
    if (p == nil)
        return nil;
    
    wk_port_request* request = [self createSPIRequestForPort:port action:WK_PORT_ACTION_TX_N_RX_DATA data:data chipSelect:chipSelect];
    [self writeMessage:&request->header];
    
    wk_port_event* response = [self executePortRequest:request];
    free(request);
    
    SPIResult result = (SPIResult)response->event_attribute1;
    p->setLastSample(result);
    
    NSData* rxData = nil;
    size_t dataLength = WK_PORT_EVENT_DATA_LEN(response);
    if (dataLength > 0)
        rxData = [NSData dataWithBytes:response->data length:dataLength];
    
    free(response);
    return rxData;
}


-(wk_port_request*)createSPIRequestForPort:(PortID)port action:(uint8_t)action data:(NSData*)data chipSelect:(PortID)chipSelect
{
    uint16_t requestId = portList.nextRequestId();
    NSUInteger len = data.length;
    size_t msg_len = WK_PORT_REQUEST_ALLOC_SIZE(len);
    
    throttler.waitUntilAvailable(requestId, msg_len);
    
    wk_port_request* request = (wk_port_request*)malloc(msg_len);
    memset(request, 0, msg_len);
    request->header.message_size = msg_len;
    request->header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request->header.port_id = port;
    request->header.request_id = requestId;
    request->action = action;
    request->action_attribute2 = chipSelect;
    memcpy(request->data, data.bytes, len);
    
    return request;
}


-(SPIResult) lastResultOnSPIPort: (PortID)port
{
    Port* p = portList.getPort(port);
    if (p == nil)
        return SPIResultInvalidParameter;
    
    return (SPIResult)p->lastSample();
}


#pragma mark - Message handling


- (void) handleConfigResponse: (wk_config_response*) response
{
    pendingRequests.putResponse(response->header.request_id, (wk_msg_header*)response);
}


- (void) handlePortEvent: (wk_port_event*) event
{
    if (event->event == WK_EVENT_SINGLE_SAMPLE) {
        Port* port = portList.getPort(event->header.port_id);
        if (port == NULL)
            goto error;
        
        PortType portType = port->type();
        if (portType == PortTypeDigitalInputOnDemand) {
            port->pushEvent(event);
            return;
            
        } else if (portType == PortTypeDigitalInputPrecached || portType == PortTypeDigitalInputTriggering) {
            uint8_t value = (uint8_t)event->value1;
            free(event);
            port->setLastSample(value);
            
            if (portType == PortTypeDigitalInputTriggering) {
                NSNumber* key = [NSNumber numberWithUnsignedShort:port->portId()];
                DigitalInputPinCallback callback = digitalInputPinCallbacks[key];
                dispatch_queue_t dispatchQueue = digitalInputDispatchQueues[key];
                if (callback != nil && dispatchQueue != nil) {
                    dispatch_async(dispatchQueue, ^{
                        callback(port->portId(), value != 0);
                    });
                }
            }
            return;
            
        } else if (portType == PortTypeAnalogInputOnDemand) {
            port->pushEvent(event);
            return;
            
        } else if (portType == PortTypeAnalogInputSampling) {
            int32_t value = (int32_t)event->value1;
            free(event);
            port->setLastSample(value);
            
            NSNumber* key = [NSNumber numberWithUnsignedShort:port->portId()];
            AnalogInputPinCallback callback = analogInputPinCallbacks[key];
            dispatch_queue_t dispatchQueue = analogInputDispatchQueues[key];
            if (callback != nil && dispatchQueue != nil) {
                dispatch_async(dispatchQueue, ^{
                    double v = value < 0 ? value / 2147483648.0 : value / 2147483647.0;
                    callback(port->portId(), v);
                });
            }
            return;
        }
        
    } else if (event->event == WK_EVENT_TX_COMPLETE || event->event == WK_EVENT_DATA_RECV) {
        Port* port = portList.getPort(event->header.port_id);
        if (port == NULL)
            goto error;
        
        PortType portType = port->type();
        if (portType == PortTypeI2C || portType == PortTypeSPI) {
            throttler.requestCompleted(event->header.request_id);
            pendingRequests.putResponse(event->header.request_id, (wk_msg_header*)event);
            return;
        }    
    } else if (event->event == WK_EVENT_SET_DONE) {
        throttler.requestCompleted(event->header.request_id);
        free(event);
        return;
    }

error:
    NSLog(@"Wirekite: Unknown event (%d) for port (%d) received", event->event, event->header.port_id);
    free(event);
}


#pragma mark - Worker thread

- (void) threadMainRoutine: (id) data
{
    @autoreleasepool {

        NSValue* value = data;
        CFRunLoopSourceRef runLoopSource = (CFRunLoopSourceRef) [value pointerValue];
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);

        // Keep processing events until the runloop is stopped.
        CFRunLoopRun();
        
        CFRelease(runLoopSource);
    }
}


- (void) stopWorkerThread
{
    [self performSelector:@selector(stopThisRunLoop) onThread:workerThread withObject:nil waitUntilDone:NO];
    workerThread = nil;
}


- (void)stopThisRunLoop
{
    CFRunLoopStop(CFRunLoopGetCurrent());
}


@end


#pragma mark - Callback helpers


void DeviceNotification(void *refCon, io_service_t service, natural_t messageType, void *messageArgument)
{
    WirekiteDevice* device = (__bridge WirekiteDevice*) refCon;
    [device onDeviceNotificationForService:service messageType:messageType messageArgument:messageArgument];
}


void WriteCompletion(void *refCon, IOReturn result, void *arg0)
{
    Transfer* transfer = (Transfer*)refCon;
    [transfer->device onWriteCompletedWithResult: result argument: arg0];
    free(transfer->buffer);
    transfer->device = nil;
    free(transfer);
}


void ReadCompletion(void *refCon, IOReturn result, void *arg0)
{
    WirekiteDevice* device = (__bridge WirekiteDevice*) refCon;
    [device onReadCompletedWithResult: result argument: arg0];
}
