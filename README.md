# TEC-1G TMS9918 Demo

A colour graphics and music demo for a Z80 machine with a TMS9918 video chip, such as the TEC-1G with a TMS9918 board. Plasma, sprites, rainbow bars and a giant "TEC-1G ★" scroller, with the "Music Banger" bytebeat playing throughout.

| File | What it is |
|---|---|
| `tec1g_demo.hex` | Ready-to-load Intel HEX, 8,192 bytes at 8000h–9FFFh |
| `tec1g_demo.asm` | Full Z80 source (self-contained, all tables inlined) |

All HEX checksums were checked by reading the file back. The source assembles with [sjasmplus](https://github.com/z00m128/sjasmplus) to the same bytes as the HEX file.

## Hardware requirements

- **CPU:** Z80. Timing was designed and tested for about 3.58–4 MHz.
- **Video:** TMS9918 / TMS9918A with 16 KB of video RAM.
  - Data port: `BEh`
  - Control (register/address) port: `BFh`
- **RAM:** 8000h–BFFFh must be RAM. Working variables go just after the code, and the stack starts at C000h and grows down.
- **Sound:** a speaker on **bit 7 of port `01h`**. On the TEC-1G this is the DSCAN display latch. Only the values 00h and 80h are ever written, so the 7-segment display stays blank. To use a different port, change `SPK EQU $01` in the source.
- **Interrupts:** none are used. The program runs with interrupts disabled (`DI`) and waits for each frame by reading the VDP status register.

## Loading and running

1. Load `tec1g_demo.hex` into memory with your monitor or loader. Every record is a type-00 data record ending with a type-01 EOF record. There is no type-03 start-address record, because some monitors reject it.
2. Start execution at **8000h**.
3. The demo runs until you reset the machine.

## What's on screen

The screen is in Graphics II mode, 256×192 pixels.

- **Plasma:** top two-thirds of the screen, 256 shades (32 colour pairs × 8 dither levels). Wobbles, with cycling colours.
- **Sprite chain:** T-E-C---1-G-★ twice (14 sprites of 16×16), snaking along a Lissajous path over the plasma. The letters cycle through the rainbow and the stars twinkle yellow and white.
- **Orbiting stars:** 2 stars circling the plasma on opposite sides.
- **Copper bars:** two animated rainbow bars framing the bottom area.
- **Big scroller:** "TEC-1G ★" in large LED dots (each font pixel is a 4×4 dot) across the bottom six rows, with rainbow colours moving up through the letters.
- **Scenes:** 4, each lasting 512 frames (about 25 seconds). Each has its own plasma shape, colour set, sprite path and scroller wave:
  1. Gentle wave
  2. Tight ripple
  3. Whole word bouncing
  4. Slow reverse swell
- **Speed:** about 20 fps. The music takes about a quarter of the CPU.

## About the music

The music is the "Music Banger" bytebeat by Anonymous. The original is a tight loop that needs the whole CPU, so it can't run alongside the graphics as written. This demo reworks it as follows:

- **One-step formula:** the routine's shifting works out to a simple formula, computed once per sample:

  ```
  out = ((rlc(D, C) | E) * 10) AND 80h
  ```

  `DE` is a 16-bit sample counter. `C` is the section number (1–5), which advances each time `DE` wraps. `rlc(D, C)` means D rotated left C times.
- **Spare registers:** the music state lives in the Z80's alternate registers (`BC'`, `DE'`, `HL'`, with `AF'` as a save slot). One sample takes 60 T-states and doesn't disturb the graphics code.
- **Spread through the loops:** a sample macro (`SMP`) is placed through every demo loop, including the vblank wait, so a sample goes out about every 240 T-states. That is the same rate as the original loop, so pitch and tempo match.

Checked in an emulator:
- The speaker output matches the original Banger code **bit for bit** over 518,522 samples, covering all five sections and the wrap back to the start.
- The average gap between samples is about 240 T-states, the same as the original. Most gaps land within 220–259 T-states. The rest are mainly once per frame, at hand-overs between effects.

## Timing notes

- **Video writes:** every write to video memory is at least 29 T-states after the previous one. That is safe during active display at 3.58 MHz, and the emulator logged zero timing violations. On a faster CPU, add wait states or more padding.
- **Sprite limit:** the TMS9918 shows at most 4 sprites per scanline. Where more line up, the demo rotates sprite priority each frame so the extras flicker rather than vanish. With 14 sprites in the chain this happens fairly often. Real hardware does the same.

## Building from source

```
sjasmplus tec1g_demo.asm
```

This writes `tec1g.bin`, the raw binary for loading at 8000h. To make an Intel HEX file from it, use any bin-to-hex tool with a load address of 8000h, for example:

```
srec_cat tec1g.bin -binary -offset 0x8000 -o tec1g.hex -intel
```

## Credits

- **Music:** "Music Banger" by Anonymous.
- **Graphics code and music integration:** written with Claude.
