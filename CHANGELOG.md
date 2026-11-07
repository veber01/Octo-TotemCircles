## QoL stuff (v0.5)

- Added a UI window for all the customizable settings so its easier to personalize the addon. (use minimap button or /tcrui /tcr options commands)
- Added Minimap button
- Made all custom settings persistent

## More Performance changes (v0.4.9)

- **Offscreen culling** Skip rendering and visibility updates for circles offscreen 
- **Combined draw calls** Batching circles into one submission instead of each totem calling each frame
- **Cached geometry** Precomputes world-space circle geometry until totem position changes
- Added performance presets for low-end users /tcr performance <Low/Balanced/High>

## Performance changes (v0.4.8)

- **Persistent terrain cache:** sample a totem ground only once. No periodic terrain rebuild.
- **Incremental sampling:** at most **four new ring spokes per ~16 ms window** across all active totems. Rings become visible when the ring is ready (a short delay is normal).
- **Lower-overhead D3D9 rendering:** reuse D3D state block, CPU buffer and a dynamic vertex buffer.

## Renderer notes (v0.4.7)

- Continuous terrain-following rings with protection against sudden height jumps and disconnected platforms.
- Camera-to-ring visibility checks include segment midpoints, faster refreshes and near-camera projection safeguards.
- Occlusion uses collision traces, not the GPU depth buffer; decorative geometry may differ from collision geometry.
- Settings, including occlusion, are saved in `TotemCirclesDB`.