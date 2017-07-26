//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#include "PortList.hpp"


PortList::PortList()
: port_mutex(PTHREAD_MUTEX_INITIALIZER),
    lastRequestId(0)
{
    pthread_mutex_init(&port_mutex, NULL);
}


PortList::~PortList()
{
    clear();
    pthread_mutex_destroy(&port_mutex);
}


Port* PortList::getPort(uint16_t portId)
{
    Port* port = NULL;
    pthread_mutex_lock(&port_mutex);
    
    for (std::vector<Port*>::iterator it = ports.begin(); it != ports.end(); it++) {
        if ((*it)->portId() == portId) {
            port = *it;
            break;
        }
    }
    
    pthread_mutex_unlock(&port_mutex);
    return port;
}


void PortList::addPort(Port* port)
{
    pthread_mutex_lock(&port_mutex);
    
    ports.push_back(port);
    
    pthread_mutex_unlock(&port_mutex);
}


void PortList::removePort(uint16_t portId)
{
    pthread_mutex_lock(&port_mutex);
    
    for (std::vector<Port*>::iterator it = ports.begin(); it != ports.end(); it++) {
        if ((*it)->portId() == portId) {
            ports.erase(it);
            break;
        }
    }
    
    pthread_mutex_unlock(&port_mutex);
}


uint16_t PortList::nextRequestId()
{
    pthread_mutex_lock(&port_mutex);
    
    lastRequestId++;
    uint16_t result = lastRequestId;
    
    pthread_mutex_unlock(&port_mutex);
    
    return result;
}


void PortList::clear()
{
    pthread_mutex_lock(&port_mutex);
    
    for (std::vector<Port*>::iterator it = ports.begin(); it != ports.end(); it++)
        delete (*it);
    ports.clear();
    
    pthread_mutex_unlock(&port_mutex);
}

