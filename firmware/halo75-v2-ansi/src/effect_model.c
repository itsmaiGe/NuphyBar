/* SPDX-License-Identifier: GPL-2.0-or-later
 * NuphyBar Halo75 V2 ANSI lighting effects.
 */
#include "effect_model.h"

static const uint8_t breathe_curve[32] = {
    24, 25, 27, 30, 34, 39, 45, 52,
    60, 69, 79, 90, 102, 115, 129, 143,
    157, 171, 185, 198, 210, 221, 231, 239,
    246, 250, 253, 255, 255, 253, 250, 246,
};

static uint8_t scale_channel(uint8_t channel, uint8_t level) {
    return (uint8_t)(((uint16_t)channel * level + 255) >> 8);
}

static void fill(agent_light_frame_t *frame, uint8_t red, uint8_t green,
                 uint8_t blue, uint8_t level) {
    for (uint8_t i = 0; i < 5; i++) {
        frame->pixel[i].red = scale_channel(red, level);
        frame->pixel[i].green = scale_channel(green, level);
        frame->pixel[i].blue = scale_channel(blue, level);
    }
}

static uint8_t breathe_level(uint32_t elapsed_ms, uint16_t step_ms) {
    uint8_t phase = (uint8_t)((elapsed_ms / step_ms) & 0x3F);
    uint8_t index = phase < 32 ? phase : (uint8_t)(63 - phase);
    return breathe_curve[index];
}

bool agent_light_decode_report(const uint8_t *report, size_t length,
                               agent_light_state_t *state) {
    if (report == NULL || state == NULL || length != AGENT_LIGHT_REPORT_SIZE) {
        return false;
    }
    if (report[0] != 0x4E || report[1] != 0x42 ||
        report[2] != 0x01 || report[3] != 0x01 ||
        report[4] > AGENT_LIGHT_ERROR) {
        return false;
    }

    uint8_t checksum = 0;
    for (size_t i = 0; i < AGENT_LIGHT_REPORT_SIZE - 1; i++) {
        checksum ^= report[i];
    }
    if (checksum != report[AGENT_LIGHT_REPORT_SIZE - 1]) {
        return false;
    }

    *state = (agent_light_state_t)report[4];
    return true;
}

agent_light_state_t agent_light_decode_wireless_led(uint8_t led_mask) {
    switch (led_mask & 0x05) {
        case 0x01:
            return AGENT_LIGHT_THINKING;
        case 0x04:
            return AGENT_LIGHT_PERMISSION;
        case 0x05:
            return AGENT_LIGHT_COMPLETE;
        default:
            return AGENT_LIGHT_IDLE;
    }
}

agent_light_state_t agent_light_select_transport_state(
    bool is_usb, bool is_connected_bluetooth, uint8_t wireless_led_mask,
    agent_light_state_t usb_state) {
    if (is_usb) return usb_state;
    if (is_connected_bluetooth) {
        return agent_light_decode_wireless_led(wireless_led_mask);
    }
    return AGENT_LIGHT_IDLE;
}

bool agent_light_model_render(agent_light_state_t state, uint32_t elapsed_ms,
                              agent_light_frame_t *frame) {
    if (frame == NULL) return false;

    switch (state) {
        case AGENT_LIGHT_IDLE:
            return false;
        case AGENT_LIGHT_THINKING:
            fill(frame, 255, 0, 0, breathe_level(elapsed_ms, 32));
            return true;
        case AGENT_LIGHT_TOOL_RUNNING:
            fill(frame, 255, 0, 0, 255);
            return true;
        case AGENT_LIGHT_OUTPUTTING:
            fill(frame, 255, 160, 0, breathe_level(elapsed_ms, 32));
            return true;
        case AGENT_LIGHT_PERMISSION:
            fill(frame, 0, 96, 255, breathe_level(elapsed_ms, 12));
            return true;
        case AGENT_LIGHT_COMPLETE:
            fill(frame, 0, 255, 64, 255);
            return true;
        case AGENT_LIGHT_ERROR:
            fill(frame, 255, 0, 0, ((elapsed_ms / 200) & 1) == 0 ? 255 : 0);
            return true;
    }
    return false;
}
