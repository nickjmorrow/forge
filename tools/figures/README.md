# Figures

A step in a guide can carry a `figure`: a small looping line drawing of the movement, stored as data on the step (points in a
100 × 100 box, the strokes that join them, and the poses they pass through; see `Core/Sources/ForgeCore/Figure.swift`).

`make_figures.py` holds a library of them for common mobility drills and stretches and writes `figures.json` (`{"slug": figure}`).
To use one, read a guide (`forge guide show <id>`), set `"figure"` on a step to an entry from `figures.json`, and send the guide
back with `forge guide put --json`.

To look at the library after changing it, draw four moments of each figure as sheets:

```bash
python3 tools/figures/make_figures.py
cd UI && FORGE_FIGURES_JSON=../tools/figures/figures.json FORGE_SNAPSHOT_DIR=/tmp/sheets swift test --filter aLibraryOfFigures
```
