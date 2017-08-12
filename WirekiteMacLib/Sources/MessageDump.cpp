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
    "config_port",
    "release",
    "reset",
    "config_module"
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
    buf << "message_size: " << msg->message_size << "\n";
    buf << "message_type: " << SafeElement(MessageTypes, msg->message_type) << " (" << (int)msg->message_type << ")\n";
    
    if (msg->message_type == WK_MSG_TYPE_CONFIG_REQUEST) {
        wk_config_request* request = (wk_config_request*)msg;
        buf << "action: " << SafeElement(ConfigActions, request->action) << " (" << (int)request->action << ")\n";
        buf << "port_type: " << SafeElement(PortTypes, request->port_type) << " (" << (int)request->port_type << ")\n";
        buf << "port_id: " << request->port_id << "\n";
        buf << "request_id: " << request->request_id << "\n";
        buf << "port_attributes: " << request->port_attributes << "\n";
        buf << "pin_config: " << request->pin_config << "\n";
        buf << "value1: " << request->value1 << "\n";
    } else if (msg->message_type == WK_MSG_TYPE_CONFIG_RESPONSE) {
        wk_config_response* response = (wk_config_response*)msg;
        buf << "result: " << response->result << "\n";
        buf << "port_id: " << response->port_id << "\n";
        buf << "request_id: " << response->request_id << "\n";
        buf << "optional1: " << response->optional1 << "\n";
    } else if (msg->message_type == WK_MSG_TYPE_PORT_REQUEST) {
        wk_port_request* request = (wk_port_request*)msg;
        buf << "port_id: " << request->port_id << "\n";
        buf << "action: " << SafeElement(PortActions, request->action) << " (" << (int)request->action << ")\n";
        buf << "action_attribute1: " << (int)request->action_attribute1 << "\n";
        buf << "action_attribute2: " << request->action_attribute2 << "\n";
        int data_length = msg->message_size - sizeof(wk_port_request) + 4;
        dumpData(buf, request->data, data_length);
    } else if (msg->message_type == WK_MSG_TYPE_PORT_EVENT) {
        wk_port_event* event = (wk_port_event*)msg;
        buf << "port_id: " << event->port_id << "\n";
        buf << "action: " << SafeElement(PortEvents, event->event) << " (" << (int)event->event << ")\n";
        buf << "event_attribute1: " << (int)event->event_attribute1 << "\n";
        buf << "request_id: " << event->request_id << "\n";
        int data_length = msg->message_size - sizeof(wk_port_event) + 4;
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
