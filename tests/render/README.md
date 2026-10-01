# Render tests

Scenes rendered by OpenFL and compared, cell by cell and with room for anti-aliasing, against what
Adobe AIR shows for the same code. One lime project runs them all; the same build serves CI and a
developer's machine, and leaves the pictures needed to see what went wrong.

## Running

From this folder, with the openfl checkout as the `openfl` haxelib:

```
lime build hl && (cd Export/hl/bin && ./RenderTests.exe)                                     # HashLink, OpenGL window
lime build hl -Dsoftware && (cd Export/hl/bin && SDL_VIDEODRIVER=dummy ./RenderTests.exe)     # HashLink, Cairo, no display
lime build neko -Dsoftware && (cd Export/neko/bin && SDL_VIDEODRIVER=dummy ./RenderTests.exe) # neko, Cairo, no display
```

`-Dsoftware` gives a Cairo window, which the dummy video driver needs: it has no OpenGL. Or as a
group of the test suite, from the repository root (or from `tests/`), as the unit tests run:

```
haxelib run hxp test-render -Dtarget=hl                                 # OpenGL
SDL_VIDEODRIVER=dummy haxelib run hxp test-render -Dtarget=hl           # Cairo, no display (-Dsoftware is implied)
SDL_VIDEODRIVER=dummy haxelib run hxp test-render -Dtarget=neko         # neko, Cairo
```

`RENDER_SCENE=blend_rect,combined_high` runs only those scenes; `RENDER_OUT` sets the output folder
(default `out` in the working directory; the hxp group uses `out/<target>[_software]`). The exit code
is 0 when every cell passes.

## Output

For each scene and renderer, in the output folder:

| File | Content |
|---|---|
| `<scene>_<renderer>.png` | the capture, cropped to the reference's size |
| `<scene>_<renderer>_diff.png` | the largest channel difference per pixel, four times brighter |
| `<scene>_<renderer>_sheet.png` | reference, capture and difference side by side |
| `results_<renderer>.json` | every cell's scores, thresholds and verdict |

The renderer is the target and the window it drew into: `hl_opengl`, `hl_cairo`, `neko_cairo`. The
console shows the same table as the JSON, so a CI log names the failing cell.

## Scoring

A pixel is off when its largest channel difference exceeds the scene's **tolerance** (8 for hard-edged
scenes, 32 for scenes full of soft edges). Two shares are measured per cell, both in percent of the
cell's pixels:

- **off**: all pixels off. Catches everything, but a shifted or differently anti-aliased outline
  counts here too.
- **interior**: pixels off that are not within one pixel of an edge. An edge pixel differs from one of
  its eight neighbours by more than the tolerance, in the reference or in the capture. A wrong colour,
  a missing shape or a mask of the wrong size changes flat areas, so they land here; anti-aliasing
  does not.

A cell passes when `off <= maxOff` and `interior <= maxInterior`. The scene sets the defaults, a cell
can override them, and both are meant to ratchet: a cell gets the value it measures today, a regression
past it fails the run, an improvement lowers it in the next commit. Hard-edged cells get 0.

`mean` (the average difference) and `max` are reported for reading, not for the verdict.

## Scenes

| Scene | Reference | Cells | Tolerance | Source |
|---|---|---|---|---|
| `blend_rect` | `reference/blend_rect.png` | 52: thirteen modes, live / drawn / stage / container | 8, 0% off | the blend-mode suite's grid, drawRect variant |
| `filters_high` | `reference/filters_high.png` | 20: the filters alone at HIGH, no blend modes (`Filters.hx`) | 32, 1.5% off, 0.3% interior | the combined kit, `--variant filters` |
| `combined_high` | `reference/combined_high.png` | 20: the same cells, each subject also blended (`Combined.hx`) | 32, 1.5% off, 0.3% interior | the combined kit |

One class per scene, one reference image per class; `Filters` and `Combined` share their grid and
shapes through `Cells`. `filters_high` needs only the filters work, `blend_rect` only the blend-mode
work, and `combined_high` both, so a branch can run the scenes it supports (`RENDER_SCENE`) until
everything is merged.

A scene extends `render.Scene`: it sets its name, reference, size, stage colour and quality, tolerance
and thresholds, lists its cells, and `build(root)` draws it. The window is as large as the largest
reference (800 x 768); a smaller scene is compared over its own size at the top left.

The references are AIR's window captures, made on a developer's machine with the suite's capture
scripts (`capture_air_window.ps1` under adl, system chrome off, PrintWindow). They are regenerated only
when a scene changes. AIR ignores `stage.quality` in its window, so one reference serves every quality.

## CI

`.github/workflows/render-tests.yml` runs the group on `ubuntu-24.04` in two jobs, both with the
same Haxe setup as the unit tests:

| Job | Window | How |
|---|---|---|
| `render-cairo` | Cairo, HashLink and neko | `SDL_VIDEODRIVER=dummy`: no display, no OpenGL, so `-Dsoftware` is implied |
| `render-opengl` | OpenGL, HashLink | `xvfb-run` with Mesa's llvmpipe (`LIBGL_ALWAYS_SOFTWARE=1`), built with `-Dopenfl_gl_sync_backdrop` |

**llvmpipe needs `-Dopenfl_gl_sync_backdrop`.** Blend modes that read the backdrop copy it out of the
framebuffer with `glCopyTexSubImage2D`. llvmpipe can run that copy before its rasterizer threads have
finished the draws before it, so a blended group inside a LAYER sees an empty backdrop and a varying
number of cells fail from run to run; `glFlush` does not help, `glFinish` does. The define adds that
wait before the copy. It stalls the pipeline once per blended group, so it is for software OpenGL
only; `build.hx` adds it whenever `LIBGL_ALWAYS_SOFTWARE` is set. On a GPU the renderer is unchanged.
The same holds for Mesa on Windows (its `opengl32.dll` next to the executable), which is how to
reproduce the CI result locally.

Each job uploads `tests/render/out` as an artifact (`render-tests-cairo`, `render-tests-opengl`), so a
failure can be looked at without reproducing it: the same captures, difference images, sheets and
`results_<renderer>.json` the local run writes. The console log holds the tables.

## Notes

- The capture is taken on the scene's fourth frame: on a Cairo window `readPixels` returns the frame
  before the current one.
- Text with device fonts differs per OS; a scene with text should embed its font.
- The Cairo window with `SDL_VIDEODRIVER=dummy` needs no display, so those runs work on a headless CI
  runner as they are. An OpenGL window on a Linux runner needs Xvfb and Mesa's llvmpipe.
- Scoring 800 x 768 pixels takes about a second on HashLink and several on neko.
