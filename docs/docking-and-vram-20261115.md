# Station docking and GPU memory validation, 2026-11-15

The 70 m ship previously had to move its origin within 24 m of the homecoming port, although its bow could touch the tower first. The HUD advertised docking from 140 m and E invoked planetary landing. Imported stations additionally built their collision shapes before their measured dimensions were assigned, and their relative-speed checks reused the homecoming station's velocity.

All three stations now share a 600 m approach context, E docking within 140 m, automatic capture within 64 m, and a 22 m/s relative-speed limit. The approach must be above the tower port. The HUD marks the actual port and reports the station, distance and relative speed. X matches the nearby port's velocity; undocking inherits that velocity. Docked ships park 50 m above the port so their full bow clears the tower and retain the station's orientation. Station interactions consume E before planetary landing, including specific range, speed, approach-side and cooldown feedback.

`station_docking_test.gd` reproduces the screenshot's 118 m / 4.8 m/s approach for each station, enters and leaves each interior, checks full-hull clearance, validates fast/wrong-side approaches and cooldowns, and checks independent station velocities and braking. All 43 checks passed. The existing station test now initializes a safe approach with the orbiting station's velocity, rather than treating zero absolute velocity as zero relative velocity. The wall test waits for background scene reads before teardown.

## GPU residency

Ordinary lossless image compression reduced download size but left many 3D textures uncompressed on the GPU. `tools/configure_vram_textures.py` sets model texture imports to GPU compression with mipmaps. Source image bytes, filenames, model UVs and albedo resolution remain unchanged. The flat 4096 x 4096 station ORM map has a 1024 import-size limit; its source image is retained.

The same finite offscreen native probe loaded all 20 planets, visited cloud/firefly/alley/snow, returned, then freed the game. RTX 4060 Laptop GPU, OpenGL Compatibility, 1600 x 900. The launcher set no-focus before window creation, applied `offscreen_window.gd`, disabled mouse capture, monitored foreground ownership and reported no foreground activation.

| Engine GPU resource monitor | Before | After |
| --- | ---: | ---: |
| All resident resources | 962.6 MiB | 632.3 MiB |
| Textures | 497.9 MiB | 149.4 MiB |
| Buffers | 464.7 MiB | 483.0 MiB |
| After unloading game | 42.5 MiB | 60.8 MiB |

Total GPU resources dropped 34.3%; textures dropped 70.0%. All four pocket worlds and the subsequent return stayed at approximately 632.4 MiB. This is an engine resource measurement, not total Windows process or driver allocation, and does not include the user's other editor processes. The cropped Task Manager graph's 15.6 GB scale is not evidence of this game consuming 15.6 GB. This change does not establish a new FPS or cold-start benchmark.

`texture_budget_test.gd` checks actual imported compressed data, image dimensions and mip budgets for ship, station, cave, attic and planet textures: 32 checks passed. Twelve source regression groups passed: station docking, station, station integrity, station walls (275 rays), smoke, walking, runtime bakes (150 checks), texture budgets, settings, route linkage (81 checks), home gate (25 checks), and attic scenes (187 checks). Some pre-existing tests still report two ObjectDB instances at exit; no RID leak or gameplay ERROR remained in these completed runs.

Ignored evidence files: `_tools/_tmp/vram_before.json`, `vram_after.json`, `vram_visual_*.png`, and `docking_vram_tests.json`. Release package validation is recorded in `build/export-manifest-20261115.json`.
