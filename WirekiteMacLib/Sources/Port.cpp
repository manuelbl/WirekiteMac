//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#include <stdlib.h>
#include "Port.hpp"


static void free_event(wk_port_event* event)
{
    free(event);
}


Port::Port(uint16_t portId, PortType type, int queueLength)
: _portId(portId), _type(type), _lastSample(0), queue(queueLength)
{
}


Port::~Port()
{
    queue.clear(free_event);
}


void Port::pushEvent(wk_port_event* event)
{
    queue.put(event);
}


wk_port_event* Port::waitForEvent()
{
    return queue.waitForNext();
}
