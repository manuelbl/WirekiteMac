//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#ifndef PendingRequestList_hpp
#define PendingRequestList_hpp

#include <pthread.h>
#include <vector>
#include "proto.h"


class PendingRequest {
public:
    uint16_t requestId;
    wk_config_response* response;
};


class PendingRequestList {
public:
    PendingRequestList();
    ~PendingRequestList();
    
    void putResponse(uint16_t requestId, wk_config_response* response);
    wk_config_response* waitForResponse(uint16_t requestId);
    void clear();
    
private:
    std::vector<PendingRequest> requests;
    pthread_cond_t inserted;
    pthread_mutex_t mutex;
};

#endif /* PendingRequest_hpp */
