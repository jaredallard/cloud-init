# How to Use

## Raspberry Pi

Copy `cloud-init.yaml` to the root of the boot SD card driver as `user-data`.

Modify `cmdline.txt` to include `cgroup_enable=cpuset cgroup_enable=memory` before `rootwait` and after `elevator=deadline`.

## Supported Devices

 - Any server (untested)
 - Raspberry Pi 3
 - Raspberry Pi 4 (tested)