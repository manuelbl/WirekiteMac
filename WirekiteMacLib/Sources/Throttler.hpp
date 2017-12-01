//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#ifndef Throttler_hpp
#define Throttler_hpp

#include <pthread.h>
#include <unordered_map>

/**
 * Throttles sending messages to the Wirekite such that the memory on the Wirekite is not overlaoded
 */
class Throttler {
public:
    Throttler();
    ~Throttler();
    
    /**
     * Gets the configured memory size
     * @return the memory size (in bytes)
     */
    int memorySize();
    
    /**
     * Configures the memory size.
     * @param size memory size (in bytes)
     */
    void configureMemorySize(int size);
    
    /**
     * Gets the maximum number of outstanding requests.
     * @return the number of requests
     */
    int maximumOutstanding();
    
    /**
     * Configures the maximum number of outstanding requets.
     * @param maxReq the number of requests
     */
    void configureMaximumOutstanding(int maxReq);
    
    /**
     * Configures the available memory size and the number of outstanding requets.
     * @param memSize memory size (in bytes) available on the microcontroller board for buffering data
     * @param maxReq the maximum number of requests to be outstanding at any time
     */
    void configure(int memSize, int maxReq);
    
    /**
     * Waits until the specified amount of memory is available on the Wirekite.
     *
     * The occupied memory size is then increased by that amount. Once the request
     * has completed, `requestCompleted` must be called to decreased it.
     *
     * @param requestId the ID of the request
     * @param requiredMemSize the required memory size (in bytes)
     */
    void waitUntilAvailable(uint16_t requestId, uint16_t requiredMemSize);
    
    /**
     * Decreases the amount of occupied memory by the amount speicified for the request.
     *
     * @param requestId the ID of the request
     */
    void requestCompleted(uint16_t requestId);
    
    
    void clear();
    
private:
    int memSize;
    int occupiedSize;
    int maxOutstandingRequests;
    int outstandingRequests;
    std::unordered_map<uint16_t, uint16_t> requests;
    pthread_cond_t available;
    pthread_mutex_t mutex;
    bool isDestroyed;
};


#endif /* Throttler_hpp */
