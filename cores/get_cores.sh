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
    # This repo only ever needs the core's current rtl/ -- not its own
    # commit history (that belongs in the core's own repo), and not its
    # docs/*.pdf reference manuals (tens of MB, irrelevant to a build
    # dependency). A plain (even --depth 1) clone still transfers every
    # blob in the current tree, including those PDFs, which repeatedly
    # failed over a throttled connection during initial testing (three
    # separate HTTP/2 disconnects). A blobless partial clone + cone-mode
    # sparse-checkout limited to rtl/ avoids fetching those blobs at all.
    git clone --filter=blob:none --no-checkout --depth 1 "$url" "$dest"
    (
        cd "$dest"
        git sparse-checkout init --cone
        git sparse-checkout set rtl
        git checkout main
    )
}

# MH030: cycle-accurate MC68030 CPU core (this project's own m68030_top)
clone_core mh030 https://github.com/harrowm/MH030.git

# MH882: MC68881/68882 FPU coprocessor core — not needed for initial
# bring-up (no coprocessor wired into the memory map yet), fetched here
# so it's available once that stretch goal is picked up.
clone_core mh882 https://github.com/harrowm/mh882.git

# OpenCores 16550-compatible UART -- the same core Mackerel-F itself uses
# (freecores GitHub mirror, matching its own get_cores.sh exactly).
clone_core_full() {
    local name="$1" url="$2" dest="$CORES_DIR/$1"
    if [ -d "$dest" ]; then
        echo "Skipping $name (already present at $dest)"
        return
    fi
    echo "Cloning $name into $dest..."
    git clone --depth 1 "$url" "$dest"
}
clone_core_full uart16550 https://github.com/freecores/uart16550.git

echo "Done."
