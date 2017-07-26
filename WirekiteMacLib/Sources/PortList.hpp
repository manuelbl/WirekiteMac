//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#ifndef PortList_hpp
#define PortList_hpp

#include <pthread.h>
#include <vector>
#include "Port.hpp"


class PortList
{
public:
    PortList();
    ~PortList();
    
    Port* getPort(uint16_t portId);
    void addPort(Port* port);
    void removePort(uint16_t portId);
    void clear();
    
    uint16_t nextRequestId();
    
private:
    pthread_mutex_t port_mutex;
    std::vector<Port*> ports;
    uint16_t lastRequestId;
};


#endif /* PortList_hpp */
