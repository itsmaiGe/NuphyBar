/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "effect_model.h"

#include <assert.h>
#include <stdio.h>

static void test_idle_and_caps_leave_stock_lighting_untouched(void) {
    agent_light_frame_t frame = {0};
    assert(!agent_light_render(0x00, 0, &frame));
    assert(!agent_light_render(0x02, 0, &frame));
}

static void assert_pixel(const agent_light_frame_t *frame, int index,
                         uint8_t red, uint8_t green, uint8_t blue) {
    assert(frame->pixel[index].red == red);
    assert(frame->pixel[index].green == green);
    assert(frame->pixel[index].blue == blue);
}

static void test_working_uses_one_blue_hue_with_a_moving_brightness_wave(void) {
    agent_light_frame_t frame = {0};
    assert(agent_light_render(0x01, 0, &frame));
    assert_pixel(&frame, 0, 0, 8, 32);
    assert_pixel(&frame, 1, 0, 29, 116);
    assert_pixel(&frame, 2, 0, 61, 241);
    assert_pixel(&frame, 3, 0, 57, 228);
    assert_pixel(&frame, 4, 0, 24, 94);

    const uint32_t dark_arrival_ms[5] = {0, 416, 832, 1248, 1664};
    for (int i = 0; i < 5; i++) {
        assert(agent_light_render(0x01, dark_arrival_ms[i], &frame));
        assert_pixel(&frame, i, 0, 8, 32);
    }
}

static void test_working_keeps_a_visible_dark_trough_without_blackout(void) {
    agent_light_frame_t frame = {0};
    for (int step = 0; step < 128; step++) {
        assert(agent_light_render(0x01, (uint32_t)step * 16, &frame));
        int darkest = 765;
        int brightest = 0;
        for (int i = 0; i < 5; i++) {
            assert(frame.pixel[i].red == 0);
            assert(frame.pixel[i].green <= 64);
            int channel_sum = frame.pixel[i].red + frame.pixel[i].green +
                              frame.pixel[i].blue;
            assert(channel_sum >= 40);
            if (channel_sum < darkest) darkest = channel_sum;
            if (channel_sum > brightest) brightest = channel_sum;
        }
        assert(darkest <= 70);
        assert(brightest >= 290);
    }
}

static void test_working_palette_wraps_without_a_visible_jump(void) {
    agent_light_frame_t before_wrap = {0};
    agent_light_frame_t after_wrap = {0};
    assert(agent_light_render(0x01, 2032, &before_wrap));
    assert(agent_light_render(0x01, 2048, &after_wrap));

    for (int i = 0; i < 5; i++) {
        int red_delta = before_wrap.pixel[i].red - after_wrap.pixel[i].red;
        int green_delta = before_wrap.pixel[i].green - after_wrap.pixel[i].green;
        int blue_delta = before_wrap.pixel[i].blue - after_wrap.pixel[i].blue;
        if (red_delta < 0) red_delta = -red_delta;
        if (green_delta < 0) green_delta = -green_delta;
        if (blue_delta < 0) blue_delta = -blue_delta;
        assert(red_delta <= 8);
        assert(green_delta <= 8);
        assert(blue_delta <= 8);
    }
}

static void test_waiting_uses_an_amber_double_pulse_with_a_quiet_gap(void) {
    agent_light_frame_t frame = {0};
    assert(agent_light_render(0x04, 0, &frame));
    for (int i = 0; i < 5; i++) assert_pixel(&frame, i, 255, 96, 0);

    assert(agent_light_render(0x04, 64, &frame));
    for (int i = 0; i < 5; i++) assert_pixel(&frame, i, 63, 24, 0);

    assert(agent_light_render(0x04, 96, &frame));
    for (int i = 0; i < 5; i++) assert_pixel(&frame, i, 0, 0, 0);

    assert(agent_light_render(0x04, 192, &frame));
    for (int i = 0; i < 5; i++) assert_pixel(&frame, i, 255, 96, 0);

    assert(agent_light_render(0x04, 640, &frame));
    for (int i = 0; i < 5; i++) assert_pixel(&frame, i, 0, 0, 0);

    assert(agent_light_render(0x04, 1280, &frame));
    for (int i = 0; i < 5; i++) assert_pixel(&frame, i, 255, 96, 0);
}

static void test_complete_breathes_all_five_leds_symmetrically(void) {
    agent_light_frame_t frame = {0};
    assert(agent_light_render(0x05, 0, &frame));
    for (int i = 0; i < 5; i++) assert_pixel(&frame, i, 0, 32, 8);

    assert(agent_light_render(0x05, 992, &frame));
    for (int i = 0; i < 5; i++) assert_pixel(&frame, i, 0, 255, 64);

    assert(agent_light_render(0x05, 1024, &frame));
    for (int i = 0; i < 5; i++) assert_pixel(&frame, i, 0, 255, 64);

    assert(agent_light_render(0x05, 2016, &frame));
    for (int i = 0; i < 5; i++) assert_pixel(&frame, i, 0, 32, 8);
}

static void test_caps_bit_is_preserved_but_ignored_by_right_side_state(void) {
    agent_light_frame_t without_caps = {0};
    agent_light_frame_t with_caps = {0};
    assert(agent_light_render(0x01, 320, &without_caps));
    assert(agent_light_render(0x03, 320, &with_caps));
    for (int i = 0; i < 5; i++) {
        assert(without_caps.pixel[i].red == with_caps.pixel[i].red);
        assert(without_caps.pixel[i].green == with_caps.pixel[i].green);
        assert(without_caps.pixel[i].blue == with_caps.pixel[i].blue);
    }
}

static void test_channel_scaling_reaches_true_off_and_full_brightness(void) {
    assert(agent_light_scale_channel(255, 0) == 0);
    assert(agent_light_scale_channel(255, 255) == 255);
    assert(agent_light_scale_channel(64, 255) == 64);
}

int main(void) {
    test_idle_and_caps_leave_stock_lighting_untouched();
    test_working_uses_one_blue_hue_with_a_moving_brightness_wave();
    test_working_keeps_a_visible_dark_trough_without_blackout();
    test_working_palette_wraps_without_a_visible_jump();
    test_waiting_uses_an_amber_double_pulse_with_a_quiet_gap();
    test_complete_breathes_all_five_leds_symmetrically();
    test_caps_bit_is_preserved_but_ignored_by_right_side_state();
    test_channel_scaling_reaches_true_off_and_full_brightness();
    puts("effect model tests passed");
}
