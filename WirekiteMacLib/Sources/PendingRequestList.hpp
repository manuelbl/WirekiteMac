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
#include <unordered_set>
#include "proto.h"


class PendingRequest {
public:
    uint16_t requestId;
    wk_msg_header* response;
};


class PendingRequestList {
public:
    PendingRequestList();
    ~PendingRequestList();
    
    void putResponse(uint16_t requestId, wk_msg_header* response);
    wk_msg_header* waitForResponse(uint16_t requestId);
    void clear();

private:
    std::vector<PendingRequest> completedRequests;
    std::unordered_set<uint16_t> waitingForRequests;
    pthread_cond_t inserted;
    pthread_mutex_t mutex;
    bool isDestroyed;
};

#endif /* PendingRequest_hpp */
