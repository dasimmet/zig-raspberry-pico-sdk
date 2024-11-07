# raspberry pico-sdk on the zig buildsystem

## Picotool

```console
foo@bar:~$ zig version
0.14.0-dev.2164+6b2c8fc68
foo@bar:~$ zig build run
PICOTOOL:
    Tool for interacting with an RP2040/RP2350 binary

SYNOPSIS:
    picotool info [-b] [-p] [-d] [--debug] [-l] [-a] <filename> [-t <type>]
    picotool config [-s <key> <value>] [-g <group>] <filename> [-t <type>]
    picotool link [--quiet] [--verbose] <outfile> [-t <type>] <infile1> [-t <type>] <infile2> [-t <type>] [<infile3>] [-t <type>] [-p] <pad>
    picotool otp list
    picotool partition create
    picotool uf2 convert
    picotool version [-s] [<version>]
    picotool coprodis [--quiet] [--verbose] <infile> [-t <type>] <outfile> [-t <type>]
    picotool help [<cmd>]

COMMANDS:
    info        Display information from the target device(s) or file.
                Without any arguments, this will display basic information for all connected RP2040 devices in BOOTSEL mode
    config      Display or change program configuration settings from the target device(s) or file.
    link        Link multiple binaries into one block loop.
    otp         Commands related to the RP2350 OTP (One-Time-Programmable) Memory
    partition   Commands related to RP2350 Partition Tables
    uf2         Commands related to UF2 creation and status
    version     Display picotool version
    coprodis    Post-process coprocessor instructions in disassembly files.
    help        Show general help or help for a specific command

Use "picotool help <cmd>" for more info
```