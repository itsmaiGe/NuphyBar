/* SPDX-License-Identifier: GPL-2.0-or-later */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define AGENT_LIGHT_REPORT_SIZE 32

typedef enum {
    AGENT_LIGHT_IDLE = 0,
    AGENT_LIGHT_THINKING = 1,
    AGENT_LIGHT_TOOL_RUNNING = 2,
    AGENT_LIGHT_OUTPUTTING = 3,
    AGENT_LIGHT_PERMISSION = 4,
    AGENT_LIGHT_COMPLETE = 5,
    AGENT_LIGHT_ERROR = 6,
} agent_light_state_t;

typedef struct {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
} agent_light_pixel_t;

typedef struct {
    agent_light_pixel_t pixel[5];
} agent_light_frame_t;

bool agent_light_decode_report(const uint8_t *report, size_t length,
                               agent_light_state_t *state);
agent_light_state_t agent_light_decode_wireless_led(uint8_t led_mask);
agent_light_state_t agent_light_select_transport_state(
    bool is_usb, bool is_connected_bluetooth, uint8_t wireless_led_mask,
    agent_light_state_t usb_state);
bool agent_light_model_render(agent_light_state_t state, uint32_t elapsed_ms,
                              agent_light_frame_t *frame);
