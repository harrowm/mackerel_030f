#!/usr/bin/env bash
# Clone the external CPU/FPU core repos used by Mackerel-030F.
#
# Mirrors mackerel-68k's own pld/mackerel-f/get_cores.sh convention exactly:
# cores are fetched, not vendored, so this project never carries a second
# copy of MH030/MH882's own RTL. Each core keeps its own independent
# verification history (Tom Harte sweep, Musashi cosim, etc.) in its own
# repo; this script just clones them into cores/ so the build can reference
# cores/mh030/rtl/*.sv the same way mackerel-f references cores/fx68k/*.sv.

set -euo pipefail

CORES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

clone_core() {
    local name="$1" url="$2" dest="$CORES_DIR/$1"
    if [ -d "$dest" ]; then
        echo "Skipping $name (already present at $dest)"
        return
    fi
    echo "Cloning $name into $dest..."
    git clone "$url" "$dest"
}

# MH030: cycle-accurate MC68030 CPU core (this project's own m68030_top)
clone_core mh030 https://github.com/harrowm/MH030.git

# MH882: MC68881/68882 FPU coprocessor core — not needed for initial
# bring-up (no coprocessor wired into the memory map yet), fetched here
# so it's available once that stretch goal is picked up.
clone_core mh882 https://github.com/harrowm/mh882.git

echo "Done."
