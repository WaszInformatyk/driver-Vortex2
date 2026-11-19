#!/usr/bin/env python3
"""Generate the CC0 stereo test tone used by the AU8830 test scripts."""
from pathlib import Path
import math
import sys
import wave

RATE = 48000
SECONDS = 5
FADE = int(RATE * 0.02)

def main() -> None:
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("test-tone.wav")
    output.parent.mkdir(parents=True, exist_ok=True)
    frames = RATE * SECONDS
    pcm = bytearray()
    for index in range(frames):
        envelope = min(1.0, index / FADE, (frames - 1 - index) / FADE)
        left = round(32767 * 0.1 * envelope * math.sin(2 * math.pi * 440 * index / RATE))
        right = round(32767 * 0.1 * envelope * math.sin(2 * math.pi * 660 * index / RATE))
        pcm += left.to_bytes(2, "little", signed=True)
        pcm += right.to_bytes(2, "little", signed=True)
    with wave.open(str(output), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm)
    print(output)

if __name__ == "__main__":
    main()
