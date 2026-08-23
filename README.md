# Vuron

[Download the Vuron Demo (macOS)](https://github.com/VanadiumVox/Vuron/blob/main/Vuron_Demo.zip?raw=true)

## 1. What is Vuron?

Vuron is a custom-built, high-performance 3D game engine and renderer developed entirely from scratch. It does not rely on commercial engines like Unity or Unreal. It is a native macOS application interfacing directly with the GPU hardware.

**The Game Type:** Vuron is being developed as a hyper-kinetic, momentum-based "Free Movement Shooter" / fast-paced sandbox platformer.

**The Goal:** To build a flawless, ultra-fast 3D playground where player movement is unrestrictive, geometry is mathematically solid, and the visual feedback is immediate. The goal is to achieve total mastery over low-level engine architecture (for/by myself, since this is all developed entirely myself).



https://github.com/user-attachments/assets/7e8c8a94-fd86-46bf-823a-526c1b02fe82



---

## 2. Technical Info

* **Core Languages:** C++, Objective-C++ (`.mm`) for Apple bridging, and Apple Metal Shader Language (`.metal`).
* **Graphics API:** Apple Metal (Direct-to-GPU). Used to avoid the overhead of higher-level APIs and extract maximum performance from Apple Silicon (M2 chips, etc).
* **Coordinate System:** Left-handed (Z pushes into the screen), mapping depth from 0.0 to 1.0.
* **Compile Environment:** Terminal via CMake / Make / Clang.

---

## 3. The "Pure Path" Philosophy

Vuron is developed using a philosophy called the **"Pure Path."**

* **Zero Bloat:** No massive libraries, no hacky `if` statements to patch edge cases. If a bug occurs (like clipping through a ramp), I ain't gonna write just a "patch"; I'll redesign the underlying mathematics to eliminate the edge case entirely.
* **Mathematical Roots:** Every problem is aimed to be solved at its geometric root. Algebraic truths (like Planes and Vectors) are favored over brute-force CPU loops.
* **Lean Architecture:** Data is passed to the GPU in the smallest footprints possible(by me). Vuron favors clever GPU-side math over bloated arrays, that type of stuff.

---

## 4. Inspirations

* **Ultrakill / Dusk / Quake:** For the raw, unadulterated speed, the PS1-style crisp flat-shading, the dynamic point lighting without shadow map overhead, and the momentum-heavy physics.
* **Team Fortress 2 / Half-Life 2 (Source Engine):** For lighting formulas (Half-Lambert shading) and robust, collision-slide physics.
* **John Carmack:** The approach to engineering—building custom math, binary space concepts, and raw C++ speed.

---

## 5. Directory Structure & Files

* `src/platform/mac/MacWindow.mm`: Handles the native macOS window creation and OS bridging.
* `src/renderer/MetalRenderer.h` & `.mm`: The absolute core of the engine. Contains the main rendering loop, input polling (bypassing standard OS keyboard delays), physics integration, geometry construction, and GPU command encoding.
* `src/renderer/Shaders.metal`: The GPU programs (Vertex and Fragment shaders) compiled at runtime. Handles all visual output, UI, and lighting.
* `src/math/Math.h`: The custom mathematics library. Contains strictly typed definitions for `Vector3`, `Matrix4x4`, `Frustum`, `AABB`, `Plane`, `Transform`, `Ray`, `Camera`, and `Rocket`.
* `src/levels/test_arena.vlvl`: A custom level format loaded via `src/world/LevelLoader.h`.

---

## 6. Controls, Mechanics & The Movement Sandbox

Vuron is designed for high-skill ceiling movement, featuring a highly complex, momentum-based state machine that calculates physics using rigid 3D vectors. Understanding the engine's physics states is key to mastering the sandbox. And also I love fighting games so some of these are combos :) 

### General Controls & HUD
* **WASD:** Move (stop pressing all for instant 0 momentum)
* **Spacebar:** Jump (Hold for slow falling)
* **Shift:** Crouch (Hold for fast falling)
* **"R"/Double tap on WASD:** Run (toggle acceleration on/off)
* **Left Click:** Fire Weapon / Shoot Grapple Hook
* **Right Click:** Melee Parry
* **Hold 'G':** Swap Weapon (Fills a visual UI loading bar to prevent accidental swaps).
* **Crosshair States:** Small crosshair indicates Grapple Hook is active; Large crosshair indicates Rocket Launcher is armed.
* **Debug Menu:** Toggle the debug overlay on/off with 'ctrl + v' to track precise velocity (using a true units-per-frame positional delta), coordinates, and active engine states.
* **Bounding Boxes:** Toggle the Bounding boxes for every object with 'ctrl + b' to visually indicate the hitboxes of every object.
* **Quitting:** Cmd + Q


https://github.com/user-attachments/assets/cc6a2401-e7f4-437d-bce2-40f5f103b153

<img width="463" height="346" alt="Screenshot 2026-08-23 at 9 33 50 PM" src="https://github.com/user-attachments/assets/5750ec1f-1612-4835-bf36-a863768cf731" />

<img width="1267" height="709" alt="Screenshot 2026-08-23 at 9 33 57 PM" src="https://github.com/user-attachments/assets/f0d13cc5-b4cf-4a53-bbd7-62610e88c480" />


### Core & Advanced Movement
* **Wavedashing:** A frame-perfect combo system. Crouching while carrying momentum on the ground grants a burst of speed (`m_currentMomentum += 0.05f`), softly capped at 0.5f. Includes a 15-frame input buffer.


https://github.com/user-attachments/assets/da16a4e2-888e-41f7-b72e-bd55f29e08f0


* **Boost Boots (Long Jump):** Crouching and moving on the ground triggers a 30-frame "hang time" where jump decay is paused, granting massive horizontal distance, but then brutally slicing the player's speed to 0.35f, unless accelerating.
* **Air Acceleration & Friction:** Preserves X/Z momentum independently of Y gravity. Floating gravity vs. Fast-fall gravity depends on jump input state.


https://github.com/user-attachments/assets/e9213999-7847-46e5-8b0c-a6d75113563f



* **Rocket Boots (High Jump):** Jumping and timing a "crouch" followed by another "jump" shortly after causes the player to launch upwards with a massive burst of speed. this effectively carries the player to higher reaches, and can be combined with speed to cover great distances.


https://github.com/user-attachments/assets/bb9ead44-1588-49ef-92b6-efe52c23ac09



### The Grappling Hook (True 3D Pendulum Physics)
* Utilizes advanced orbital mechanics, not simple linear pulling.
* Calculates 3D tension by projecting velocity away from the anchor point and neutralizing it.
* Uses a radius-based dampening system (friction increases heavily as the player nears the exact anchor point to prevent infinite orbital energy).
* Features an auto-retract speed and consumes mid-air charges (`m_currentAirGrapples`) that restock upon touching flat ground or sloped surfaces.


https://github.com/user-attachments/assets/d514108f-ec6c-4e85-8bf4-f5bc4715a2a2



### The Arsenal, Projectiles & Parrying
* **Zero-Allocation Rockets:** Projectiles are managed via a strict Ring Buffer (max capacity 5), eliminating memory allocation lag during firefights. Features a TF2-style auto-reload system (1 rocket per second after a firing delay). 
* **Continuous Collision Detection (CCD):** Rockets calculate exact surface normals upon impact via hitscan math to execute perfect Vector Reflection ricochets on both flat and custom wedge geometry. 
* **Rocket Jumping:** Look straight down (the engine allows a mathematically perfect 90º/1.5707f pitch without Gimbal Lock). Jump and parry(how? Read ahead!) a rocket simultaneously at the floor to launch yourself with 3x normal explosive force.
* **The Ricochet Parry Boost:** Fire a rocket at a wall. As it ricochets and travels back into your melee range, aim directly at it and Right-Click (utilizes a Dot-Product View Cone). A successful parry consumes the rocket, freezes time for a fraction of a second, shakes the screen, and violently blasts you in the opposite direction at hyper-speed.


https://github.com/user-attachments/assets/9981b251-a1ec-4b99-9cdc-9d19e69b3382



---

## 8. Mathematical Algorithms & Collision Architecture

### Convex Hull Architecture

* **The Math:** A wedge is now dynamically defined as 5 infinite `Plane` objects (Floor, Front Wall, Left/Right Triangles, Sloped Roof).
* **Separating Axis Theorem (SAT):** Instead of standard AABB checks, the Wedge physics pass uses SAT. It checks the player's 3D volume against all 5 planes simultaneously. If outside even one plane, no collision occurs. If inside all 5, it calculates the path of least resistance (`minPenetration`) and pushes the player out via the `pushNormal`.
* **Vector Sliding:** Kills velocity moving directly into the slanted wall (`dot(vel, pushNormal) < 0.0f`), while allowing the remaining vector to slide perfectly up or down the ramp.

### Raycasting (The Universal Plane Clipper)

* **Inverse Transformations:** To calculate ray hits, the engine takes the world-space ray and applies inverse Translation, Rotation (Z, then -Y, then -X), and Scale to teleport the ray into the object's perfect `1x1x1` local space.
* **Universal Algorithm:** Instead of Slab Method hacks, the engine tests the ray against mathematical boundaries. For wedges, it tests the `y + z <= 0` slope face, guaranteeing grapple hits from the top, sides, and bottom.

### Sub-Stepping (Time-Slicing)

* **Fixing Quantum Tunneling:** When falling at terminal velocity (`vel.y = -3.0f`), the player could phase through 0.5f-thick floors.
* Instead of "Swept Volumes" (stretching the hitbox, which caused the "Fat Hitbox" stair-snagging bug), the engine uses Time Slicing. It breaks `vel.y` into safe, `0.25f` chunks and processes the Y-Axis pass multiple times in a single frame.

### Frustum Culling

* Extracts the 6 mathematical planes of the Camera's View-Projection matrix. Checks the 8 corners of an object's `AABB` against those 6 planes. If the object is behind the camera, it skips the GPU draw call entirely, massively saving resources.

---

## 9. The Rendering & Lighting System

### Ultrakill Flat-Shading (Hardware Cross-Derivatives)

* Instead of bloating the C++ `Vertex` struct with Normal data, the Fragment Shader computes normals dynamically.
* It uses Metal's hardware functions `dfdx(in.worldPos)` and `dfdy(in.worldPos)` to compare adjacent pixels and calculate the exact 3D angle of a face via Cross Product (`normalize(cross(dy, dx))`).

### Dynamic Lighting (Without Shadow Map Bloat)

* **The Valve Half-Lambert Trick:** Standard Lambert shading makes faces pointing away from the sun pitch black. Vuron uses `(dot(normal, lightDir) * 0.5) + 0.5` to wrap light mathematically around geometry, ensuring Wedges and hidden faces are always brightly readable.
* **Point Lights:** Dynamic point lights (glowing pickups, rockets) calculate attenuation based on distance and blend perfectly with the global directional "Sun".
* **Retro Blob Shadows:** To avoid the massive GPU overhead of rendering Depth/Shadow Maps twice per frame, Vuron uses a CPU raycast straight down to find the highest floor. It then renders a semi-transparent black quad directly on the ground.

### Diagnostic Visuals & Pipeline Hijacking

* **The Alpha Flag System:** The shader relies on a `float alphaFlag` sent via `buffer(2)` to change its behavior mid-frame without needing entirely separate pipeline states for everything.
* `alphaFlag < 1.0`: Renders the Drop Shadow.
* `alphaFlag > 1.5`: Triggers UI rendering, carving out a Crosshair.
* `alphaFlag > 1.1 && < 1.4`: The Unlit Pipeline Bypass. Used for diagnostic wireframes (`Ctrl+B`) so lines render in pure Green (Local Transform) and Red (AABB) without derivative failure turning them black.


* **UI Color Inversion:** The UI crosshair uses a custom blend state (`MTLBlendFactorOneMinusDestinationColor`) to dynamically invert the colors of whatever it is hovering over.
* **Cross-Thread Debug UI:** A native macOS `NSTextField` overlay dispatched to the main thread to show real-time coordinates, speed, grappling charges, and culled object counts.


* **IMPORTANT INFO:** Due to the nature of coding, and the fact that I have almost zero experience with coding a project of this magnitude, let along doing it myself, this project has been aided by the use of AI. Specifically, Gemini 3.1 Pro being used most frequently. Whilst I have used it to help me get code that I could have no hope of figuring out myself, I strive to type every line of code by hand, regardless of whether it was given by AI or not. This project is to challenge myself, and to hopefully create a masterpiece that I am truly proud of. The Mac hardly has any good games that can also be played on older Macs, and always having been a gamer at heart, and a budding full-stack developer by profession, Vuron is my heartfelt attempt at making something that everybody enjoys. Not just people, but everybody. I want this to be like TF2, running on a potato. I want it to be like Ultrakill, fast, and performative, expressive by nature, and reflective of the player's abilities. It has to be fast, and it has to be lean. No compromises.
