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
    inserted(PTHREAD_COND_INITIALIZER)
{
    pthread_mutex_init(&mutex, NULL);
    pthread_cond_init(&inserted, NULL);
}


PendingRequestList::~PendingRequestList()
{
    pthread_cond_destroy(&inserted);
    pthread_mutex_destroy(&mutex);
}


void PendingRequestList::putResponse(uint16_t requestId, wk_config_response* response)
{
    pthread_mutex_lock(&mutex);
    
    PendingRequest request;
    request.requestId = requestId;
    request.response = response;
    requests.push_back(request);
    
    pthread_cond_broadcast(&inserted);
    pthread_mutex_unlock(&mutex);
}


wk_config_response* PendingRequestList::waitForResponse(uint16_t requestId)
{
    pthread_mutex_lock(&mutex);
    
    std::vector<PendingRequest>::iterator it;
    while (true) {
        for (it = requests.begin(); it != requests.end(); it++)
            if ((*it).requestId == requestId)
                break;
        if (it != requests.end())
            break;
        pthread_cond_wait(&inserted, &mutex);
    }
    
    wk_config_response* result = (*it).response;
    requests.erase(it);
    
    pthread_mutex_unlock(&mutex);
    
    return result;
}


void PendingRequestList::clear()
{
    pthread_mutex_lock(&mutex);
    
    for (std::vector<PendingRequest>::iterator it = requests.begin(); it != requests.end(); it++)
        free((*it).response);
    requests.clear();
    
    pthread_mutex_unlock(&mutex);
}
