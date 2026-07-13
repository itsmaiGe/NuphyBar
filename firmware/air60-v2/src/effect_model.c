/* SPDX-License-Identifier: GPL-2.0-or-later
 * NuphyBar Air60 V2 lighting effects, added 2026-07-13.
 * Copyright 2026 Maige.
 */
#include "effect_model.h"

static const uint8_t breathe_curve[32] = {
    32, 33, 34, 37, 41, 46, 52, 59,
    67, 75, 85, 94, 105, 116, 127, 138,
    149, 160, 171, 182, 193, 202, 212, 220,
    228, 235, 241, 246, 250, 253, 254, 255,
};

static void fill_scaled(agent_light_frame_t *frame, uint8_t red, uint8_t green,
                        uint8_t blue, uint8_t level) {
    for (uint8_t i = 0; i < 5; i++) {
        frame->pixel[i].red = agent_light_scale_channel(red, level);
        frame->pixel[i].green = agent_light_scale_channel(green, level);
        frame->pixel[i].blue = agent_light_scale_channel(blue, level);
    }
}

static void render_working(uint32_t now_ms, agent_light_frame_t *frame) {
    uint8_t global_phase = (uint8_t)((now_ms >> 4) & 0x7F);

    for (uint8_t i = 0; i < 5; i++) {
        uint8_t pixel_phase = (uint8_t)((i * 26 + 128 - global_phase) & 0x7F);
        uint8_t curve_index = pixel_phase < 64
            ? pixel_phase >> 1
            : (uint8_t)(127 - pixel_phase) >> 1;
        uint8_t level = breathe_curve[curve_index];

        frame->pixel[i].red = 0;
        frame->pixel[i].green = agent_light_scale_channel(64, level);
        frame->pixel[i].blue = level;
    }
}

static void render_waiting(uint32_t now_ms, agent_light_frame_t *frame) {
    uint8_t step = (uint8_t)((now_ms >> 5) % 40);
    uint8_t pulse_step;
    uint8_t level = 0;

    if (step < 3) {
        pulse_step = step;
        level = (uint8_t)(255 - pulse_step * 96);
    } else if (step >= 6 && step < 9) {
        pulse_step = (uint8_t)(step - 6);
        level = (uint8_t)(255 - pulse_step * 96);
    }

    fill_scaled(frame, 255, 96, 0, level);
}

static void render_complete(uint32_t now_ms, agent_light_frame_t *frame) {
    uint8_t phase = (uint8_t)((now_ms >> 5) & 0x3F);
    uint8_t curve_index = phase < 32 ? phase : (uint8_t)(63 - phase);

    fill_scaled(frame, 0, 255, 64, breathe_curve[curve_index]);
}

bool agent_light_render(uint8_t host_leds, uint32_t now_ms, agent_light_frame_t *frame) {
    switch (host_leds & 0x05) {
        case 0x01:
            render_working(now_ms, frame);
            return true;
        case 0x04:
            render_waiting(now_ms, frame);
            return true;
        case 0x05:
            render_complete(now_ms, frame);
            return true;
        default:
            return false;
    }
}

uint8_t agent_light_scale_channel(uint8_t channel, uint8_t level) {
    return (uint8_t)(((uint16_t)channel * level + 255) >> 8);
}
