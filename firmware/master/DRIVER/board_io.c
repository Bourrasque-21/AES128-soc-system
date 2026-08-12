#include "board_io.h"
#include "hal_platform.h"

#include "xil_io.h"

#define GPIO_CR_OFFSET     0x00u
#define GPIO_IDR_OFFSET    0x04u
#define GPIO_ODR_OFFSET    0x08u

#define GPIOA_SW_MASK      0x0Fu
#define GPIOA_AN_MASK      0xF0u
#define FND_DOT_DIGIT      1u

static const u8 g_hex_to_seg[16] = {
    0xC0u, 0xF9u, 0xA4u, 0xB0u,
    0x99u, 0x92u, 0x82u, 0xF8u,
    0x80u, 0x90u, 0x88u, 0x83u,
    0xC6u, 0xA1u, 0x86u, 0x8Eu
};

static void gpio_write(u32 base, u32 offset, u8 value)
{
    Xil_Out32(base + offset, (u32)value);
}

static u8 gpio_read(u32 base, u32 offset)
{
    return (u8)(Xil_In32(base + offset) & 0xFFu);
}

void board_io_init(void)
{
    gpio_write(HAL_GPIOA_BASEADDR, GPIO_CR_OFFSET, 0xF0u);
    gpio_write(HAL_GPIOA_BASEADDR, GPIO_ODR_OFFSET, GPIOA_AN_MASK);

    gpio_write(HAL_GPIOB_BASEADDR, GPIO_CR_OFFSET, 0xFFu);
    gpio_write(HAL_GPIOB_BASEADDR, GPIO_ODR_OFFSET, 0x00u);

    gpio_write(HAL_GPIOC_BASEADDR, GPIO_CR_OFFSET, 0xFFu);
    gpio_write(HAL_GPIOC_BASEADDR, GPIO_ODR_OFFSET, 0xFFu);
}

u8 board_io_read_switches(void)
{
    return gpio_read(HAL_GPIOA_BASEADDR, GPIO_IDR_OFFSET) & GPIOA_SW_MASK;
}

void board_io_set_leds(u8 value)
{
    gpio_write(HAL_GPIOB_BASEADDR, GPIO_ODR_OFFSET, value);
}

void board_io_blank_fnd(void)
{
    gpio_write(HAL_GPIOA_BASEADDR, GPIO_ODR_OFFSET, GPIOA_AN_MASK);
    gpio_write(HAL_GPIOC_BASEADDR, GPIO_ODR_OFFSET, 0xFFu);
}

void board_io_refresh_fnd_hex(u16 value, u8 dot_visible)
{
    static u8 digit;
    u8 nibble;
    u8 anode;
    u8 segment;

    digit &= 0x03u;
    nibble = (u8)((value >> ((3u - digit) * 4u)) & 0x0Fu);
    anode = (u8)(GPIOA_AN_MASK & (u8)~(1u << (4u + digit)));
    segment = g_hex_to_seg[nibble];

    if ((digit == FND_DOT_DIGIT) && dot_visible) {
        segment &= 0x7Fu;
    }

    gpio_write(HAL_GPIOC_BASEADDR, GPIO_ODR_OFFSET, segment);
    gpio_write(HAL_GPIOA_BASEADDR, GPIO_ODR_OFFSET, anode);
    digit = (u8)((digit + 1u) & 0x03u);
}

void board_io_delay_cycles(u32 cycles)
{
    volatile u32 i;

    for (i = 0u; i < cycles; ++i) {
        ;
    }
}
