/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "effect_model.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void encode_report(agent_light_state_t state, uint8_t *report) {
    memset(report, 0, AGENT_LIGHT_REPORT_SIZE);
    report[0] = 0x4E;
    report[1] = 0x42;
    report[2] = 0x01;
    report[3] = 0x01;
    report[4] = state;
    for (int i = 0; i < AGENT_LIGHT_REPORT_SIZE - 1; i++) {
        report[AGENT_LIGHT_REPORT_SIZE - 1] ^= report[i];
    }
}

static void assert_all(const agent_light_frame_t *frame, uint8_t red,
                       uint8_t green, uint8_t blue) {
    for (int i = 0; i < 5; i++) {
        assert(frame->pixel[i].red == red);
        assert(frame->pixel[i].green == green);
        assert(frame->pixel[i].blue == blue);
    }
}

static void test_protocol_accepts_all_states_and_rejects_damage(void) {
    uint8_t report[AGENT_LIGHT_REPORT_SIZE];
    for (int code = AGENT_LIGHT_IDLE; code <= AGENT_LIGHT_ERROR; code++) {
        agent_light_state_t state = AGENT_LIGHT_IDLE;
        encode_report((agent_light_state_t)code, report);
        assert(agent_light_decode_report(report, sizeof(report), &state));
        assert(state == (agent_light_state_t)code);
    }

    encode_report(AGENT_LIGHT_THINKING, report);
    report[10] = 1;
    agent_light_state_t state;
    assert(!agent_light_decode_report(report, sizeof(report), &state));
    assert(!agent_light_decode_report(report, sizeof(report) - 1, &state));
}

static void test_idle_restores_stock_lighting(void) {
    agent_light_frame_t frame = {0};
    assert(!agent_light_model_render(AGENT_LIGHT_IDLE, 0, &frame));
}

static void test_wireless_led_decoder_uses_only_num_and_scroll_lock(void) {
    assert(agent_light_decode_wireless_led(0x00) == AGENT_LIGHT_IDLE);
    assert(agent_light_decode_wireless_led(0x01) == AGENT_LIGHT_THINKING);
    assert(agent_light_decode_wireless_led(0x04) == AGENT_LIGHT_PERMISSION);
    assert(agent_light_decode_wireless_led(0x05) == AGENT_LIGHT_COMPLETE);

    assert(agent_light_decode_wireless_led(0x02) == AGENT_LIGHT_IDLE);
    assert(agent_light_decode_wireless_led(0x03) == AGENT_LIGHT_THINKING);
    assert(agent_light_decode_wireless_led(0x06) == AGENT_LIGHT_PERMISSION);
    assert(agent_light_decode_wireless_led(0x07) == AGENT_LIGHT_COMPLETE);
}

static void test_transport_selection_keeps_usb_rich_and_gates_wireless(void) {
    assert(agent_light_select_transport_state(
               true, false, 0x00, AGENT_LIGHT_OUTPUTTING) ==
           AGENT_LIGHT_OUTPUTTING);
    assert(agent_light_select_transport_state(
               false, true, 0x05, AGENT_LIGHT_ERROR) ==
           AGENT_LIGHT_COMPLETE);
    assert(agent_light_select_transport_state(
               false, false, 0x05, AGENT_LIGHT_ERROR) ==
           AGENT_LIGHT_IDLE);
}

static void test_solid_states_use_the_agreed_colors(void) {
    agent_light_frame_t frame = {0};
    assert(agent_light_model_render(AGENT_LIGHT_TOOL_RUNNING, 0, &frame));
    assert_all(&frame, 255, 0, 0);
    assert(agent_light_model_render(AGENT_LIGHT_COMPLETE, 0, &frame));
    assert_all(&frame, 0, 255, 64);
}

static void test_breathing_states_keep_their_hue(void) {
    agent_light_frame_t frame = {0};
    assert(agent_light_model_render(AGENT_LIGHT_THINKING, 0, &frame));
    assert(frame.pixel[0].red > 0);
    assert(frame.pixel[0].green == 0);
    assert(frame.pixel[0].blue == 0);

    assert(agent_light_model_render(AGENT_LIGHT_OUTPUTTING, 0, &frame));
    assert(frame.pixel[0].red > frame.pixel[0].green);
    assert(frame.pixel[0].green > 0);
    assert(frame.pixel[0].blue == 0);

    assert(agent_light_model_render(AGENT_LIGHT_PERMISSION, 0, &frame));
    assert(frame.pixel[0].red == 0);
    assert(frame.pixel[0].blue > frame.pixel[0].green);
}

static void test_error_flashes_red(void) {
    agent_light_frame_t frame = {0};
    assert(agent_light_model_render(AGENT_LIGHT_ERROR, 0, &frame));
    assert_all(&frame, 255, 0, 0);
    assert(agent_light_model_render(AGENT_LIGHT_ERROR, 200, &frame));
    assert_all(&frame, 0, 0, 0);
}

int main(void) {
    test_protocol_accepts_all_states_and_rejects_damage();
    test_idle_restores_stock_lighting();
    test_wireless_led_decoder_uses_only_num_and_scroll_lock();
    test_transport_selection_keeps_usb_rich_and_gates_wireless();
    test_solid_states_use_the_agreed_colors();
    test_breathing_states_keep_their_hue();
    test_error_flashes_red();
    puts("Halo75 V2 effect model tests passed");
}
