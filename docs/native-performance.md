# Windows rendering and loading budgets

Static architecture batching and small-object distance culling run on Windows and Web. The batcher preserves source triangles, collision bodies and gameplay anchors. Medium quality uses a 1024-pixel directional shadow atlas over 180 metres; high and custom shadow settings retain their own budgets. Stars are unchanged by this optimization.

Windows progressively reads planet snapshots with `ResourceLoader.load_threaded_request`. Only a completed request is consumed on the main thread, which then instantiates the scene and restores live bindings. Loading pauses before scene instantiation if the player enters the attic or pauses the game. Web keeps its existing loading path because the export template does not enable threads.

The bake tool restores the base viewing ranges and full prop density before saving. A developer's saved low-quality settings must not be compounded when a player loads the exported snapshots.

`planet_collision_budget.gd` removes distant static bodies from the physics space. Buildings and terrain wake at a surface distance of 5000 metres from either the player or ship, and sleep beyond 6500 metres. The budget preserves authored process and disable modes, tracks terrain loaded after the initial scene, and runs before player movement. Planet orbits and physics interpolation remain enabled. The bake command disables this runtime policy so snapshots retain enabled collisions.

Regenerate caches after changing their source recipes:

```powershell
& 'D:/GAME/godot/Godot_v4.7.1-stable_win64_console.exe' --headless --path . --script res://tools/bake_runtime_assets.gd -- --no-capture --rebake-runtime
```

Validation includes `runtime_bake_test.gd`, `planet_collision_budget_test.gd`, `web_static_batch_test.gd`, `scene_visibility_test.gd`, `settings_test.gd`, walking and all-planet stability tests, station integrity, route linkage and attic scene regression. Headless tests validate functionality, not GPU performance. Native rendering measurements must use a finite offscreen probe with `display/window/size/no_focus=true` set before the engine creates its window, `OffscreenWindow.apply()` and `--no-capture`.

Latest exports and measured results are recorded in the ignored `build/export-manifest-20261115.json`. Measurements are specific to the tested adapter, resolution and scenes; initial asset uploads and first-use shader compilation can still cause a loading spike.

On 2026-11-15, an offscreen native OpenGL Compatibility run on the RTX 4060 Laptop GPU measured the following medium-quality stationary samples, without a 3D resolution reduction:

| Window | Previous mean frame | Updated mean frame | Previous draws | Updated draws |
| --- | ---: | ---: | ---: | ---: |
| 1600 x 900 | 27.22 ms | 16.18 ms | 2208 | 670 |
| 2560 x 1440 | 25.25 ms | 15.04 ms | 2206 | 670 |

Each stationary sample lasted four seconds. Updated walking averaged 17.31 ms over four seconds, compared with 24.06 ms before. The four local worlds averaged 4.51-5.20 ms during three-second stationary samples. Initial background loading still had a 318 ms maximum frame and the first cloud-world entry took 688 ms; these are separate from steady-state frame performance. The 900p stationary sample also contained two frames over 50 ms. The probe stayed offscreen without mouse capture, and the launcher detected no foreground activation during the successful measurements.
