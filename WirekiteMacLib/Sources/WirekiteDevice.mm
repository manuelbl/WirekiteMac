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


@interface WirekiteDevice ()
{
    io_object_t notification;
    IOUSBDeviceInterface** device;
    IOUSBInterfaceInterface** interface;
    uint16_t rxBuffer[2][RX_BUFFER_SIZE];
    int pendingBuffer;

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
}


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


- (void) writeString: (NSString*)str
{
    const char* cstr = [str cStringUsingEncoding:NSUTF8StringEncoding];
    size_t size = strlen(cstr);
    [self writeBytes:(const uint8_t*)cstr size:size];
}

- (void) writeMessage:(wk_msg_header*)msg
{
    //NSLog(@"%s", MessageDump::dump(msg).c_str());
    [self writeBytes:(const uint8_t*)msg size:msg->messageSize];
}


- (void) writeBytes: (const uint8_t*)bytes size: (uint16_t) size
{
    IOReturn kr = (*interface)->WritePipeAsync(interface,
                                               EndpointTransmit,
                                               (void*)bytes,
                                               size,
                                               WriteCompletion,
                                               (__bridge void*)self);
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
        uint16_t msgSize = header->messageSize;
        wk_msg_header* copy = (wk_msg_header*) malloc(msgSize);
        memcpy(copy, header, msgSize);
        
        //NSLog(@"%s", MessageDump::dump(header).c_str());
        
        if (header->messageType == WK_MSG_TYPE_CONFIG_RESPONSE) {
            [self handleConfigResponse: (wk_config_response*)copy];
        } else if (header->messageType == WK_MSG_TYPE_PORT_EVENT) {
            [self handlePortEvent: (wk_port_event*)copy];
        } else {
            NSLog(@"Wirekite: Message of unknown type %d received", msgSize);
            free(copy);
        }
        processedBytes += msgSize;
        // TODO: partial messages
    }
}


- (void) resetConfiguration
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.messageSize = sizeof(wk_config_request);
    request.header.messageType = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_RESET;
    request.requestId = portList.nextRequestId();
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = pendingRequests.waitForResponse(request.requestId);
    free(response);
    
    portList.clear();
    pendingRequests.clear();
    [digitalInputPinCallbacks removeAllObjects];
    [digitalInputDispatchQueues removeAllObjects];
    [analogInputPinCallbacks removeAllObjects];
    [analogInputDispatchQueues removeAllObjects];
}


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
    request.header.messageSize = sizeof(wk_config_request);
    request.header.messageType = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_CONFIG_PORT;
    request.portType = WK_CFG_PORT_TYPE_DIGI_PIN;
    request.requestId = portList.nextRequestId();
    request.portAttributes = attributes;
    request.pinConfig = pin;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = pendingRequests.waitForResponse(request.requestId);

    Port* port = NULL;
    if (response->result == WK_RESULT_OK) {
        port = new Port(response->portId, type, 10);
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
    request.header.messageSize = sizeof(wk_config_request);
    request.header.messageType = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_RELEASE;
    request.portId = portId;
    
    [self writeMessage:&request.header];

    wk_config_response* response = pendingRequests.waitForResponse(portId);
    
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
    request.header.messageSize = sizeof(wk_port_request);
    request.header.messageType = WK_MSG_TYPE_PORT_REQUEST;
    request.portId = portId;
    request.action = WK_PORT_ACTION_SET_VALUE;
    request.data[0] = value ? 1 : 0;

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
    request.header.messageSize = sizeof(wk_port_request);
    request.header.messageType = WK_MSG_TYPE_PORT_REQUEST;
    request.portId = portId;
    request.action = WK_PORT_ACTION_GET_VALUE;
    request.actionAttribute1 = 0;
    request.actionAttribute2 = 0;
    request.requestId = 0;
    request.data[0] = 0;
    request.data[1] = 0;
    request.data[2] = 0;
    request.data[3] = 0;

    [self writeMessage:&request.header];

    wk_port_event* event = port->waitForEvent();
    
    BOOL result = event->data[0] != 0;
    free(event);
    return result;
}


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
    request.header.messageSize = sizeof(wk_config_request);
    request.header.messageType = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_CONFIG_PORT;
    request.portType = WK_CFG_PORT_TYPE_ANALOG_IN;
    request.requestId = portList.nextRequestId();
    request.pinConfig = pin;
    request.value1 = interval;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = pendingRequests.waitForResponse(request.requestId);
    
    Port* port = NULL;
    if (response->result == WK_RESULT_OK) {
        port = new Port(response->portId, interval == 0 ? PortTypeAnalogInputOnDemand : PortTypeAnalogInputSampling, 10);
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
    request.header.messageSize = sizeof(wk_config_request);
    request.header.messageType = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_RELEASE;
    request.portId = portId;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = pendingRequests.waitForResponse(portId);
    
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
    request.header.messageSize = sizeof(wk_port_request);
    request.header.messageType = WK_MSG_TYPE_PORT_REQUEST;
    request.portId = portId;
    request.action = WK_PORT_ACTION_GET_VALUE;
    request.actionAttribute1 = 0;
    request.actionAttribute2 = 0;
    request.requestId = 0;
    request.data[0] = 0;
    request.data[1] = 0;
    request.data[2] = 0;
    request.data[3] = 0;
    
    [self writeMessage:&request.header];
    
    wk_port_event* event = port->waitForEvent();
    
    int16_t result = *(int16_t*)(&event->data);
    free(event);
    return result;
}


- (PortID) configurePWMOutputPin:(PWMPin)pin
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.messageSize = sizeof(wk_config_request);
    request.header.messageType = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_CONFIG_PORT;
    request.portType = WK_CFG_PORT_TYPE_PWM;
    request.requestId = portList.nextRequestId();
    request.pinConfig = pin;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = pendingRequests.waitForResponse(request.requestId);
    
    Port* port = NULL;
    PortID portId = 0;
    if (response->result == WK_RESULT_OK) {
        portId = response->portId;
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
    request.header.messageSize = sizeof(wk_config_request);
    request.header.messageType = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_RELEASE;
    request.portId = portId;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = pendingRequests.waitForResponse(portId);
    
    Port* port = portList.getPort(portId);
    portList.removePort(portId);
    free(response);
    delete port;
}


- (void) writePWMPinOnPort:(PortID)portId dutyCycle:(int16_t)dutyCycle
{
    wk_port_request request;
    memset(&request, 0, sizeof(wk_port_request));
    request.header.messageSize = sizeof(wk_port_request);
    request.header.messageType = WK_MSG_TYPE_PORT_REQUEST;
    request.portId = portId;
    request.action = WK_PORT_ACTION_SET_VALUE;
    int16_t* p = (int16_t*) &request.data;
    *p = dutyCycle;
    
    [self writeMessage:&request.header];
}


- (void) configurePWMTimer: (uint8_t) timer frequency: (uint32_t) frequency attributes: (PWMTimerAttributes) attributes
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.messageSize = sizeof(wk_config_request);
    request.header.messageType = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_CONFIG_MODULE;
    request.portType = WK_CFG_MODULE_PWM_TIMER;
    request.requestId = portList.nextRequestId();
    request.pinConfig = timer;
    request.portAttributes = attributes;
    request.value1 = frequency;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = pendingRequests.waitForResponse(request.requestId);
    free(response);
}


- (void) configurePWMChannel: (uint8_t) timer channel: (uint8_t) channel attributes: (PWMChannelAttributes) attributes
{
    wk_config_request request;
    memset(&request, 0, sizeof(wk_config_request));
    request.header.messageSize = sizeof(wk_config_request);
    request.header.messageType = WK_MSG_TYPE_CONFIG_REQUEST;
    request.action = WK_CFG_ACTION_CONFIG_MODULE;
    request.portType = WK_CFG_MODULE_PWM_CHANNEL;
    request.requestId = portList.nextRequestId();
    request.pinConfig = timer;
    request.portAttributes = attributes;
    request.value1 = channel;
    
    [self writeMessage:&request.header];
    
    wk_config_response* response = pendingRequests.waitForResponse(request.requestId);
    free(response);
}


- (void) handleConfigResponse: (wk_config_response*) response
{
    pendingRequests.putResponse(response->requestId, response);
}


- (void) handlePortEvent: (wk_port_event*) event
{
    if (event->event == WK_EVENT_SINGLE_SAMPLE) {
        Port* port = portList.getPort(event->portId);
        if (port == NULL)
            goto error;
        
        PortType portType = port->type();
        if (portType == PortTypeDigitalInputOnDemand) {
            port->pushEvent(event);
            return;
            
        } else if (portType == PortTypeDigitalInputPrecached || portType == PortTypeDigitalInputTriggering) {
            uint8_t value = event->data[0];
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
            int16_t value = (event->data[1] << 8) | event->data[0];
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
    }

error:
    NSLog(@"Wirekite: Unknown event (%d) for port (%d) received", event->event, event->portId);
    free(event);
}


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


void DeviceNotification(void *refCon, io_service_t service, natural_t messageType, void *messageArgument)
{
    WirekiteDevice* device = (__bridge WirekiteDevice*) refCon;
    [device onDeviceNotificationForService:service messageType:messageType messageArgument:messageArgument];
}


void WriteCompletion(void *refCon, IOReturn result, void *arg0)
{
    WirekiteDevice* device = (__bridge WirekiteDevice*) refCon;
    [device onWriteCompletedWithResult: result argument: arg0];
}


void ReadCompletion(void *refCon, IOReturn result, void *arg0)
{
    WirekiteDevice* device = (__bridge WirekiteDevice*) refCon;
    [device onReadCompletedWithResult: result argument: arg0];
}
