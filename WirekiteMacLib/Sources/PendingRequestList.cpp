//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#include <stdlib.h>
#include "PendingRequestList.hpp"



PendingRequestList::PendingRequestList()
:   mutex(PTHREAD_MUTEX_INITIALIZER),
    inserted(PTHREAD_COND_INITIALIZER),
    isDestroyed(false)
{
    pthread_mutex_init(&mutex, NULL);
    pthread_cond_init(&inserted, NULL);
}


PendingRequestList::~PendingRequestList()
{
    isDestroyed = true;
    pthread_cond_destroy(&inserted);
    pthread_mutex_destroy(&mutex);
}


void PendingRequestList::putResponse(uint16_t requestId, wk_msg_header* response)
{
    pthread_mutex_lock(&mutex);
    
    if (waitingForRequests.count(requestId) > 0)
    {
        PendingRequest request;
        request.requestId = requestId;
        request.response = response;
        completedRequests.push_back(request);
        
        pthread_cond_broadcast(&inserted);
    }
    else
    {
        free(response);
    }
    
    pthread_mutex_unlock(&mutex);
}


wk_msg_header* PendingRequestList::waitForResponse(uint16_t requestId)
{
    pthread_mutex_lock(&mutex);
    
    waitingForRequests.insert(requestId);
    
    std::vector<PendingRequest>::iterator it;
    while (!isDestroyed) {
        for (it = completedRequests.begin(); it != completedRequests.end(); it++)
            if ((*it).requestId == requestId)
                break;
        if (it != completedRequests.end())
            break;
        pthread_cond_wait(&inserted, &mutex);
    }
    
    wk_msg_header* result = NULL;
    if (!isDestroyed)
    {
        result = (*it).response;
        completedRequests.erase(it);
    }
    
    waitingForRequests.erase(requestId);
    
    pthread_mutex_unlock(&mutex);
    
    return result;
}


void PendingRequestList::clear()
{
    pthread_mutex_lock(&mutex);
    
    for (std::vector<PendingRequest>::iterator it = completedRequests.begin(); it != completedRequests.end(); it++)
        free((*it).response);
    completedRequests.clear();
    waitingForRequests.clear();
    
    pthread_mutex_unlock(&mutex);
}
