# BeamNG Mirrors Implementation Notes

This repository is a small BeamNG.drive mod that adds picture-in-picture mirrors for the player's current vehicle. The implementation is compact: almost all of the behavior lives in a single Lua extension, with a tiny registration file and a pair of JSON files for input metadata.

## File layout

- `scripts/vehicle_mirrors_angelo234/modScript.lua`  
  Registers the extension with BeamNG.
- `scripts/vehicle_mirrors_angelo234/extension.lua`  
  Main implementation for mirror discovery, camera placement, rendering, UI, and saved state.
- `lua/ge/extensions/core/input/actions/input_actions_vehicle_mirrors_angelo234.json`  
  Declares the `toggle_veh_mirrors_angelo234` action and wires it to `toggleMirrorsUI()`.
- `settings/inputmaps/keyboard_vehicle_mirrors_angelo234.json`  
  Default keyboard binding for the action (`F3`).
- `mod_info/MBAH352DV/info.json`  
  Mod metadata and the original user-facing description.

## High-level flow

1. BeamNG loads `modScript.lua`, which registers `extension.lua`.
2. The input action calls `toggleMirrorsUI()` when the user presses `F3`.
3. When the player switches vehicles, `onVehicleSwitched()` rebuilds mirror data for the new vehicle.
4. `onPreRender()` updates the mirror camera transforms right before rendering.
5. `onUpdate()` manages active render views and draws the ImGui windows that show the mirror textures.
6. `onSerialize()` and `onDeserialized()` persist mirror settings across reloads.

## Core pieces

### 1. Mirror modes and render targets

At the top of `extension.lua`, the mod defines three mirror bits:

- `MIRROR_1_BIT`: left mirror
- `MIRROR_2_BIT`: right mirror
- `MIRROR_3_BIT`: interior rear-view mirror

These are combined into the user-visible modes:

- `MODE_OFF`
- `MODE_WING_MIRRORS`
- `MODE_REAR_VIEW_MIRROR`
- `MODE_ALL_MIRRORS`

The file also predefines:

- ImGui window names (`mirrorUIsName`)
- render view names (`renderViewsName`)
- render texture names (`texturesName`)
- initial window positions and sizes
- field of view, near clip, and far clip values

Those constants are the configuration backbone for both the rendering side and the UI side.

### 2. Persistent runtime state

The most important mutable state in `extension.lua` is:

- `mode`: current mirror mode
- `efficientRendering`: whether only one render view is reused and alternated
- `resMult`: resolution multiplier for the render textures
- `farClip`: render distance
- `mirrorsNodeGroup`: node groups for the left and right exterior mirrors
- `mirrorsRefNodes`: reference nodes used to compute mirror orientation
- `mirrorsRotOffset`: correction quaternion that aligns the mirror with the vehicle-facing direction
- `intMirrorOffsetVec`: position of the interior mirror relative to the vehicle reference node
- `mirrorsYaw` / `mirrorsPitch`: per-mirror angle adjustment values exposed in the UI
- `mirrorsHorizontalOffset` / `mirrorsVerticalOffset`: per-mirror position offsets used to move mirrors left/right and up/down
- `renderViews`, `frustums`, `resolutions`, `viewports`: active render infrastructure

This state is what makes the mod feel dynamic: the mirror windows can be moved and resized, the view angles can be tuned, and the data survives serialization.

## Most important functions

### `getMirrorRefNodes(vdata, nodeGroup)`

This function is one of the most important pieces in the whole mod.

It receives a mirror node group from the vehicle data and picks three reference nodes:

- the left-most node
- the right-most node
- the highest remaining node

From those points it builds a local orientation for the mirror mesh. It then compares that orientation with the vehicle's reference/back/up nodes and computes `mirrorRotOffset`, a quaternion that makes the virtual mirror camera face the correct direction.

Why it matters:

- exterior mirror rendering depends on this function
- it converts raw JBeam/flexbody data into something usable at runtime
- the quality of mirror alignment is determined here

### `getMirrorsInitData()`

This function discovers whether the current vehicle appears to have usable mirror geometry.

It searches flexbody mesh names for:

- left mirror meshes ending in `_mirror_L`
- right mirror meshes ending in `_mirror_R`
- interior mirror meshes matching patterns such as `_int...mirror`, `_ceiling`, or `_center_mirror`

Then it:

- collects the exterior mirror node groups
- calls `getMirrorRefNodes()` for left and right mirrors
- estimates the interior mirror position by averaging its flexmesh vertices

Why it matters:

- it is the bridge between arbitrary vehicle content and the generic mirror renderer
- if this function cannot identify mirror data, that mirror cannot be shown
- it explains why vanilla vehicles work best and some modded vehicles may fail

### `getMirrorOrientation(veh, mirrorID, outMat)`

This function computes the actual camera transform used for rendering a mirror view.

For wing mirrors it:

- reads the current node positions from the live vehicle
- reconstructs direction and up vectors
- applies user yaw/pitch adjustments
- applies optional user horizontal/vertical position offsets
- applies the precomputed rotation offset
- averages the mirror node positions to place the camera

For the interior mirror it:

- uses the vehicle reference node rotation
- applies the user yaw/pitch adjustments
- offsets from the vehicle by `intMirrorOffsetVec`
- applies user horizontal/vertical position offsets

Why it matters:

- this is the core runtime camera math
- every mirror image depends on this transform being correct
- it allows mirrors to follow vehicle deformation and movement in real time

### `onPreRender(dt)`

This hook updates the render-view camera matrices immediately before rendering.

There are two rendering strategies:

- **Normal rendering:** one render view per visible mirror
- **Efficient rendering:** one render view is reused and alternated between active mirrors

Efficient mode improves performance, but it reduces smoothness and can introduce flicker. That tradeoff is explicitly surfaced in the UI.

Why it matters:

- this is where the camera transforms are pushed into BeamNG's render system
- it is the heart of the mirror rendering loop

### `renderMirrorWindow(id)` and `renderImGui()`

`renderImGui()` decides which mirror windows should be visible for the current mode.  
`renderMirrorWindow(id)` creates the actual ImGui window, draws the render texture, opens the right-click popup, and reacts to window resizing.

When the window size changes, `renderMirrorWindow(id)` recalculates:

- texture resolution
- viewport size
- frustum aspect ratio

That is why the mirrors can be resized interactively without requiring a restart.

Why they matter:

- these functions turn the low-level render views into visible UI mirrors
- they keep the render resolution synchronized with the window size

### `renderPopUpViewControl(mirrorID)`

This function provides the per-mirror and global configuration popup.

The popup allows the player to change:

- yaw angle
- pitch angle
- horizontal position
- vertical position
- render distance
- resolution multiplier
- efficient rendering mode

When these values change, the function also rebuilds quaternions, frustums, resolutions, and viewports as needed.

Why it matters:

- it is the main user customization surface
- many of the dynamic rendering adjustments happen here

### `onVehicleSwitched(oldId, newId, player, secondTime)`

This function resets old mirror state and initializes new state for the active vehicle.

Important detail:

- the first call intentionally delays real setup and queues a second call through vehicle Lua
- this is done so flexmeshes are initialized before mirror discovery runs

After the delayed pass, the function fills:

- node groups
- reference nodes
- rotation offsets
- interior mirror offset

Why it matters:

- mirror detection is vehicle-specific
- without this hook, the mod would not adapt when the player changes cars

### `toggleMirrorsUI()`

This is the user entry point triggered by the input binding. It cycles through:

`Off -> Side Mirrors -> Rear View Mirror -> All Mirrors -> Off`

It also shows a BeamNG GUI message with the active mode.

Why it matters:

- this is the simplest function conceptually, but it is the main interaction users see first

### `initMirrorView(id)` and `destroyView(id)`

These functions allocate and free BeamNG render views.

They are small, but they are important because they control:

- when render targets exist
- which texture name each render view writes to
- the resolution, viewport, frustum, and camera matrix attached to each view

### `onUpdate(dt)`

This is the higher-level frame loop for UI-side maintenance.

It:

- creates or destroys render views when the mode changes
- handles efficient versus non-efficient render view setup
- calls `renderImGui()`

This means `onUpdate()` is the coordinator for mirror visibility, while `onPreRender()` is the coordinator for mirror camera transforms.

### `onSerialize()` and `onDeserialized(data)`

These functions save and restore the runtime configuration.

The serialized data includes:

- current mode
- efficient rendering flag
- resolution multiplier
- far clip distance
- discovered mirror metadata
- user yaw/pitch settings

`onDeserialized()` also rebuilds the ImGui pointer wrappers and the cached quaternions so the restored values immediately work again.

## Important implementation details

### Exterior mirrors are discovered from mesh naming conventions

The mod does not use a dedicated mirror API. Instead, it infers mirror presence from flexbody mesh names and their grouped nodes. This keeps the implementation generic, but also means compatibility depends on how a vehicle's content is authored.

### Interior mirror placement is estimated

The interior mirror is positioned by averaging the vertices of the detected flexmesh and applying a small downward correction. This is simple and surprisingly practical, but it is still an approximation rather than explicit author data.

### Window size affects render quality

Mirror resolution is tied to the ImGui window size multiplied by `resMult`. Enlarging a mirror window increases the underlying render texture dimensions as well.

### Efficient rendering is a performance tradeoff

In efficient mode the mod reuses a single render view and alternates which mirror gets rendered. This reduces rendering cost, but the mirrors update less smoothly and may flicker depending on graphics settings.

## Practical limitations and assumptions

Based on the code and mod metadata, the mod assumes:

- the active vehicle exposes recognizable mirror meshes
- exterior mirrors have enough grouped nodes to derive left/right/up directions
- some graphics settings may cause visual artifacts
- modded vehicles may be less reliable than vanilla vehicles

The metadata in `mod_info/MBAH352DV/info.json` also warns users to be careful with anti-aliasing, bloom, ambient occlusion, motion blur, and shadows if graphical glitches appear.

## In one sentence

The mod works by finding mirror geometry on the active vehicle, deriving camera transforms from that geometry, rendering those views into textures, and presenting the textures inside movable ImGui windows with adjustable per-mirror settings.
