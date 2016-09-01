## Simple timer with a PIC microcontroller

This is a simple timer implemented with a PIC 18F25K50 microcontroller
in assembly with the following features:

 * 16bit timer with second resolution
 * timeout and countdown shown in a 7seg display (I2C)
 * 5 buttons debounced and with automatic repetition
 * 10 presets saved in the EEPROM of the microcontroller
 * 2 open drain outputs for the relays
 * ICSP connector compatible with PICkit
 * A buzzer to signal the end of the countdown driven in PWM

## Motivation

Made to control a home made UV exposure unit.

## Disclaimer

May contain unintended bugs.
