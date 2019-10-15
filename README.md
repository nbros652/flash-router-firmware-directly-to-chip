# flash-router-firmware-directly-to-chip
Flash a router with an SPI programmer

Getting Ready:
------------
 * Read this entire file before doing anything! You have been warned.
 * On a Linux system, install flashrom (Ubuntu: `sudo apt install flashrom`)
 * Copy both script files (argParser.sh and flash-router_spi.sh) into an empty folder, ensuring both are set executable.
 * Add a custom firmware to this same folder
 * Attach your flash programmer (script tested with a ch341a_spi) to your computer
 * Connect your SOIC8 SOP8 flash clip to the flash chip on your router
 * Search online to find out what the offset is of the firmware in flash memory for your router (the TL-WR703N, which this was used for, has an offset of 131072 (0x20000) bytes)

Performing the flash:
------------
Open a shell inside your folder and run  
`./flash-router_spi.sh -p YOUR-PROGRAMMER -f YOUR-FIRMWARE -o OFFSET-OF-FIRMWARE-IN-MEMORY`
If you don't specify the programmer, the script will assume you're using a ch341a_spi programmer. To get a list of all supported programmers, run `man flashrom`

The following are the available switches:
 * `-p PROGRAMMER` or `--programmer PROGRAMMER`        *(defaults to **ch341a_spi**)*
 * `-f FIRMWARE_FILE` or `--firmware FIRMWARE_FILE`    *(this is required)*
 * `-o OFFSET` or `--offset OFFSET`                    *(this is required)*

Once the script is running, follow the prompts. The first thing that will happen is that it will check to see if the clip is seated properly on the flash chip. It it is not, you'll be informed and asked to re-seat the clip and try again. This can be a frustrating process that takes a while. Once you get it seated properly, DON'T MOVE ANYTHING!

Next the script will dump the current flash contents, make a copy and inject the firmware at the offset you specified. It will then write the modified flash image back to the chip, verifying after the write is complete. You'll be prompted to check and see if the router boots. If it doesn't, you can write the dumped image back to the flash chip so that you don't leave your router bricked.

Finally, if everything went well, and your router boots just fine into the new firmware, you should perform a router reset to ensure that the left-over contents in nvram don't interfere with your new firmware settings.

Example Usage:
-----
This script was used to write custom firmware to a TL-WR703N. It was not tested with any other devices. USE AT YOUR OWN RISK! On the TL-WR703N firmware is located in flash at an offset of 131072 (0x20000) bytes. This is not likely to be true for other makes and models of routers!
Flashing an image named dd-wrt.bin to a TL-WR703N with a ch341a_spi programmer would be accomplished with the following command:  
`./flash-router_spi.sh -p ch341a_spi -f dd-wrt.bin -o 131072`  
or  
`./flash-router_spi.sh --programmer ch341a_spi --firmware dd-wrt.bin --offset $((0x20000))`

*Note that the use of $((0x20000)), the hexadecimal representation of the offset in memory, will not work in all shells. It will work in bash.*
