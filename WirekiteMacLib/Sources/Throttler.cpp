//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#include <stdlib.h>
#include "Throttler.hpp"



Throttler::Throttler()
:   memSize(4200),
    occupiedSize(0),
    maxOutstandingRequests(20),
    outstandingRequests(0),
    mutex(PTHREAD_MUTEX_INITIALIZER),
    available(PTHREAD_COND_INITIALIZER),
    isDestroyed(false)
{
    pthread_mutex_init(&mutex, NULL);
    pthread_cond_init(&available, NULL);
}


Throttler::~Throttler()
{
    isDestroyed = true;
    pthread_cond_destroy(&available);
    pthread_mutex_destroy(&mutex);
}


int Throttler::memorySize()
{
    return memSize;
}


void Throttler::configureMemorySize(int size)
{
    pthread_mutex_lock(&mutex);
    int oldMemSize = memSize;
    memSize = size;
    
    if (memSize > oldMemSize)
        pthread_cond_broadcast(&available);
    
    pthread_mutex_unlock(&mutex);
}


int Throttler::maximumOutstanding()
{
    return maxOutstandingRequests;
}


void Throttler::configureMaximumOutstanding(int maxReq)
{
    pthread_mutex_lock(&mutex);
    int oldMaxRequests = maxOutstandingRequests;
    maxOutstandingRequests = maxReq;
    
    if (maxOutstandingRequests > oldMaxRequests)
        pthread_cond_broadcast(&available);
    
    pthread_mutex_unlock(&mutex);
}


void Throttler::waitUntilAvailable(uint16_t requestId, uint16_t requiredMemSize)
{
    requiredMemSize += 8;
    pthread_mutex_lock(&mutex);
    
    while (!isDestroyed) {
        if (memSize - occupiedSize >= requiredMemSize
                && outstandingRequests < maxOutstandingRequests)
            break;
        pthread_cond_wait(&available, &mutex);
    }
    
    if (!isDestroyed)
    {
        occupiedSize += requiredMemSize;
        outstandingRequests++;
        requests[requestId] = requiredMemSize;
    }
    
    pthread_mutex_unlock(&mutex);
}


void Throttler::requestCompleted(uint16_t requestId)
{
    pthread_mutex_lock(&mutex);
    
    uint16_t requestSize = requests[requestId];
    requests.erase(requestId);
    occupiedSize -= requestSize;
    outstandingRequests--;
    
    pthread_cond_broadcast(&available);
    pthread_mutex_unlock(&mutex);
}


void Throttler::clear()
{
    pthread_mutex_lock(&mutex);
    isDestroyed = true;
    pthread_cond_broadcast(&available);
    pthread_mutex_unlock(&mutex);
    
    pthread_mutex_lock(&mutex);
    isDestroyed = false;
    occupiedSize = 0;
    outstandingRequests = 0;
    requests.clear();
    pthread_mutex_unlock(&mutex);
}
