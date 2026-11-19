# Changelog

## 0.1.0 — 2026-11-09

First public repair package for Aureal Vortex 2 AU8830.

- Prevent the one-page access beyond the full 64 KiB DMA ring by keeping a
  mapped 4 KiB guard page and limiting the logical buffer to 61440 bytes.
- Disable the known-incomplete WT PCM by default (`enable_wt=N`).
- Add optional `debug` diagnostics without enabling them in production.
- Add DKMS packaging, hardware and dependency detection, idempotent install,
  per-kernel reinstall, rollback and optional guarded module reload.
- Preserve the current PCI managed-I/O API on 7.x while providing a 6.x
  `pcim_iomap_regions()` fallback and explicit-size `strscpy()` calls.
  Builds pass for all installed 6.8 and 7.0 header sets.
- Add PipeWire/direct-ALSA tests, long-run stress testing and a CC0 test tone.
- Validate stereo playback, two streams, 22050–48000 Hz, long-run playback,
  cross-header builds and automatic DKMS loading after reboot.
