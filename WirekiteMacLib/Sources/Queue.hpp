//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#ifndef Queue_hpp
#define Queue_hpp

#include <pthread.h>
#include <algorithm>
#include <queue>


template <class E> class Queue {
   
public:
    Queue(int maxSize);
    ~Queue();
    
    E waitForNext();
    void put(E& elem);
    void clear(void(*deleter)(E));
    
private:
    std::queue<E> elements;
    int maxSize;
    pthread_cond_t not_empty;
    pthread_mutex_t mutex;
};


template <class E> Queue<E>::Queue(int maxSize):
maxSize(maxSize),
mutex(PTHREAD_MUTEX_INITIALIZER),
not_empty(PTHREAD_COND_INITIALIZER)
{
    pthread_mutex_init(&mutex, NULL);
    pthread_cond_init(&not_empty, NULL);
}


template <class E> Queue<E>::~Queue()
{
    pthread_cond_destroy(&not_empty);
    pthread_mutex_destroy(&mutex);
}


template <class E> void Queue<E>::put(E& elem)
{
    pthread_mutex_lock(&mutex);
    
    if (elements.size() == maxSize)
        elements.pop();  // drop oldest element
    elements.push(elem);
    
    pthread_cond_signal(&not_empty);
    pthread_mutex_unlock(&mutex);
}


template <class E> E Queue<E>::waitForNext() {
    pthread_mutex_lock(&mutex);
    while (elements.empty())
        pthread_cond_wait(&not_empty, &mutex);
    
    E result = elements.front();
    elements.pop();
    
    pthread_mutex_unlock(&mutex);
    
    return result;
}


template <class E> void Queue<E>::clear(void (*deleter)(E)) {
    pthread_mutex_lock(&mutex);
    
    while (!elements.empty()) {
        E elem = elements.front();
        elements.pop();
        deleter(elem);
    }
    
    pthread_mutex_unlock(&mutex);
}


#endif /* Queue_hpp */
