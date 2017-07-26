//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#ifndef MessageDump_hpp
#define MessageDump_hpp

#include "proto.h"
#include <string>

class MessageDump {
public:
    static std::string dump(wk_msg_header* msg);
};

#endif /* MessageDump_hpp */
