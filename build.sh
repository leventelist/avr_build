#!/bin/bash

# The original script was written by Zak Kemble. Here is the original preamble

# Project: avr-gcc-build
# Author: Zak Kemble
# Copyright: (C) 2023 by Zak Kemble
# Web: https://blog.zakkemble.net/avr-gcc-builds/

# License:
# Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)
# http://creativecommons.org/licenses/by-sa/4.0/


# http://www.nongnu.org/avr-libc/user-manual/install_tools.html

# VM with 4x AMD Ryzen 5 5600X cores & 5.5GB RAM
# Debian 11 & GCC 10.2.1
# AVR-GCC 12.1.0 compile time: Around 1 hour for all 3 hosts

# For optimum compile time this should generally be set to the number of CPU cores your machine has.
# Some systems with not much RAM may fail with "collect2: fatal error: ld terminated with signal 9 [Killed]", if this happens try reducing the JOBCOUNT value or add more RAM.
# In my case using GCC 8.3.0 on Debian 10 with 2GB RAM is fine, but Debian 11 and GCC 10.2.1 needs 5.5GB

# The script was heavily midified by Levente Kovacs. My goal was to build a toolchain that has support for
# the new AVR-Dx CPUs.
#
# Removed feature:
#   - Non-Linux builds
#   - tarball downloads
#
# Added feature
#   - Git download
#   - Process priority (nice) settings
#   - Use all CPU cores you have
#   - Tar archive
#
# I use this to compile the following components:
#
# GCC 14
# binutils
# gdb
# avr-libc 2.2 (develop version)
# AVRDUDE 7.3

JOBCOUNT=${JOBCOUNT:-$(getconf _NPROCESSORS_ONLN)}

# Use the lowest priority. With this selected, you can enjoy your fast computer while it builds.
NICE=19

# Build Binutils
BUILD_BINUTILS=${BUILD_BINUTILS:-1}

# Build GDB
BUILD_GDB=${BUILD_GDB:-1}

# Build GCC (requires AVR-Binutils)
BUILD_GCC=${BUILD_GCC:-1}

# Build AVR-LibC (requires AVR-GCC)
BUILD_LIBC=${BUILD_LIBC:-1}

# Build AVRDUDE
BUILD_AVRDUDE=${BUILD_AVRDUDE:-1}

NAME_BINUTILS_GDB="git://sourceware.org/git/binutils-gdb.git"
COMMIT_BINUTILS="binutils-2_43_1"
COMMIT_GDB="gdb-15.1-release"

NAME_GCC="git://gcc.gnu.org/git/gcc.git"
COMMIT_GCC="releases/gcc-14.2.0"

NAME_LIBC="https://github.com/avrdudes/avr-libc.git"
COMMIT_LIBC="avr-libc-2_2_1-release"

NAME_AVRDUDE="https://github.com/avrdudes/avrdude.git"
COMMIT_AVRDUDE="v8.0"
PATCH_D_AVRDUDE="avrdude_patches"

HERE=`pwd`
DIR=""

LOG_DIR=$HERE
LOGFILE=$LOG_DIR/avr-toolchain-build.log

# Output locations for built toolchains
PREFIX=$HERE/out

# Configuration options for parts
OPTS_BINUTILS="
	--target=avr
	--disable-nls
	--disable-werror
	--with-static-standard-libraries
	--disable-gdb
"

# Configuration options for parts
OPTS_GDB="
	--target=avr
	--disable-nls
	--disable-werror
	--with-static-standard-libraries
	--disable-binutils
	--disable-gas
	--disable-ld
	--disable-gprof
	--disable-gprofng
"

OPTS_GCC="
	--target=avr
	--enable-languages=c,c++
	--disable-nls
	--disable-libssp
	--disable-libada
	--with-dwarf2
	--disable-shared
	--enable-static
	--enable-mingw-wildcard
	--enable-plugin
	--with-gnu-as
"

OPTS_LIBC="--host=avr"

OPTS_AVRDUDE="-DPYTHON_SITE_PACKAGES=python"

# Parse command line options
OPTIONS="k"
LONGOPTS="keep"

# Parsing command line arguments
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")

eval set -- "$PARSED"

KEEP=0

# Define usage function
usage() {
    echo "Usage: $0 -k"
    exit 1
}

# Loop through parsed options and arguments
while true; do
    case "$1" in
        -k|--keep)
            KEEP=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            usage
            ;;
    esac
done

# Stop on errors
set -e

PATH="$PREFIX"/bin:"$PATH"
export PATH

CC=""
export CC


TIME_START=$(date +%s)

log()
{
	echo -e "$1"
	echo "[$(date +"%d %b %y %H:%M:%S")]: $1" >> $LOGFILE
}

makeDir()
{
	if [ $KEEP -eq 0 ]; then
		rm -rf "$1/"
	fi
	mkdir -p "$1"
}

get_source()
{
	NAME=$1
	COMMIT=$2

	log "Getting $NAME $COMMIT"

	DIR_NAME=$(basename "$NAME" .git)

	if [ -d "$DIR_NAME" ]; then
		cd $DIR_NAME
		log "Dir existed. Doing only an update."
		git fetch
		cd ..
	else
		git clone $NAME
	fi

	cd $DIR_NAME
	git checkout $COMMIT
	if [ $KEEP -eq 0 ]; then
		git reset --hard
		git clean -xffd
		git clean -Xffd
	fi
	cd ..
	DIR="$DIR_NAME"

	return 0
}

confMake()
{
	../configure --prefix=$1 $2 $3 --build=`../config.guess`
	log "Compiling..."
	nice -n ${NICE} make -j $JOBCOUNT
	log "Installing..."
	make install-strip
	if [ $KEEP -eq 0 ]; then
		rm -rf *
	fi
}

confCmake()
{
	cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=$1 $2 $3
	log "Compiling..."
	nice -n ${NICE} make -j $JOBCOUNT
	make install
	if [ $KEEP -eq 0 ]; then
		rm -rf *
	fi
}

apply_patches()
{
	log "Applying patches..."
	for PATCH in ../$1/*; do
		echo $PATCH
		git apply $PATCH
	done
}


#Main program starts here

rm -f $LOGFILE
log "Start"
log "Creating output directory..."
makeDir "$PREFIX"

# Make AVR-Binutils
if [ $BUILD_BINUTILS -eq 1 ]; then
	log "***Binutils***"
	get_source $NAME_BINUTILS_GDB $COMMIT_BINUTILS
	cd $DIR
	mkdir -p obj-avr
	cd obj-avr
	confMake "$PREFIX" "$OPTS_BINUTILS"
	cd $HERE
else
	log "Skipping Binutils..."
fi

# Make AVR-GDB
if [ $BUILD_GDB -eq 1 ]; then
	log "***GDB***"
	get_source $NAME_BINUTILS_GDB $COMMIT_GDB
	cd $DIR
	mkdir -p gdb-obj-avr
	cd gdb-obj-avr
	confMake "$PREFIX" "$OPTS_GDB"
	cd $HERE
else
	log "Skipping GDB..."
fi

# Make AVR-GCC
if [ $BUILD_GCC -eq 1 ]; then
	log "***GCC***"
	get_source $NAME_GCC $COMMIT_GCC
	cd $DIR
	mkdir -p obj-avr
	cd obj-avr
	confMake "$PREFIX" "$OPTS_GCC"
	cd $HERE
else
	log "Skipping GCC..."
fi

# Make AVR-LibC
if [ $BUILD_LIBC -eq 1 ]; then
	log "***AVR-LibC***"
	get_source $NAME_LIBC $COMMIT_LIBC
	cd $DIR
	./bootstrap
	mkdir -p obj-avr
	cd obj-avr
	confMake "$PREFIX" "$OPTS_LIBC"
	cd $HERE
else
	log "Skipping AVR-LibC..."
fi

# Make AVRDUDE
if [ $BUILD_AVRDUDE -eq 1 ]; then
	log "***AVRDUDE***"
	get_source $NAME_AVRDUDE $COMMIT_AVRDUDE
	cd $DIR
	apply_patches $PATCH_D_AVRDUDE
	mkdir -p obj-avr
	cd obj-avr
	confCmake "$PREFIX" "$OPTS_AVRDUDE"
	cd $HERE
else
	log "Skipping AVRDUDE..."
fi

TIME_END=$(date +%s)
TIME_RUN=$(($TIME_END - $TIME_START))

log "***Creating archive***"
rm -f *.tar.bz2
tar -cjf avr-GNU-toolchain.tar.bz2 --transform 's,^,avr-GNU-toolchain/,' -C $PREFIX .

echo ""
log "Done in $TIME_RUN seconds"
log "Toolchains are in $PREFIX"

exit 0
