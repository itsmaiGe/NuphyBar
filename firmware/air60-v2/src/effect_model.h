/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright 2026 Maige.
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
} agent_light_pixel_t;

typedef struct {
    agent_light_pixel_t pixel[5];
} agent_light_frame_t;

bool agent_light_render(uint8_t host_leds, uint32_t now_ms, agent_light_frame_t *frame);

uint8_t agent_light_scale_channel(uint8_t channel, uint8_t level);
