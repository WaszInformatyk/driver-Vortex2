# Copyright and attribution

This package is derived from the Linux `sound/pci/au88x0` driver and the
OpenVortex Project work, including contributions by Manuel Jander, Jeff
Muizelaar, Kester Maddock, the ALSA developers and other upstream contributors.
Please retain the SPDX notices and author comments in the source files.

The modifications in this distribution comprise:

- an external AU8830 module and DKMS build,
- compatibility with the 6.x and 7.x PCI/string APIs used by the test systems,
- a mapped guard page within the existing 64 KiB DMA preallocation,
- opt-in DMA/PCM diagnostics,
- `enable_wt` defaulting to disabled for the incomplete WT implementation,
- hardware/dependency detection, installation, repair, rollback and test tools,
- a separately generated stereo test tone.

These changes are distributed under **GNU GPL version 2 only**, consistently
with the strictest applicable upstream license declarations. No claim is made
to authorship of the original OpenVortex or Linux code.

The five-second generated test tone is provided under **CC0 1.0 Universal**.
No Windows binaries or third-party proprietary driver assets are included.
