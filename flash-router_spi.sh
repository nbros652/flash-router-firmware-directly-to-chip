#!/bin/bash

if [ "$(whoami)" != "root" ]; then
    sudo bash $0 $@
    exit
fi

status() {
	# write status text to console
	echo "$@" >&2
}

clear

# import code to handle argument parsing
[ ! -e argParser.sh ] && status -e "Oops, you need to copy the argParser.sh script into the same directory as this\nscript." && exit
source argParser.sh
# switch definitions
firmwareSwitches="-f --firmware"
offsetSwitches="-o --offset"
programmerSwitches="-p --programmer"

# set some variables used by the script; don't change these
stockFlash="stock.bin"
customFlash="cstm.bin"

# parse args
argFirmware="$(argParser.getArg $firmwareSwitches)"
argOffset="$(argParser.getArg $offsetSwitches)"
argProgrammer="$(argParser.getArg $programmerSwitches)"

# configure programmer
if [ ! -z "$argProgrammer" ]; then
	programmer=$argProgrammer
else
	status "No programmer specified; assuming ch341a_spi."
	status "Use -p PROGRAMMER or --programmer PROGRAMMER to specify something different" 
	programmer=ch341a_spi
fi

missingArgs=0
# configure firmware
if [ ! -z "$argFirmware" ]; then
	customFirmware="$argFirmware"
else
	status "Please specify a firmware image with -f FILENAME or --firmware FILENAME"
	missingArgs=1
fi

# configure offset
if [ ! -z "$argOffset" ]; then
	firmwareOffset=$argOffset
else
	status "Please specify the offset of firmware in flash with -o OFFSET or --offset OFFSET"
	status "If flashing a TL-WR703N, the firmware offset is 131072 (0x20000)"
	missingArgs=1
fi

# quit if we're missing args
[ $missingArgs -ne 0 ] && status "Please add the missing arguments and try again." && exit

echo
# delete any old firmware
if [ -e "$stockFlash" ]; then
    status "Flash dump found from previous session"
    read -p "Do you want to delete it? [Y/n]: " opt
    [ "${opt,,}" != "n" ] && rm "$stockFlash" "$customFlash"
fi

clear
# specify what actions will be attempted based on user input
status "Operation Pending: write $customFirmware to router flash at $firmwareOffset using $programmer"

checkClip() {
	echo
	status "Checking for proper seating of clip on chip"
	while flashrom -p $programmer | grep -q "No EEPROM/flash device found." || ! flashrom -p $programmer > /dev/null 2>&1
	do
	    read -sp "Clip is not seated correctly; re-seat and press [Enter]."
	    echo
	done
	status "Clip is seated properly. Don't move anything!"
}
checkClip

# start a loop dumping firmware until we have a verified dump
while :
do
    echo
    status "Dumping current contents of flash chip"
    flashrom -p $programmer -r "$stockFlash"

    echo
    status "Verifying dumped contents"
    flashrom -p $programmer -v "$stockFlash" && success=1 || success=0
    [ $success -eq 1 ] && break
    status "Bad dump; trying again"
done

echo
status "Injecting custom firmware into flash binary"
# make a copy of the dumped flash contents
cp "$stockFlash" "$customFlash"
# inject firmware at $firwareOffset bytes into flash binary
dd if="$customFirmware" of="$customFlash" bs=$firmwareOffset seek=1 conv=notrunc > /dev/null 2>&1

echo
status "Writing custom flash binary to router"
flashrom -p $programmer -w "$customFlash"

# guide user on steps to take after flashing
echo
status -e "Don't close this window! Check your router to make sure everything works with\nthe new firmware! If it doesn't, reflash the original dump."
read -p "Should I reflash the original dump? [y/N]: " opt
if [ "${opt,,}" == "y" ]; then
	echo
	status "Reverting flash contents"
	checkClip
	flashrom -p $programmer -w "$stockFlash"
else
	echo
	status -e "Now disconnect the clip, power up the router, and perform a router reset\nimmediately!"
fi
