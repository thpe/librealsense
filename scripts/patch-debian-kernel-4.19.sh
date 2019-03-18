#!/bin/bash

#Break execution on any error received
set -e

#trap read debug

echo -e "\e[36mDevelopment script for kernel 4.19 with metadata node\e[0m"

#Locally suppress stderr to avoid raising not relevant messages
exec 3>&2
exec 2> /dev/null
con_dev=$(ls /dev/video* | wc -l)
exec 2>&3

if [ $con_dev -ne 0 ];
then
	echo -e "\e[32m"
	read -p "Remove all RealSense cameras attached. Hit any key when ready"
	echo -e "\e[0m"
fi

#Include usability functions
source ./scripts/patch-utils.sh

# Get the required tools and headers to build the kernel
sudo apt-get install build-essential git
#Packages to build the patched modules / kernel 4.16
require_package libusb-1.0-0-dev
require_package libssl-dev
require_package bison
require_package flex
require_package libelf-dev


LINUX_BRANCH=$(uname -r)

codename=`lsb_release -s -c`

minor=$(uname -r | cut -d '.' -f 2)
if [ $minor -ne 19 ];
then
	echo -e "\e[43mThe patch is applicable for kernel version 4.19."
	exit 1
fi

kernel_branch=$(uname -r | awk -F '[.-]' '{print "v"$1"."$2"."$3}')
kernel_major_minor=$(uname -r | awk -F '[.-]' '{print "v"$1"."$2}')
kernel_name="linux-4.19.16"
kernel_pkg="linux-image-4.19.0-0.bpo.2-amd64-unsigned"


# install source
sudo apt build-dep $kernel_pkg
apt source $kernel_pkg


cd ${kernel_name}


#Check if we need to apply patches or get reload stock drivers (Developers' option)
[ "$#" -ne 0 -a "$1" == "reset" ] && reset_driver=1 || reset_driver=0

if [ $reset_driver -eq 1 ];
then
	echo -e "\e[43mUser requested to rebuild and reinstall ubuntu-${ubuntu_codename} stock drivers\e[0m"
else
	# Patching kernel for RealSense devices
	echo -e "\e[32mApplying realsense-uvc patch\e[0m"
	patch -p1 < ../scripts/realsense-camera-formats_debian-${codename}-${kernel_major_minor}.patch
	echo -e "\e[32mApplying realsense-metadata patch\e[0m"
	patch -p1 < ../scripts/realsense-metadata-debian-${codename}-${kernel_major_minor}.patch
	echo -e "\e[32mApplying realsense-hid patch\e[0m"
	patch -p1 < ../scripts/realsense-hid-debian-${codename}-${kernel_major_minor}.patch
	echo -e "\e[32mApplying realsense-powerlinefrequency-fix patch\e[0m"
	patch -p1 < ../scripts/realsense-powerlinefrequency-control-fix.patch
	#echo -e "\e[32mApplying kernel debug patches\e[0m"
	#patch -p1 < ../scripts/0001-Kernel-debugs.patch
fi

# Copy configuration
cp /usr/src/linux-headers-$(uname -r)/.config .
cp /usr/src/linux-headers-$(uname -r)/Module.symvers .

# Basic build for kernel modules
echo -e "\e[32mPrepare kernel modules configuration\e[0m"
make silentoldconfig modules_prepare

# Build the uvc, accel and gyro modules
KBASE=`pwd`
cd drivers/media/usb/uvc
cp $KBASE/Module.symvers .

echo -e "\e[32mCompiling uvc module\e[0m"
make -j -C $KBASE M=$KBASE/drivers/media/usb/uvc/ modules
#echo -e "\e[32mCompiling accelerometer and gyro modules\e[0m"
make -j -C $KBASE M=$KBASE/drivers/iio/accel modules
make -j -C $KBASE M=$KBASE/drivers/iio/gyro modules
echo -e "\e[32mCompiling v4l2-core modules\e[0m"
make -j -C $KBASE M=$KBASE/drivers/media/v4l2-core modules

# Copy the patched modules to a sane location
cp $KBASE/drivers/media/usb/uvc/uvcvideo.ko ~/$LINUX_BRANCH-uvcvideo.ko
cp $KBASE/drivers/iio/accel/hid-sensor-accel-3d.ko ~/$LINUX_BRANCH-hid-sensor-accel-3d.ko
cp $KBASE/drivers/iio/gyro/hid-sensor-gyro-3d.ko ~/$LINUX_BRANCH-hid-sensor-gyro-3d.ko
cp $KBASE/drivers/media/v4l2-core/videodev.ko ~/$LINUX_BRANCH-videodev.ko

echo -e "\e[32mPatched kernels modules were created successfully\n\e[0m"

# Load the newly-built modules
try_module_insert videodev				~/$LINUX_BRANCH-videodev.ko 			/lib/modules/`uname -r`/kernel/drivers/media/v4l2-core/videodev.ko
try_module_insert uvcvideo				~/$LINUX_BRANCH-uvcvideo.ko 			/lib/modules/`uname -r`/kernel/drivers/media/usb/uvc/uvcvideo.ko
try_module_insert hid_sensor_accel_3d 	~/$LINUX_BRANCH-hid-sensor-accel-3d.ko 	/lib/modules/`uname -r`/kernel/drivers/iio/accel/hid-sensor-accel-3d.ko
try_module_insert hid_sensor_gyro_3d	~/$LINUX_BRANCH-hid-sensor-gyro-3d.ko 	/lib/modules/`uname -r`/kernel/drivers/iio/gyro/hid-sensor-gyro-3d.ko

echo -e "\e[92m\n\e[1mScript has completed. Please consult the installation guide for further instruction.\n\e[0m"
