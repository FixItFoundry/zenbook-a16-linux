#!/usr/bin/env python3
"""Check the compiled/decoded topology's ABI against the A16 UCM profile."""
from pathlib import Path
import re
import sys


def block(text, name):
    match = re.search(r"(?m)^\s*" + re.escape(name) + r"\s*\{", text)
    if not match:
        raise ValueError(f"Missing topology block: {name}")
    start = match.end()
    depth = 1
    for end in range(start, len(text)):
        depth += (text[end] == "{") - (text[end] == "}")
        if depth == 0:
            return text[start:end]
    raise ValueError(f"Unclosed topology block: {name}")


def verify(text):
    pcms = block(text, "SectionPCM")
    caps = block(text, "SectionPCMCapabilities")
    expected = [
        ("MultiMedia1 Playback", 0, "playback", 2, 2),
        ("MultiMedia2 Playback", 1, "playback", 4, 4),
        ("MultiMedia3 Capture", 2, "capture", 1, 2),
        ("MultiMedia4 Capture", 3, "capture", 1, 4),
    ]
    if len(re.findall(r"pcm\.(?:playback|capture)\.capabilities", pcms)) != 4:
        raise ValueError("Expected exactly four PCM endpoints")
    for name, index, direction, minimum, maximum in expected:
        pcm = block(pcms, repr(name))
        # alsatplg omits default-valued fields, including PCM id 0.
        pcm_id = re.search(r"(?m)^\s*id (\d+)\s*$", pcm)
        if (int(pcm_id[1]) if pcm_id else 0) != index:
            raise ValueError(f"Wrong PCM index for {name}")
        for field in (f"dai.'{name}'.id {index}", f"pcm.{direction}.capabilities '{name}'"):
            if field not in pcm:
                raise ValueError(f"Missing {field}")
        capability = block(caps, repr(name))
        for field in ("formats 'S16_LE'", "rate_min 48000", "rate_max 48000",
                      f"channels_min {minimum}", f"channels_max {maximum}"):
            if not re.search(r"(?m)^\s*" + re.escape(field) + r"\s*$", capability):
                raise ValueError(f"Wrong {name} capability: {field}")
    graph = block(text, "SectionGraph")
    for route in (
        "WSA_CODEC_DMA_RX_0 Audio Mixer, MultiMedia2, stream1.logger1",
        "MultiMedia4 Mixer, VA_CODEC_DMA_TX_0, device110.logger1",
    ):
        if repr(route) not in graph:
            raise ValueError(f"Missing UCM route: {route}")
    widgets = block(text, "SectionWidget")
    for widget, mixer in (
        ("WSA_CODEC_DMA_RX_0 Audio Mixer", "MultiMedia2"),
        ("MultiMedia4 Mixer", "VA_CODEC_DMA_TX_0"),
    ):
        if repr(mixer) not in block(widgets, repr(widget)):
            raise ValueError(f"Missing mixer {widget}/{mixer}")


if __name__ == "__main__":
    verify(Path(sys.argv[1]).read_text())
    print("PASS: compiled A16 topology has UCM-compatible PCM IDs, capabilities and routes")
