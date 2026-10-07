/* SPDX-License-Identifier: GPL-2.0-or-later */
#pragma once

#include <stdbool.h>
#include <stdint.h>

bool agent_light_handle_via_command(uint8_t *data, uint8_t length);
void agent_light_render_overlay(void);

