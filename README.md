# raspberry pico-sdk on the zig buildsystem

## Requirements

- zig 0.13.0 or higher
- ~~libudev-dev for libusb on linux~~

The last zig version i built against (ubuntu linux 24.04 x86_64):

```console
foo@bar:~$ zig version
0.14.0-dev.2164+6b2c8fc68
```

## Picotool

this repo builds the raspberry picotool from the sdk source on the zig buildsystem:

```console
foo@bar:~$ zig build run
PICOTOOL:
    Tool for interacting with RP2040/RP2350 device(s) in BOOTSEL mode, or with an RP2040/RP2350 binary

SYNOPSIS:
    picotool info [-b] [-p] [-d] [--debug] [-l] [-a] [device-selection]
    picotool info [-b] [-p] [-d] [--debug] [-l] [-a] <filename> [-t <type>]
    picotool config [-s <key> <value>] [-g <group>] [device-selection]
    picotool config [-s <key> <value>] [-g <group>] <filename> [-t <type>]
    picotool load [--ignore-partitions] [--family <family_id>] [-p <partition>] [-n] [-N] [-u] [-v] [-x] <filename> [-t <type>] [-o <offset>]
                [device-selection]
    picotool link [--quiet] [--verbose] <outfile> [-t <type>] <infile1> [-t <type>] <infile2> [-t <type>] [<infile3>] [-t <type>] [-p] <pad>
    picotool save [-p] [device-selection]
    picotool save -a [device-selection]
    picotool save -r <from> <to> [device-selection]
    picotool verify [device-selection]
    picotool reboot [-a] [-u] [-g <partition>] [-c <cpu>] [device-selection]
    picotool otp list|get|set|load|dump|permissions|white-label
    picotool partition info|create
    picotool uf2 info|convert
    picotool version [-s] [<version>]
    picotool coprodis [--quiet] [--verbose] <infile> [-t <type>] <outfile> [-t <type>]
    picotool help [<cmd>]

COMMANDS:
    info        Display information from the target device(s) or file.
                Without any arguments, this will display basic information for all connected RP2040 devices in BOOTSEL mode
    config      Display or change program configuration settings from the target device(s) or file.
    load        Load the program / memory range stored in a file onto the device.
    link        Link multiple binaries into one block loop.
    save        Save the program / memory stored in flash on the device to a file.
    verify      Check that the device contents match those in the file.
    reboot      Reboot the device
    otp         Commands related to the RP2350 OTP (One-Time-Programmable) Memory
    partition   Commands related to RP2350 Partition Tables
    uf2         Commands related to UF2 creation and status
    version     Display picotool version
    coprodis    Post-process coprocessor instructions in disassembly files.
    help        Show general help or help for a specific command

Use "picotool help <cmd>" for more info
```

## Picotool zig build interface

```zig
// build.zig
const pico_sdk = @import("zig-raspberry-pico-sdk");
const load_step = pico_sdk.load(b, .{
    .firmware = lazypath_to_firmware_uf2,
    .execute = true,
    .sudo = b.option(bool, "load-with-sudo", "run picotool load with sudo") orelse false,
}, .{});
b.step("load").dependOn(load_step);
```
