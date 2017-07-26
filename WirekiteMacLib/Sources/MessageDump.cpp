//
// Wirekite for MacOS
//
// Copyright (c) 2017 Manuel Bleichenbacher
// Licensed under MIT License
// https://opensource.org/licenses/MIT
//

#include "MessageDump.hpp"
#include <iomanip>
#include <sstream>

static const char* Invalid = "<invalid>";

static const char* MessageTypes[] = {
    "<invalid>",
    "config_request",
    "config_response",
    "port_request",
    "port_event"
};

static const char* ConfigActions[] = {
    "<invalid>",
    "config",
    "release",
    "reset"
};

static const char* PortTypes[] = {
    "<invalid>",
    "digi_pin",
    "analog_in",
    "pwm_out"
};

static const char* PortActions[] = {
    "<invalid>",
    "set_value",
    "get_value"
};

static const char* PortEvents[] = {
    "dodo",
    "single_sample"
};


#define SafeElement(array, index) (index < sizeof(array) / sizeof(array[0]) ? array[index] : Invalid)

static void dumpData(std::stringstream& buf, uint8_t* data, int len);


std::string MessageDump::dump(wk_msg_header* msg)
{
    std::stringstream buf;
    
    buf << std::hex << "\n";
    buf << "messageSize: " << msg->messageSize << "\n";
    buf << "messageType: " << SafeElement(MessageTypes, msg->messageType) << " (" << (int)msg->messageType << ")\n";
    
    if (msg->messageType == WK_MSG_TYPE_CONFIG_REQUEST) {
        wk_config_request* request = (wk_config_request*)msg;
        buf << "action: " << SafeElement(ConfigActions, request->action) << " (" << (int)request->action << ")\n";
        buf << "portType: " << SafeElement(PortTypes, request->portType) << " (" << (int)request->portType << ")\n";
        buf << "portId: " << request->portId << "\n";
        buf << "requestId: " << request->requestId << "\n";
        buf << "portAttributes: " << request->portAttributes << "\n";
        buf << "pinConfig: " << request->pinConfig << "\n";
        buf << "value1: " << request->value1 << "\n";
    } else if (msg->messageType == WK_MSG_TYPE_CONFIG_RESPONSE) {
        wk_config_response* response = (wk_config_response*)msg;
        buf << "result: " << response->result << "\n";
        buf << "portId: " << response->portId << "\n";
        buf << "requestId: " << response->requestId << "\n";
        buf << "optional1: " << response->optional1 << "\n";
    } else if (msg->messageType == WK_MSG_TYPE_PORT_REQUEST) {
        wk_port_request* request = (wk_port_request*)msg;
        buf << "portId: " << request->portId << "\n";
        buf << "action: " << SafeElement(PortActions, request->action) << " (" << (int)request->action << ")\n";
        buf << "actionAttribute1: " << (int)request->actionAttribute1 << "\n";
        buf << "actionAttribute2: " << request->actionAttribute2 << "\n";
        int data_length = msg->messageSize - sizeof(wk_port_request) + 4;
        dumpData(buf, request->data, data_length);
    } else if (msg->messageType == WK_MSG_TYPE_PORT_EVENT) {
        wk_port_event* event = (wk_port_event*)msg;
        buf << "portId: " << event->portId << "\n";
        buf << "action: " << SafeElement(PortEvents, event->event) << " (" << (int)event->event << ")\n";
        buf << "eventAttribute1: " << (int)event->eventAttribute1 << "\n";
        buf << "requestId: " << event->requestId << "\n";
        int data_length = msg->messageSize - sizeof(wk_port_event) + 4;
        dumpData(buf, event->data, data_length);
    }
    
    return buf.str();
}


void dumpData(std::stringstream& buf, uint8_t* data, int len)
{
    buf << "data: ";
    for (int i = 0; i < len; i++)
        buf << std::setw(2) << std::setfill('0') << (int)data[i];
    buf << "\n";
}
