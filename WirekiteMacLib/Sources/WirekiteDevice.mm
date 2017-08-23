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

uint16_t InvalidPortID = 0xffff;


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
    uint16_t rxBuffer[2][RX_BUFFER_SIZE];
    int pendingBuffer;
    
    DeviceStatus deviceStatus;

    PendingRequestList pendingRequests;
    PortList portList;
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
    deviceStatus = StatusClosed;
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
    request.action = WK_CFG_ACTION_RESET;
    request.request_id = 0xffff;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = (wk_config_response*)pendingRequests.waitForResponse(request.request_id);
    free(response);
    
    portList.clear();
    pendingRequests.clear();
    [digitalInputPinCallbacks removeAllObjects];
    [digitalInputDispatchQueues removeAllObjects];
    [analogInputPinCallbacks removeAllObjects];
    [analogInputDispatchQueues removeAllObjects];
    deviceStatus = StatusReady;
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
    
    int bufIndex = pendingBuffer;
    pendingBuffer ^= 1;
    [self submitRead];
    
    UInt32 receivedBytes = (UInt32)(unsigned long) arg0;
    UInt32 processedBytes = 0;
    while (processedBytes < receivedBytes) {
        wk_msg_header* header = (wk_msg_header*)(rxBuffer[bufIndex] + processedBytes);
        uint16_t msgSize = header->message_size;
        wk_msg_header* copy = (wk_msg_header*) malloc(msgSize);
        memcpy(copy, header, msgSize);
        
        //NSLog(@"%s", MessageDump::dump(header).c_str());
        
        if (header->message_type == WK_MSG_TYPE_CONFIG_RESPONSE) {
            wk_config_response* config_response = (wk_config_response*)copy;
            if (deviceStatus == StatusReady || config_response->request_id == 0xffff)
                [self handleConfigResponse: config_response];
            else
                free(copy);
        } else if (header->message_type == WK_MSG_TYPE_PORT_EVENT) {
            if (deviceStatus == StatusReady)
                [self handlePortEvent: (wk_port_event*)copy];
            else
                free(copy);
        } else {
            NSLog(@"Wirekite: Message of unknown type %d received", msgSize);
            free(copy);
        }
        processedBytes += msgSize;
        // TODO: partial messages
    }
}


#pragma mark - Digital input / output


- (PortID) configureDigitalOutputPin: (int)pin attributes: (DigitalOutputPinAttributes)attributes
{
    Port* port = [self configureDigitalPin:pin type:PortTypeDigitalOutput attributes:(1 | (uint16_t) attributes)];
    return port != nil ? port->portId() : InvalidPortID;
}


- (PortID) configureDigitalInputPin: (int)pin attributes: (DigitalInputPinAttributes)attributes communication:(InputCommunication)communication
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
    Port* port = [self configureDigitalPin:pin type:type attributes:(uint16_t)attributes];
    return port != nil ? port->portId() : InvalidPortID;
}


- (PortID) configureDigitalInputPin: (int)pin attributes: (DigitalInputPinAttributes)attributes notification: (DigitalInputPinCallback)notifyBlock
{
    return [self configureDigitalInputPin:pin attributes:attributes dispatchQueue:dispatch_get_main_queue() notification:notifyBlock];
}


- (PortID) configureDigitalInputPin: (int)pin attributes: (DigitalInputPinAttributes)attributes dispatchQueue: (dispatch_queue_t) dispatchQueue notification: (DigitalInputPinCallback)notifyBlock
{
    if ((attributes & (DigitalInputPinAttributesTriggerRaising | DigitalInputPinAttributesTriggerFalling)) == 0) {
        NSLog(@"Wirekite: Digital input pin with notification requires attribute DigiInPinTriggerRaising and/or DigiInPinTriggerFalling");
        return InvalidPortID;
    }
    
    Port* port = [self configureDigitalPin:pin type:PortTypeDigitalInputTriggering attributes:(uint16_t)attributes];
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


- (Port*) configureDigitalPin: (int)pin type: (PortType)type attributes: (uint16_t)attributes
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_CONFIG_PORT;
    request.port_type = WK_CFG_PORT_TYPE_DIGI_PIN;
    request.request_id = portList.nextRequestId();
    request.port_attributes = attributes;
    request.pin_config = pin;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = (wk_config_response*)pendingRequests.waitForResponse(request.request_id);

    Port* port = NULL;
    if (response->result == WK_RESULT_OK) {
        port = new Port(response->port_id, type, 10);
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
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_RELEASE;
    request.port_id = portId;
    request.request_id = portList.nextRequestId();
    
    [self writeMessage:&request.header];

    wk_config_response* response = (wk_config_response*)pendingRequests.waitForResponse(request.request_id);
    
    NSNumber* key = [NSNumber numberWithUnsignedShort:portId];
    [digitalInputPinCallbacks removeObjectForKey:key];
    [digitalInputDispatchQueues removeObjectForKey:key];
    
    Port* port = portList.getPort(portId);
    portList.removePort(portId);
    free(response);
    delete port;
}


- (void) writeDigitalPinOnPort: (PortID)portId value:(BOOL)value
{
    wk_port_request request;
    memset(&request, 0, sizeof(wk_port_request));
    request.header.message_size = sizeof(wk_port_request);
    request.header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request.port_id = portId;
    request.action = WK_PORT_ACTION_SET_VALUE;
    request.value1 = value ? 1 : 0;

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
    request.header.message_size = sizeof(wk_port_request) - 4;
    request.header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request.port_id = portId;
    request.action = WK_PORT_ACTION_GET_VALUE;
    request.action_attribute1 = 0;
    request.action_attribute2 = 0;
    request.request_id = 0;

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


- (PortID) configureAnalogInputPin: (AnalogPin)pin interval:(uint32_t)interval notification: (AnalogInputPinCallback)notifyBlock
{
    return [self configureAnalogInputPin:pin interval:interval dispatchQueue:dispatch_get_main_queue() notification:notifyBlock];
}


- (PortID) configureAnalogInputPin: (AnalogPin)pin interval:(uint32_t)interval dispatchQueue: (dispatch_queue_t)dispatchQueue notification: (AnalogInputPinCallback)notifyBlock
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



- (Port*) configureAnalogInputPin:(AnalogPin)pin interval:(uint32_t)interval
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_CONFIG_PORT;
    request.port_type = WK_CFG_PORT_TYPE_ANALOG_IN;
    request.request_id = portList.nextRequestId();
    request.pin_config = pin;
    request.value1 = interval;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = (wk_config_response*)pendingRequests.waitForResponse(request.request_id);
    
    Port* port = NULL;
    if (response->result == WK_RESULT_OK) {
        port = new Port(response->port_id, interval == 0 ? PortTypeAnalogInputOnDemand : PortTypeAnalogInputSampling, 10);
        portList.addPort(port);
    } else {
        NSLog(@"Wirekite: Analog input pin configuration failed");
    }
    
    free(response);
    return port;
}


- (void) releaseAnalogPinOnPort: (PortID)portId
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_RELEASE;
    request.port_id = portId;
    request.request_id = portList.nextRequestId();
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = (wk_config_response*)pendingRequests.waitForResponse(request.request_id);
    
    NSNumber* key = [NSNumber numberWithUnsignedShort:portId];
    [analogInputPinCallbacks removeObjectForKey:key];
    [analogInputDispatchQueues removeObjectForKey:key];

    Port* port = portList.getPort(portId);
    portList.removePort(portId);
    free(response);
    delete port;
}


- (int16_t) readAnalogPinOnPort: (PortID)portId
{
    Port* port = portList.getPort(portId);
    if (port == NULL)
        return 0;
    
    wk_port_request request;
    request.header.message_size = sizeof(wk_port_request) - 4;
    request.header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request.port_id = portId;
    request.action = WK_PORT_ACTION_GET_VALUE;
    request.action_attribute1 = 0;
    request.action_attribute2 = 0;
    request.request_id = 0;
    
    [self writeMessage:&request.header];
    
    wk_port_event* event = port->waitForEvent();
    
    int16_t result = (int16_t)event->value1;
    free(event);
    return result;
}


#pragma mark - PWM output


- (PortID) configurePWMOutputPin:(PWMPin)pin
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_CONFIG_PORT;
    request.port_type = WK_CFG_PORT_TYPE_PWM;
    request.request_id = portList.nextRequestId();
    request.pin_config = pin;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = (wk_config_response*)pendingRequests.waitForResponse(request.request_id);
    
    Port* port = NULL;
    PortID portId = 0;
    if (response->result == WK_RESULT_OK) {
        portId = response->port_id;
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
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_RELEASE;
    request.port_id = portId;
    request.request_id = portList.nextRequestId();
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = (wk_config_response*)pendingRequests.waitForResponse(request.request_id);
    
    Port* port = portList.getPort(portId);
    portList.removePort(portId);
    free(response);
    delete port;
}


- (void) writePWMPinOnPort:(PortID)portId dutyCycle:(int16_t)dutyCycle
{
    wk_port_request request;
    memset(&request, 0, sizeof(wk_port_request));
    request.header.message_size = sizeof(wk_port_request);
    request.header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request.port_id = portId;
    request.action = WK_PORT_ACTION_SET_VALUE;
    request.value1 = dutyCycle;
    
    [self writeMessage:&request.header];
}


- (void) configurePWMTimer: (uint8_t) timer frequency: (uint32_t) frequency attributes: (PWMTimerAttributes) attributes
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_CONFIG_MODULE;
    request.port_type = WK_CFG_MODULE_PWM_TIMER;
    request.request_id = portList.nextRequestId();
    request.pin_config = timer;
    request.port_attributes = attributes;
    request.value1 = frequency;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = (wk_config_response*)pendingRequests.waitForResponse(request.request_id);
    free(response);
}


- (void) configurePWMChannel: (uint8_t) timer channel: (uint8_t) channel attributes: (PWMChannelAttributes) attributes
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_CONFIG_MODULE;
    request.port_type = WK_CFG_MODULE_PWM_CHANNEL;
    request.request_id = portList.nextRequestId();
    request.pin_config = timer;
    request.port_attributes = attributes;
    request.value1 = channel;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = (wk_config_response*)pendingRequests.waitForResponse(request.request_id);
    free(response);
}


#pragma mark - I2C communication

- (PortID) configureI2CMaster: (I2CPins)pins frequency: (uint32_t)frequency
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_CONFIG_PORT;
    request.port_type = WK_CFG_PORT_TYPE_I2C;
    request.request_id = portList.nextRequestId();
    request.pin_config = pins;
    request.value1 = frequency;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = (wk_config_response*)pendingRequests.waitForResponse(request.request_id);
    
    Port* port = NULL;
    PortID portId = 0;
    if (response->result == WK_RESULT_OK) {
        portId = response->port_id;
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
    if (deviceStatus != StatusReady)
        return;
    
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.message_size = sizeof(wk_config_request);
    request.header.message_type = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_RELEASE;
    request.port_id = port;
    request.request_id = portList.nextRequestId();
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = (wk_config_response*)pendingRequests.waitForResponse(request.request_id);
    
    Port* p = portList.getPort(port);
    portList.removePort(port);
    free(response);
    delete p;
}


- (int) sendOnI2CPort: (PortID)port data: (NSData*)data toSlave: (uint16_t)slave
{
    Port* p = portList.getPort(port);
    if (p == nil)
        return 0;
    
    uint16_t requestId = portList.nextRequestId();
    [self submitSendOnI2CPort:port data:data toSlave:slave requestId:requestId];
    
    wk_port_event* response = (wk_port_event*)pendingRequests.waitForResponse(requestId);
    
    uint16_t transmitted = response->event_attribute2;
    p->setLastSample((I2CResult)response->event_attribute1);
    free(response);
    return transmitted;
}


- (void) submitOnI2CPort: (PortID)port data: (NSData*)data toSlave: (uint16_t)slave
{
    Port* p = portList.getPort(port);
    if (p == nil)
        return;
    
    [self submitSendOnI2CPort:port data:data toSlave:slave requestId:0];
}


- (void) submitSendOnI2CPort: (PortID)port data: (NSData*)data toSlave: (uint16_t)slave requestId: (uint16) requestId
{
    NSUInteger len = data.length;
    size_t msg_len = sizeof(wk_port_request) - 4 + len;
    wk_port_request* request = (wk_port_request*)malloc(msg_len);
    memset(request, 0, msg_len);
    request->header.message_size = msg_len;
    request->header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request->port_id = port;
    request->request_id = requestId;
    request->action = WK_PORT_ACTION_TX_DATA;
    request->action_attribute2 = slave;
    memcpy(request->data, data.bytes, len);
    
    [self writeMessage:&request->header];
    free(request);
}


- (NSData*) requestDataOnI2CPort: (PortID)port fromSlave: (uint16_t)slave length: (uint16_t)length
{
    Port* p = portList.getPort(port);
    if (p == nil)
        return nil;
    
    wk_port_request request;
    memset(&request, 0, sizeof(wk_port_request));
    request.header.message_size = sizeof(wk_port_request) - 2;
    request.header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request.port_id = port;
    request.request_id = portList.nextRequestId();
    request.action = WK_PORT_ACTION_RX_DATA;
    request.action_attribute2 = slave;
    request.value1 = length;
    
    [self writeMessage:&request.header];
    wk_port_event* response = (wk_port_event*)pendingRequests.waitForResponse(request.request_id);
    
    I2CResult result = (I2CResult)response->event_attribute1;
    p->setLastSample(result);
    
    NSData* data = nil;
    size_t dataLength = response->header.message_size - sizeof(wk_port_event) + 4;
    if (dataLength > 0)
        data = [NSData dataWithBytes:response->data length:dataLength];
    
    free(response);
    return data;
}


- (NSData*) sendAndRequestOnI2CPort: (PortID)port data: (NSData*)data toSlave: (uint16_t)slave receiveLength: (uint16_t)receiveLength
{
    Port* p = portList.getPort(port);
    if (p == nil)
        return 0;
    
    NSUInteger len = data.length;
    size_t msg_len = sizeof(wk_port_request) - 4 + len;
    wk_port_request* request = (wk_port_request*)malloc(msg_len);
    memset(request, 0, msg_len);
    request->header.message_size = msg_len;
    request->header.message_type = WK_MSG_TYPE_PORT_REQUEST;
    request->port_id = port;
    request->request_id = portList.nextRequestId();
    request->action = WK_PORT_ACTION_TX_N_RX_DATA;
    request->action_attribute2 = slave;
    request->value1 = receiveLength;
    memcpy(request->data, data.bytes, len);
    
    [self writeMessage:&request->header];
    uint16_t request_id = request->request_id;
    free(request);

    wk_port_event* response = (wk_port_event*)pendingRequests.waitForResponse(request_id);
    
    I2CResult result = (I2CResult)response->event_attribute1;
    p->setLastSample(result);
    
    NSData* rxData = nil;
    size_t dataLength = response->header.message_size - sizeof(wk_port_event) + 4;
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


#pragma mark - Message handling


- (void) handleConfigResponse: (wk_config_response*) response
{
    pendingRequests.putResponse(response->request_id, (wk_msg_header*)response);
}


- (void) handlePortEvent: (wk_port_event*) event
{
    if (event->event == WK_EVENT_SINGLE_SAMPLE) {
        Port* port = portList.getPort(event->port_id);
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
            int16_t value = (int16_t)event->value1;
            free(event);
            port->setLastSample(value);
            
            NSNumber* key = [NSNumber numberWithUnsignedShort:port->portId()];
            AnalogInputPinCallback callback = analogInputPinCallbacks[key];
            dispatch_queue_t dispatchQueue = analogInputDispatchQueues[key];
            if (callback != nil && dispatchQueue != nil) {
                dispatch_async(dispatchQueue, ^{
                    callback(port->portId(), value);
                });
            }
            return;
        }
        
    } else if (event->event == WK_EVENT_TX_COMPLETE || event->event == WK_EVENT_DATA_RECV) {
        Port* port = portList.getPort(event->port_id);
        if (port == NULL)
            goto error;
        
        PortType portType = port->type();
        if (portType == PortTypeI2C) {
            if (event->request_id != 0) {
                pendingRequests.putResponse(event->request_id, (wk_msg_header*)event);
            } else {
                free(event);
            }
            return;
        }    
    }

error:
    NSLog(@"Wirekite: Unknown event (%d) for port (%d) received", event->event, event->port_id);
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
