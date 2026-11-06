#!/usr/bin/env python3
"""Leaves FluidSynth out of a ZMusic source tree (argument: its path).

ZMusic's copy of FluidSynth needs glib, which iOS doesn't have. Without it,
MIDI music falls back to ZMusic's other synths (TiMidity, OPL, ...): a stub
CreateFluidSynthMIDIDevice throws, and ZMusic's own fallback picks the next.
Run it once on a fresh checkout; it stops if the source has moved on.
"""
import os, sys

root = sys.argv[1]

def patch(rel, old, new):
    p = os.path.join(root, rel)
    s = open(p).read()
    if s.count(old) != 1:
        sys.exit(f"{rel}: expected exactly one {old!r}")
    open(p, "w").write(s.replace(old, new))

patch("thirdparty/CMakeLists.txt", "add_subdirectory(fluidsynth/src)\n", "")
patch("source/CMakeLists.txt", "\tmididevices/music_fluidsynth_mididevice.cpp\n",
      "\tmididevices/music_nofluidsynth_mididevice.cpp\n")
patch("source/CMakeLists.txt", "timidity timidityplus wildmidi fluidsynth)", "timidity timidityplus wildmidi)")
patch("source/CMakeLists.txt", "target_link_libraries_hidden(zmusiclite zmusic-obj fluidsynth)",
      "target_link_libraries_hidden(zmusiclite zmusic-obj)")

with open(os.path.join(root, "source/mididevices/music_nofluidsynth_mididevice.cpp"), "w") as f:
    f.write('''// FluidSynth is left out of this build (it needs glib): opening it fails,
// so ZMusic falls back to its next MIDI synth.
#include <stdexcept>
#include "mididevice.h"

MIDIDevice *CreateFluidSynthMIDIDevice(int samplerate, const char *Args)
{
	throw std::runtime_error("FluidSynth is not available in this build");
}
''')
print("ZMusic: FluidSynth left out")
