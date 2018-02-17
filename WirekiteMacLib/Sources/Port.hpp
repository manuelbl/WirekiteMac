//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#ifndef Port_hpp
#define Port_hpp

#include "proto.h"
#include "Queue.hpp"

enum PortType {
    PortTypeDigitalOutput,
    PortTypeDigitalInputOnDemand,
    PortTypeDigitalInputPrecached,
    PortTypeDigitalInputTriggering,
    PortTypeAnalogInputOnDemand,
    PortTypeAnalogInputSampling,
    PortTypePWMOutput,
    PortTypeI2C,
    PortTypeSPI
};


class Port
{
public:
    Port(uint16_t portId, PortType type, int queueLength);
    ~Port();
    
    uint16_t portId() { return _portId; }
    PortType type() { return _type; }
    
    int32_t lastSample() { return _lastSample; }
    void setLastSample(int32_t sample) { _lastSample = sample; }
    
    void pushEvent(wk_port_event* event);
    wk_port_event* waitForEvent();
    
private:
    uint16_t _portId;
    PortType _type;
    int32_t _lastSample;
    Queue<wk_port_event*> queue;
};

#endif /* Port_hpp */
