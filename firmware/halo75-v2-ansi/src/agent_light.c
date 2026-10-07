/* SPDX-License-Identifier: GPL-2.0-or-later
 * NuphyBar Halo75 V2 ANSI QMK adapter.
 */
#include "agent_light.h"

#include "ansi.h"
#include "effect_model.h"
#include "raw_hid.h"
#include "rgb_matrix.h"
#include "timer.h"

#define HALO75_LEFT_LIGHT_INDEX 83
#define ACTIVE_STATE_TIMEOUT_MS (15UL * 60UL * 1000UL)
#define TERMINAL_STATE_TIMEOUT_MS (20UL * 1000UL)

extern DEV_INFO_STRUCT dev_info;

static agent_light_state_t current_state = AGENT_LIGHT_IDLE;
static uint32_t state_started_at;
static agent_light_state_t wireless_state = AGENT_LIGHT_IDLE;
static uint32_t wireless_state_started_at;
static uint8_t previous_link_mode = LINK_USB;

bool agent_light_handle_via_command(uint8_t *data, uint8_t length) {
    agent_light_state_t next_state;
    if (!agent_light_decode_report(data, length, &next_state)) return false;

    current_state = next_state;
    state_started_at = timer_read32();
    data[3] |= 0x80;
    data[AGENT_LIGHT_REPORT_SIZE - 1] = 0;
    for (uint8_t i = 0; i < AGENT_LIGHT_REPORT_SIZE - 1; i++) {
        data[AGENT_LIGHT_REPORT_SIZE - 1] ^= data[i];
    }
    raw_hid_send(data, length);
    return true;
}

void agent_light_render_overlay(void) {
    uint32_t now = timer_read32();
    if (dev_info.link_mode != previous_link_mode) {
        current_state = AGENT_LIGHT_IDLE;
        wireless_state = AGENT_LIGHT_IDLE;
        wireless_state_started_at = now;
        previous_link_mode = dev_info.link_mode;
    }

    bool is_usb = dev_info.link_mode == LINK_USB;
    bool is_connected_bluetooth =
        dev_info.link_mode >= LINK_BT_1 &&
        dev_info.link_mode <= LINK_BT_3 &&
        dev_info.rf_state == RF_CONNECT;
    agent_light_state_t displayed_state;
    uint32_t started_at;
    if (is_usb) {
        displayed_state = current_state;
        started_at = state_started_at;
    } else if (is_connected_bluetooth) {
        agent_light_state_t next_state = agent_light_select_transport_state(
            false, true, dev_info.rf_led, current_state);
        if (next_state != wireless_state) {
            wireless_state = next_state;
            wireless_state_started_at = now;
        }
        displayed_state = wireless_state;
        started_at = wireless_state_started_at;
    } else {
        wireless_state = AGENT_LIGHT_IDLE;
        wireless_state_started_at = now;
        return;
    }

    if (displayed_state == AGENT_LIGHT_IDLE) return;

    uint32_t elapsed_ms = now - started_at;
    uint32_t timeout_ms = displayed_state == AGENT_LIGHT_COMPLETE || displayed_state == AGENT_LIGHT_ERROR
        ? TERMINAL_STATE_TIMEOUT_MS
        : ACTIVE_STATE_TIMEOUT_MS;
    if (is_usb && elapsed_ms > timeout_ms) {
        current_state = AGENT_LIGHT_IDLE;
        return;
    }

    agent_light_frame_t frame;
    if (!agent_light_model_render(displayed_state, elapsed_ms, &frame)) return;
    for (uint8_t i = 0; i < 5; i++) {
        rgb_matrix_set_color(
            HALO75_LEFT_LIGHT_INDEX + i,
            frame.pixel[i].red,
            frame.pixel[i].green,
            frame.pixel[i].blue
        );
    }
}

bool via_command_kb(uint8_t *data, uint8_t length) {
    return agent_light_handle_via_command(data, length);
}
