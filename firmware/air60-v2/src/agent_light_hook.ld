/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright 2026 Maige.
 */
ENTRY(agent_light_hook)

MEMORY
{
    FLASH (rx) : ORIGIN = 0x08010E00, LENGTH = 0x200
}

official_sys_led_show = 0x080023A4;
official_timer_read32 = 0x0800B2E8;
official_rgb_matrix_set_color = 0x08007E38;
official_dev_info = 0x20000C80;
__aeabi_uidiv = 0x08000218;
__aeabi_uidivmod = 0x08000290;

SECTIONS
{
    .text :
    {
        KEEP(*(.text.agent_light_hook))
        *(.text*)
        *(.rodata*)
    } > FLASH
}

ASSERT(SIZEOF(.text) <= LENGTH(FLASH), "Agent Light hook exceeds reserved flash")
