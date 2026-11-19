# SPDX-License-Identifier: GPL-2.0
# External-module build for the AU8830 only.  The other AU88x0 sources are
# retained for reference, but are not linked into this module.

ifneq ($(KERNELRELEASE),)

snd-au8830-y := au8830.o
obj-m += snd-au8830.o

else

KDIR ?= /lib/modules/$(shell uname -r)/build
JOBS ?= $(shell nproc)

.PHONY: all clean

all:
	$(MAKE) -C "$(KDIR)" M="$(CURDIR)" -j"$(JOBS)" modules

clean:
	$(MAKE) -C "$(KDIR)" M="$(CURDIR)" clean

endif
