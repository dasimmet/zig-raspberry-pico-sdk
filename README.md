# raspberry Picotool on the zig buildsystem

## Requirements

- zig 0.16.0

## Picotool

this repo builds the raspberry picotool from the sdk source on the zig buildsystem:

```console
foo@bar:~$ zig build run
PICOTOOL:
    Tool for interacting with RP-series device(s) in BOOTSEL mode, or with an RP-series binary

SYNOPSIS:
    picotool help [<cmd>]
    picotool version [-s] [<version>]
    picotool info [-b] [-m] [-p] [-d] [--debug] [-l] [-a] [device-selection]
    picotool info [-b] [-m] [-p] [-d] [--debug] [-l] [-a] <filename> [-t <type>]
    picotool config [-s <key> <value>] [-g <group>] [device-selection]
    picotool config [-s <key> <value>] [-g <group>] <filename> [-t <type>]
    picotool load [--ignore-partitions] [--family <family_id>] [-p <partition>] [-n] [-N] [-u] [-v] [-x] <filename> [-t <type>] [-o <offset>] [device-selection]
    picotool save [-p] [-v] [--family <family_id>] <filename> [-t <type>] [device-selection]
    picotool save -a [-v] [--family <family_id>] <filename> [-t <type>] [device-selection]
    picotool save -r <from> <to> [-v] [--family <family_id>] <filename> [-t <type>] [device-selection]
    picotool verify <filename> [-t <type>] [device-selection] [-r <from> <to>] [-o <offset>] [device-selection]
    picotool erase [-a] [device-selection]
    picotool erase -p <partition> [device-selection]
    picotool erase -r <from> <to> [device-selection]
    picotool reboot [-a] [-u] [-g <partition>] [-c <cpu>] [device-selection]
    picotool partition info|create
    picotool uf2 convert|combine|info
    picotool otp get|set|load|white-label|permissions|dump|list
    picotool coprodis [--quiet] [--verbose] <infile> <outfile>
    picotool link [--quiet] [--verbose] <outfile> [-t <type>] <infile1> [-t <type>] <infile2> [-t <type>] [<infile3>] [-t <type>] [-p <pad>]
    picotool bdev ls|mkdir|cp|rm|cat|format

COMMANDS:
    help        Show general help or help for a specific command
    version     Display picotool version
    info        Display information from the target device(s) or file.
                Without any arguments, this will display basic information for all connected RP-series devices in BOOTSEL mode
    config      Display or change program configuration settings from the target device(s) or file.
    load        Load the program / memory range stored in a file onto the device.
    save        Save the program / memory stored in flash on the device to a file.
    verify      Check that the device contents match those in the file.
    erase       Erase the program / memory stored in flash on the device.
    reboot      Reboot the device
    partition   Commands related to RP2350 Partition Tables
    uf2         Commands related to UF2 creation and status
    otp         Commands related to the RP2350 OTP (One-Time-Programmable) Memory
    coprodis    Post-process coprocessor instructions in disassembly files.
    link        Link multiple binaries into one block loop.
    bdev        Commands related to embedded block devices

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
