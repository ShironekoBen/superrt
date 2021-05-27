# SuperRT

![SuperRT example image](https://user-images.githubusercontent.com/47202645/119617918-454eb280-be3d-11eb-8174-f500db98cdda.jpg)

This is an experimental expansion chip for the Super Nintendo that adds real-time ray-tracing support to the console. You can find some more details in text form on my [website](https://www.shironekolabs.com/posts/superrt/) and in this [overview video](https://www.youtube.com/watch?v=2jee4tlakqo).

This repository contains all of the source code for the chip and supporting tools. It's very much a "proof-of-concept" level implementation, lacking many features that would be desirable for any practical application beyond simple demos!
It's also "my first Verilog project", so the quality of the code is fairly suspect in places - please don't assume that anything I've done here represents any kind of best-practice (or is even a good idea...).

If you're looking to get this working then there are a number of steps involved, not least of which is building the necessary hardware.

## Hardware

The system uses a DE10-Nano board with a Cyclone-V FPGA interfaced to the SNES cartridge bus via two `74ALVC164245` level shifter ICs connected to the FPGA's GPIO pins. The wiring details look like this:

### GPIO pins

Pins here are given in the logical direction of the data flow (i.e. A0 -> GP0 indicating that address data goes from the SNES to the SuperRT chip).

The level shifter chips is used are `SN74ALVC164245`s - two are required. Each chip has two banks (1 and 2), the direction of which can be independently configured. The SuperRT prototype uses them as follows:

```
LS1 bank 1: A -> B, enabled only when required by GP16 (data bus from DE10-Nano to SNES)
LS1 bank 2: B -> A, always on (address bus from SNES to DE10-Nano)
LS2 bank 1: B -> A, always on (address bus and control lines from SNES to DE10-Nano)
LS2 bank 2: B -> A, always on (address bus from SNES to DE10-Nano)
```

You may notice that the mapping to the level shifter channels is a little odd - this is partly because the prototype was built in stages, and partly because my surface-mount soldering skills are distinctly suboptimal, and in the process of mounting the level shifter chips onto breakout boards I ended up with a few dead channels!

This list is formatted as follows (arrows indicate data flow direction):

```
SNES	   Level shifter      DE10-Nano
A7      -> 2B1  :LS1: 2A1  -> GP7
|          |     |    |       |
|          |     |    |       \-- GPIO pin on DE10-Nano board
|          |     |    \-- Output pin on level shifter
|          |      \-- Level shifter chip number (LS1 or LS2)
|          \- Input pin on level shifter
\-- Pin on SNES cartridge ROM
```

#### Pin connections list

```
[Address bus]

SNES	   Level shifter      DE10-Nano

A0      -> 2B8  :LS1: 2A8  -> GP0
A1      -> 2B7  :LS1: 2A7  -> GP1
A2      -> 2B6  :LS1: 2A6  -> GP2
A3      -> 2B5  :LS1: 2A5  -> GP3
A4      -> 2B4  :LS1: 2A4  -> GP4
A5      -> 2B3  :LS1: 2A3  -> GP5
A6      -> 2B7  :LS2: 2A7  -> GP6
A7      -> 2B1  :LS1: 2A1  -> GP7
A8      -> 1B3  :LS1: 1A3  -> GP19
A9      -> 1B4  :LS2: 1A4  -> GP20
A10     -> 1B5  :LS2: 1A5  -> GP21
A11     -> 1B6  :LS2: 1A6  -> GP22
A12     -> 2B2  :LS2: 2A2  -> GP23
A13     -> 2B5  :LS2: 2A5  -> GP24
A14     -> 2B6  :LS2: 2A6  -> GP25
A15     -> 2B8  :LS2: 2A8  -> GP26

[Data bus]

DE10-NANO  Level shifter      SNES

GP8     -> 1A2  :LS1: 1B2  -> D0
GP9     -> 1A3  :LS1: 1B3  -> D1
GP10    -> 1A4  :LS1: 1B4  -> D2
GP11    -> 1A5  :LS1: 1B5  -> D3
GP12    -> 1A6  :LS1: 1B6  -> D4
GP13    -> 1A7  :LS1: 1B7  -> D5
GP14    -> 1A8  :LS1: 1B8  -> D6
GP15 -   > 1A1  :LS1: 1B1  -> D7

[ROM access control]

SNES	Level shifter         DE10-Nano

CS      -> 1B1  :LS2: 1A1  -> GP17
OE      -> 1B2  :LS2: 1A2  -> GP18

[Level shifter tranceiver control]

DE10-Nano  Level shifter

GP16    -> 1OE :LS1

[Level shifter tranceiver control (fixed)]

Source	   Level shifter

+3.3v   -> 1DIR:LA1
Gnd     -> 2DIR:LS1
Gnd     -> 2OE :LS1
Gnd     -> 1DIR:LS2
Gnd     -> 1OE :LS2
Gnd     -> 2DIR:LS2
Gnd     -> 2OE :LS2

[Debug (Megadrive pad, optional)]

(no level shifter required - Megadrive pads can be run at 3.3v)

Pad	  DE10-Nano

Pad up    -> GP27
Pad down  -> GP28
```

## Software/design synthesis

The chip design in written in Verilog, and can be compiled using Quartus Prime. The SNES-side software is in assembler, and can be compiled with the wla-65816 compiler.

These instructions assume you are running Windows, but I think all the requisite tools are available for Linux too so it probably wouldn't be hard to build under that as well.

### Required tools

* [wla-65816 compiler v9.2](https://wiki.superfamicom.org/uploads/wla-dx-9.2.7z) (place binaries in `SRT-SNES\Tools\WLA`)
* Make ([GNU make for Windows](http://gnuwin32.sourceforge.net/packages/make.htm) or similar), either on the path or in `SRT-SNES\Tools\Make\bin`
* [SRecord 1.64](http://srecord.sourceforge.net/download.html) placed in `SRT\Tools\srecord`
* [Quartus Prime 18.1](https://fpgasoftware.intel.com/18.1/?edition=standard) installed with Cyclone-V support
* [libSFX](https://github.com/Optiroc/libSFX/) - I used [this specific version](https://github.com/Optiroc/libSFX/tree/754993beb65540cae2c0f80f7debbb992a053e92) although I suspect that the latest version will work. This needs to be placed in `SRT-SNES\External\libSFX` and then patched as per the first step in the building instructions below.
* [SharpDX](https://github.com/sharpdx/SharpDX) for the testbed tool (this is configured as a NuGet package in the solution, so you shouldn't need to get it manually).
* [Visual Studio](https://visualstudio.microsoft.com/) 2017 or newer to build the testbed tool.

### Steps for building

1) Apply `libSFX SuperRT changes.patch` to the libsfx installation in `SRT-SNES\External\libSFX` - this changes a few things that SuperRT needs (mainly the memory map, disabling FastROM and taking control over INIDISP). Note that these changes are SuperRT-specific and this patched version of libSFX won't work for anything else.
2) Open the `SRTTestbed` solution file in Visual Studio (2017 or newer), restore NuGet packages, switch to release configuration and run.
3) Hit the `PAL Regen` button and wait for it to complete (warning: this will display flickering images on the output window as it executes).
4) Click `Write data` and then close the testbed.
5) Run `make` in `SRT-SNES`. This should generate an `SRTTest.sfc` file in `SRT-SNES/Binaries`.
6) Open the SRT folder, and run the `ConvertData.bat` batch file. This will generate `.mif` files for the various binaries involved.
7) Open the SRT project file in Quartus and hit `start compilation`.
8) Once compilation completes, launch the programmer and download `output_files/SRT.sof` to the Cyclone V on the DE10-Nano board.
9) Turn on the SNES and the SuperRT test/demo app should boot.

### Demo controls

You can navigate the scene with the D-pad and L/R (to strafe) and X/A to move up and down. Holding Y allows the light source to be moved with the D-Pad.
Start toggles the debug overlay display.

### Code notes

The `config.sv` file contains some defines that affect the synthesized design. Most notably, `ENABLE_EXECUTION_UNIT_1` and `ENABLE_EXECUTION_UNIT_2` enable the second and third execution cores respectively. These are on by default, but turning them off both improves synthesis time and to an extent timing stability, but with an obvious impact on speed (there are definitely some dubious things going on timing-wise in three core mode and making unrelated changes can sometimes cause visual noise).

> Timing in general are a bit all-over-the-place in this project. Some constraints are set and the newer code is generally (moderately) "timing clean", but some of the older components have a lot of black magic "here's a multi-cycle logic chain where I just tweaked things until I stopped getting visible errors" parts. I apologise deeply for anyone who has to modify those!

`config.sv` also includes the `ENABLE_DEBUG_DISPLAY` switch, which turns on debug output to an HDMI display. This is off by default partly because the design won't fit if it and all three execution cores are enabled, and also partly because it requires some I2C driver code from Terasic which is under a different license. If you want to enable it, you'll need to get `I2C_Controller.v`, `I2C_HDMI_Config.v` and `I2C_WRITE_WDATA.v` from the [VGAHDMI example](https://github.com/nhasbun/de10nano_vgaHdmi_chip) project or the original Terasic samples and add them to the project.

With `ENABLE_DEBUG_DISPLAY` enabled, `ENABLE_DEBUG_PIXEL` can be turned on to cause data from the pixel located at `DebugPixelLocation` (set in `RayEngine.sv`) to be piped to the debug interface.

`TINT_EXECUTION_UNITS` can also be used to tint emitted pixels according to which execution unit they were processed by.

Because of hardware limitations (namely the WR line not being available to the FPGA in my interface), writes from the SNES to SuperRT registers are emulated by performing reads from the 0xBF00 to 0xBFFF region instead.
The basic mechanic here is that reading a register in the 0xBE80 to 0xBEFF range sets the "last register" value `lastIOReg`, and then when read within the "proxied write range" (0xBF00 to 0xBFFF) happens the lowest 8 bits of the address read are written to that register (and `lastIOReg` is incremented).

For command list data writes, the auto-increment is turned off, and instead a dedicated command list address register (`CmdWriteAddr`) is used to denote the target address. There are eight command list write registers, `CmdWriteData1` to `CmdWriteData8`, which write different numbers of bits from the supplied byte - this mechanism helps the SNES CPU when writing packed variable-length data as it can avoid expensive bit shifting operations.

### Testbed controls

In the testbed the camera can be moved with WASD, and rotated with Q and E. R and F move vertically (if keyboard controls don't work, try clicking on the render view first).

Clicking a pixel will set it for debugging and show trace output from the execution of that pixel in the panel below.

The testbed monitors the scene source file for changes and will reload it when it sees one, so you can edit in a text editor and have the view update immediately.

The testbed has two execution modes that can be switched between with the `USE_EXEC_EMULATOR` define at the top of `RayEngine.cs`. "Emulator" mode (the default) uses a high-level emulation of the raytracing process that (in theory) produces the same results as the hardware but using a comparitively software-efficient algorithm. When the emulator define is disabled, a cycle-accurate implementation of the exact hardware behaviour is used instead, which is much closer to what the actual chip will do, but is also *much* slower.

The buttons at the bottom of the window are:

* `256 colour display` - reduces the displayed image to 256 colours. Note that by default the palette is only generated from the first rendered frame, so unless you press `Pal regen` first colours will likely be quite strange.
* `RGB555 display` - reduces the displayed image to 5 bits per channel (only effective if not in 256 colour mode).
* `Dither` - enables dithering.
* `Show branch prediction rate` - visualises the effective branch prediction rate (requires the `USE_EXEC_EMULATOR` define to be off).
* `Animate` - animate the scene in the viewport.
* `Visualise culling` - draw culling primitives as if they were solid, enabling them to be seen.
* `Pal regen` - walk (literally!) through the scene taking screenshots from multiple angles and then generate an optimised palette based on that. *Note that the render display will flash a lot whilst this is happening.*
* `Write data` - write the data files (compiled command list, palette, etc) for the SNES to use.

## License

See the LICENSE file for full details.

The SuperRT code is licensed under the MIT license.

The debug HDMI output functionality uses code derived from Nicolas Hasbun's excellent [vgaHDMI example](https://github.com/nhasbun/de10nano_vgaHdmi_chip), which is also MIT licensed.

> Note that whilst this repository contains (a modified version of) the core `vgaHdmi.sv` file from that project, it does *not* contain the I2C driver code for the HDMI subsystem used by vgaHDMI (`I2C_Controller.v`, `I2C_HDMI_Config.v` and `I2C_WRITE_WDATA.v`) as those are under a separate license from Terasic which appears to not allow redistribution. In the interests of keeping the licensing here simple (especially as by default those files are not required, and interested parties can obtain them easily enough elsewhere), I've opted to omit them.

_"SNES" and "Super Nintendo" are trademarks of Nintendo Co Ltd. This is a hobby project and completely unassociated with Nintendo._
