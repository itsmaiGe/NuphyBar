/* SPDX-License-Identifier: GPL-2.0-or-later
 * NuphyBar Air60 V2 status-light hook, added 2026-07-13.
 * Copyright 2026 Maige.
 */
#include "effect_model.h"

#include <stdint.h>

typedef struct {
    uint8_t link_mode;
    uint8_t rf_channel;
    uint8_t ble_channel;
    uint8_t rf_state;
    uint8_t rf_charge;
    uint8_t rf_led;
    uint8_t rf_battery;
    uint8_t sys_sw_state;
} dev_info_t;

extern volatile const dev_info_t official_dev_info;
extern void official_sys_led_show(void);
extern uint32_t official_timer_read32(void);
extern void official_rgb_matrix_set_color(uint8_t index, uint8_t red, uint8_t green,
                                          uint8_t blue);

__attribute__((section(".text.agent_light_hook"), used))
void agent_light_hook(void) {
    agent_light_frame_t frame;
    uint8_t agent_state;

    official_sys_led_show();
    if (official_dev_info.link_mode == 4) return;
    agent_state = official_dev_info.rf_led & 0x05;
    if (agent_state == 0) return;
    if (!agent_light_render(agent_state, official_timer_read32(), &frame)) return;

    for (uint8_t i = 0; i < 5; i++) {
        official_rgb_matrix_set_color(
            (uint8_t)(69 + i),
            frame.pixel[i].red,
            frame.pixel[i].green,
            frame.pixel[i].blue);
    }
}
