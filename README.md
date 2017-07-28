# Wirekite for MacOS

Wire up digital and analog IOs to your Mac and control them with your Swift or Objective-C code run on your Mac.

To connect the inputs and outputs, use a [Teensy development board](https://www.pjrc.com/teensy/) connected via USB. It looks a lot like an Arduino Nano connected for loading the code. Yet with Wirekite the custom code is written for and run on your computer – not for the microcontroller.

This repository contains the MacOs code. There are separate repositories for the [Teensy code](https://github.com/manuelbl/Wirekite) and the Windows code (coming soon).

## Supported boards

- [Teensy LC](https://www.pjrc.com/store/teensylc.html)
- [Teensy 3.2](https://www.pjrc.com/store/teensy32.html) (soon)

## Supported inputs / outputs / protocols

- Digital output
- Digital input
- Analog input
- PWM output
- I2C (soon)


# Get started

1. Prepare the Teensy board for Wirekite

Download the ready-to-use code for the Teensy and install it on your Teensy board. This is a one-time step.

[See instructions](https://github.com/manuelbl/Wirekite/blob/master/docs/prepare_teensy.md)

2. Setup an Xcode projects

Instructions to follow soon...
