#include "MetalRenderer.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Appkit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/AppKit.h>
#include <iostream>
#include "../math/Math.h"
#include "../world/LevelLoader.h"

namespace vuron {
    // Constructor & destructor
    MetalRenderer::MetalRenderer() : m_device(nullptr), m_commandQueue(nullptr), m_metalLayer(nullptr), m_pipelineState(nullptr), m_vertexBuffer(nullptr), m_indexBuffer(nullptr), m_depthTexture(nullptr), m_depthStencilState(nullptr) {}
    MetalRenderer::~MetalRenderer() { shutdown(); }

    // -=The input Bridge=-
    // Changes flags the exact millisecond a key is pressed
    // Bypasses standard keyboard delay
    void MetalRenderer::setKeyState(char key, bool isPressed) {
        // Z-axis (forward/backwards)
        if (key == 'w' || key == 's') {
            if (key == 'w') m_keyW = isPressed;
            if (key == 's') m_keyS = isPressed;

            if (isPressed) {
                m_activeZ = key; // The most recent key
            } else {
                // If we let go of a key, check if opposite key is still held
                if (key == 'w' && m_keyS) m_activeZ = 's'; // First w then s
                else if (key == 's' && m_keyW) m_activeZ = 'w'; // First s then w
                else m_activeZ = 0; // Neither pressed
            }
        }

        //X-axis (left/right)
        if (key == 'a' || key == 'd') {
            if (key == 'a') m_keyA = isPressed;
            if (key == 'd') m_keyD = isPressed;

            if (isPressed) {
                m_activeX = key; // The most recent key
            } else {
                if (key == 'a' && m_keyD) m_activeX = 'd';
                else if (key == 'd' && m_keyA) m_activeX = 'a';
                else m_activeX = 0;
            }
        }

        // Jump logic
        if (key == ' ') {
            m_keySpace = isPressed;
            // The exact moment you let go
            if (!isPressed) {
                m_hasJumped = false;
            }
        }

        // Crouch logic
        if (key == 'C') {
            m_keyShift = isPressed;
        }

        // Acceleration toggle logic
        if (key == 'r') {
            if (isPressed && !m_keyR) {
                m_isAccelerating = !m_isAccelerating; // Flip the switch
            }
            m_keyR = isPressed;
        }
    }
    // ---------------------------------------------------------

    // -=Mouse input bridge=-
    void MetalRenderer::addMouseDelta(float dx, float dy) {
        m_mouseDeltaX += dx;
        m_mouseDeltaY += dy;
    }

    // ==========================================
    // -= LEvel BUIlding Tools =-
    // ==========================================
    void MetalRenderer::addCube(float px, float py, float pz, float sx, float sy, float sz) {
        vuron::Transform t;
        t.position = {px, py, pz};
        t.rotation = {0.0f, 0.0f, 0.0f};
        t.scale = {sx, sy, sz};
        m_cubes.push_back(t);
    }

    void MetalRenderer::loadTestLevel() {
        // We MUST spawn the 3 spinning cubes here. They sit at indices 0, 1, & 2
        addCube(0.0f, 0.0f, 0.0f,  1.0f, 1.0f, 1.0f); // Cube 0
        addCube(-2.0f, 0.0f, 0.0f,  1.0f, 1.0f, 1.0f); // Cube 1
        addCube(2.0f, 0.0f, 0.0f,  0.5f, 0.5f, 0.5f); // Cube 2 (shrunk)

        // The massive floor
        addCube(0.0f, -2.5f, 0.0f, 100.0f, 0.5f, 100.0f);

        // The staircase
        addCube(0.0f, -2.0f, 4.0f,  3.0f, 1.0f, 1.0f);
        addCube(0.0f, -1.5f, 6.0f,  3.0f, 1.0f, 1.0f);
        addCube(0.0f, -1.0f, 8.0f,  3.0f, 1.0f, 1.0f);
        addCube(0.0f, -0.5f, 10.0f, 3.0f, 1.0f, 1.0f);
        addCube(0.0f, 0.0f, 12.0f, 3.0f, 1.0f, 1.0f);
        addCube(0.0f, 0.5f, 14.0f, 3.0f, 1.0f, 1.0f);

        addCube (0.0f, -2.5f, 550.0f,  15.0f, 0.5f, 1000.0f);

    }

    bool MetalRenderer::init(void* windowHandle) {
      if (!windowHandle) return false;
      NSWindow* window = (NSWindow*)windowHandle;

      // Grabbing the hardware GPU
      id<MTLDevice> device = MTLCreateSystemDefaultDevice();
      if (!device) {
        std::cerr << "Metal Error: GPU does not support Metal" << std::endl;
        return false;
      }
      m_device = (void*)device;
      std::cout << "Vuron Renderer hooked into GPU -> " << [[device name] UTF8String] << std::endl;

      // Creating the command queue (The pipeline to send GPU commands)
      id<MTLCommandQueue> commandQueue = [device newCommandQueue];
      m_commandQueue = (void*)commandQueue;

      // Create the Metal canvas layer and attach it to the window
      //Setup the Canvas
      CAMetalLayer* metalLayer = [[CAMetalLayer alloc] init];
      metalLayer.device = device; // CRITICAL - tell the cnavas which GPU to use
      metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
      metalLayer.frame = window.contentView.bounds; // Match physical window size

      // Screwing the canvas into the window
      window.contentView.wantsLayer = YES;
      window.contentView.layer = metalLayer;

      m_metalLayer = (void*)metalLayer;

      // Loading and compiling the Shader File at Runtime
      NSString* shaderPath = @"src/renderer/Shaders.metal";
      NSError* error = nil;
      NSString* shaderSource = [NSString stringWithContentsOfFile:shaderPath encoding:NSUTF8StringEncoding error:&error];

      if (!shaderSource) {
        std::cerr << "Vuron Error: Could not locate Shaders.metal." << std::endl;
        return false;
      }

      id <MTLLibrary> library = [device newLibraryWithSource:shaderSource options:nil error:&error];
      if (!library) {
        std::cerr << "Shader compilation error (you didn't install Minecraft Shaders, did you?)" << [[error localizedDescription] UTF8String] << std::endl;
        return false;
      }

      // Extract our specific functions by name
      id<MTLFunction> vertexFunc = [library newFunctionWithName:@"vertexMain"];
      id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"fragmentMain"];

      // Creating the pipeline descriptor
      MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
      pipelineDesc.vertexFunction = vertexFunc;
      pipelineDesc.fragmentFunction = fragmentFunc;
      // Telling the shader that the output must perfectly match window's color format
      pipelineDesc.colorAttachments[0].pixelFormat = metalLayer.pixelFormat;
      // Tell the pipeline to expect 32-bit Float depth math
      pipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

      // Baking the pipeline descriptor into the GPUs memory
      id<MTLRenderPipelineState> pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
      if (!pipelineState) {
        std::cerr << "Pipeline error: " << [[error localizedDescription] UTF8String] << std::endl;
        return false;
      }
      m_pipelineState = (void*)pipelineState;
      std::cout << "Vuron Shaders successfuly compiled" << std::endl;

      // ----------------------------------------------------

      // -=The Depth Stencil (z-buffer)=-
      // Creating the rules for it to follow
      MTLDepthStencilDescriptor* depthDesc = [[MTLDepthStencilDescriptor alloc] init];
      // Only draw if closer to the camera
      depthDesc.depthCompareFunction = MTLCompareFunctionLess;
      // Allow writing new distances to the canvas
      depthDesc.depthWriteEnabled = YES;

      id<MTLDepthStencilState> depthStencilState = [device newDepthStencilStateWithDescriptor:depthDesc];
      m_depthStencilState = (void*)depthStencilState;

      // Creating the invisible depth canvas (matching 1280x720p window size)
      MTLTextureDescriptor* depthTexDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                            width:1280
                                            height:720
                                            mipmapped:NO];
      depthTexDesc.usage = MTLTextureUsageRenderTarget;
      depthTexDesc.storageMode = MTLStorageModePrivate; // Keep this memory strictly on GPU

      id<MTLTexture> depthTexture = [device newTextureWithDescriptor:depthTexDesc];
      m_depthTexture = (void*)depthTexture;

      // Creating the first Triangle in Vuron
//       vuron::Vertex triangleVertices[] = {
//         {{ 0.0f, 0.577f, 0.0f}, { 1.0f, 0.0f, 0.0f}}, // Top line Red
//         {{ 0.5f, -0.288f, 0.0f}, { 0.0f, 1.0f, 0.0f}}, // Bottom right green
//         {{ -0.5f, -0.288f, 0.0f}, { 0.0f, 0.0f, 1.0f}}, // Bottom left blue
//       };
//
//       // Allocating memory and copying the triangle into it
//       id<MTLBuffer> vertexBuffer = [device newBufferWithBytes:triangleVertices
//                                     length:(sizeof(vuron::Vertex) * 3)
//                                     options:MTLResourceStorageModeShared];
//       m_vertexBuffer = (void*)vertexBuffer;

        // Creating the first Vuron Cube
        vuron::Vertex cubeVertices[] = {
        // Front face (z = -0.5)
        {{-0.5f,  0.5f, -0.5f}, {1.0f, 0.0f, 0.0f}}, // 0: Top Left (Red)
        {{ 0.5f,  0.5f, -0.5f}, {0.0f, 1.0f, 0.0f}}, // 1: Top Right (Green)
        {{-0.5f, -0.5f, -0.5f}, {0.0f, 0.0f, 1.0f}}, // 2: Bottom Left (Blue)
        {{ 0.5f, -0.5f, -0.5f}, {1.0f, 1.0f, 0.0f}}, // 3: Bottom Right (Yellow)
        // Back face (z = 0.5)
        {{-0.5f,  0.5f,  0.5f}, {1.0f, 0.0f, 1.0f}}, // 4: Top Left (Magenta)
        {{ 0.5f,  0.5f,  0.5f}, {0.0f, 1.0f, 1.0f}}, // 5: Top Right (Cyan)
        {{-0.5f, -0.5f,  0.5f}, {1.0f, 1.0f, 1.0f}}, // 6: Bottom Left (White)
        {{ 0.5f, -0.5f,  0.5f}, {0.0f, 0.0f, 0.0f}}, // 7: Bottom Right (Black)
        };

        uint16_t cubeIndices[] = {
        0, 2, 1,  1, 2, 3, // Front
        1, 3, 5,  5, 3, 7, // Right
        5, 7, 4,  4, 7, 6, // Back
        4, 6, 0,  0, 6, 2, // Left
        4, 0, 5,  5, 0, 1, // Top
        2, 6, 3,  3, 6, 7  // Bottom
        };

      // 1. Sending 8 points to the GPU
      id<MTLBuffer> vertexBuffer = [device newBufferWithBytes:cubeVertices
                                    length:(sizeof(vuron::Vertex) * 8)
                                    options:MTLResourceStorageModeShared];
      m_vertexBuffer = (void*)vertexBuffer;

      //2. Sending instruction map to the GPU
      id<MTLBuffer> indexBuffer = [device newBufferWithBytes:cubeIndices
                                    length:(sizeof(uint16_t) * 36)
                                    options:MTLResourceStorageModeShared];
      m_indexBuffer = (void*)indexBuffer;

      return true;
    }

    void MetalRenderer::drawFrame() {
    @autoreleasepool{
      if (!m_metalLayer || !m_commandQueue) return;

      // Casting the raw void* into Apple Hardware pointers
      CAMetalLayer* layer = (CAMetalLayer*)m_metalLayer;
      id<MTLCommandQueue> queue = (id<MTLCommandQueue>)m_commandQueue;

      // -=The Resizing hook=-
      // Forces the physical GPu texture to mach window size every frame
      CGSize currentSize = layer.bounds.size;
      if (layer.drawableSize.width != currentSize.width || layer.drawableSize.height != currentSize.height) {
        layer.drawableSize = currentSize;
      }
      // ----------------------------------------

      // Ask the hardware for the next screen frame
      id<CAMetalDrawable> drawable = [layer nextDrawable];
      if (!drawable) return;

      // -=Dynamic Depth Canvas=-
      // If the OS resizes the window, the Depth canvas must be rebuilt based on the new grid
      id<MTLTexture> depthTex = (id<MTLTexture>)m_depthTexture;
      if (depthTex.width != drawable.texture.width || depthTex.height != drawable.texture.height) {

        id<MTLDevice> device = drawable.texture.device;

        MTLTextureDescriptor* depthTexDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                              width:drawable.texture.width
                                              height:drawable.texture.height
                                              mipmapped:NO];
        depthTexDesc.usage = MTLTextureUsageRenderTarget;
        depthTexDesc.storageMode = MTLStorageModePrivate;

        //Overwrite old memory with the newly sized canvas
        m_depthTexture = (void*)[device newTextureWithDescriptor:depthTexDesc];
      }
      // --------------------------------------------------

      // Create the command buffer
      id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];

      // Configure a render pass to clear the window color
      MTLRenderPassDescriptor* renderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
      renderPassDesc.colorAttachments[0].texture = drawable.texture;
      renderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
      // Vuron Dark Slate Blue background color : ClearColorMake(R, G, B, A)
      renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.14, 0.18, 1.0);
      renderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

      // Attaching the Depth canvas to the render pass
      renderPassDesc.depthAttachment.texture = (id<MTLTexture>)m_depthTexture;
      renderPassDesc.depthAttachment.loadAction = MTLLoadActionClear; // Clead old distances
      renderPassDesc.depthAttachment.clearDepth = 1.0; // Reset canvas to max dist (1)
      renderPassDesc.depthAttachment.storeAction = MTLStoreActionDontCare; // discard after drawing

      id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDesc];

      // New draw commands
      if (m_pipelineState && m_vertexBuffer) {
        // --=The Engine's Timepiece=--
        // Any static variable survives between frames. Because CVDisplayLink is locked to
        // the monitor's refresh rate, adding a fixed number here guarantees a smooth spin
        static float angle = 0.0f;
        angle += 0.02f;

        // 1. Defining the camera (once per frame) & Process Input
        // The static keyword ensures camera survives between frames
        static vuron::Camera camera;

        //--Applying Mouse Looking--
        // Mouse sensitivity
        float sensitivity = 0.005f;

        camera.yaw += m_mouseDeltaX * sensitivity;
        camera.pitch += m_mouseDeltaY * sensitivity;

        // Reset camera deltas so screen stops spinning upon mouse inaction
        m_mouseDeltaX = 0.0f;
        m_mouseDeltaY = 0.0f;

        // Adding bounds to the pitch so camera doesn't snap its neck
        if (camera.pitch > 1.5f) camera.pitch = 1.5f; // Max look down (about 85º)
        if (camera.pitch < -1.5f) camera.pitch = -1.5f; // Max look up (about the same)
        //---------------------

        // 2. Defining the entities(just saw the backrooms movie, ts wasn't really scary)
//         vuron::Transform cubes[8];
//
//         // --Original tumbling cubes--
//         // Cube 0 - Dead center, standard tumble
//         cubes[0].position = {0.0f, 0.0f, 0.0f};
//         cubes[0].rotation = {angle, angle * 0.7f, 0.0f};
//
//         // Cube 1 - Shifted left, spinning on Z and Y
//         cubes[1].position = {-2.0f, 0.0f, 0.0f};
//         cubes[1].rotation = {0.0f, angle, angle * 0.5f};
//
//         // Cube 2 - Shifted right, tumbling fast, and shrunk in half
//         cubes[2].position = {2.0f, 0.0f, 0.0f};
//         cubes[2].rotation = {angle * 2.0f, angle * 2.0f, 0.0f};
//         cubes[2].scale = {0.5f, 0.5f, 0.5f};
//         //----------------------------------
//
//         // The solid floor (index 3)
//         cubes[3].position = {0.0f, -2.5f, 0.0f};
//         cubes[3].rotation = {0.0f, 0.0f, 0.0f};
//         cubes[3].scale = {100.0f, 0.5f, 100.0f};
//
//         // The Staircase Ramp (indices 4, 5)
//         // Placed directly behind the center spinning cube
//         cubes[4].position = {0.0f, -1.75f, 4.0f};
//         cubes[4].rotation = {0.0f, 0.0f, 0.0f};
//         cubes[4].scale = {2.0f, 0.25f, 1.0f}; // First step
//
//         cubes[5].position = {0.0f, -1.25f, 6.0f};
//         cubes[5].rotation = {0.0f, 0.0f, 0.0f};
//         cubes[5].scale = {2.0f, 0.75f, 1.0f}; // Second, higher step
//
//         // Third step
//         cubes[6].position = {0.0f, -0.75f, 8.0f};
//         cubes[6].rotation = {0.0f, 0.0f, 0.0f};
//         cubes[6].scale = {2.0f, 1.25f, 1.0f};
//
//         // Fourth step
//         cubes[7].position = {0.0f, -0.25f, 10.0f};
//         cubes[7].rotation = {0.0f, 0.0f, 0.0f};
//         cubes[7].scale = {2.0f, 1.75f, 1.0f};


        // --= Tick Combo Timers =--
        if (m_wavedashWindow > 0) m_wavedashWindow--;
        if (m_jumpBuffer > 0) m_jumpBuffer--;


        // Tick the long jump hang time (approx 30 frames = 0.5s)
        if (m_boostHangTimer > 0)
        {
            m_boostHangTimer--;
            if (m_boostHangTimer == 0)
            {
                m_isBoosting = true; // Hang time is over, trigger decay
            }
        }
        // --------------------------

        // Initialize the level (Only runs on the very first frame)
        if (!m_levelLoaded) {
            // Loading from the text file
            m_cubes = vuron::LevelLoader::loadLevel("src/levels/test_arena.vlvl");
            m_levelLoaded = true;
        }

        // Update Geometry (dash) (2.2 when??)
        // We manually spin the first 3 cubes in our list
        m_cubes[0].rotation = {angle, angle * 0.7f, 0.0f};
        m_cubes[1].rotation = {0.0f, angle, angle * 0.5f};
        m_cubes[2].rotation = {angle * 2.0f, angle * 2.0f, 0.0f};

        // ===============================================
        // -= Unified Physics and Movement Engine =-
        // ===============================================
        float speed = 0.1f;
        // Trigonometry: Calculate exatly which way "Forwards" and "Right" are based on player's yaw
        float fwdX = std::sin(camera.yaw);
        float fwdZ = std::cos(camera.yaw);
        float rightX = std::cos(camera.yaw);
        float rightZ = -std::sin(camera.yaw);

        // -=Crouching and Anti-clip Logic=-
        bool wantCrouch = m_keyShift;

        if (wantCrouch && !camera.isCrouched) {
            // Initiate crouch
            camera.isCrouched = true;
            // Shift eyes down by 1 unit. Because hitbox moves down by 1.0,
            // The feet remain in the exact same physical location
            camera.position.y -= 0.5f;
            // Strict Rocket Lock: Only allow if crouching started midair
            if (!camera.isGrounded) {
                camera.crouchedMidAir = true;
            } else {
                // --= Wavedash Combo Logic =--
                bool isMoving = (m_activeX != 0 || m_activeZ != 0);

                if (isMoving) {

                    //Did they maintain the same directional input?
                    if (m_activeX == m_lastWavedashKeyX && m_activeZ == m_lastWavedashKeyZ) {

                        // Is the combo timer still alive?
                        if (m_wavedashWindow > 0) {
                            m_currentMomentum += 0.05f; // The wavedash burst
                            float wavedashCap = 0.5f; // Wavedash soft cap
                            if (m_currentMomentum > wavedashCap) m_currentMomentum = wavedashCap;
                        }
                    } else {
                        // The penalty; they pressed shift while changing directions on the ground
                        m_currentMomentum = 0.1f;
                    }

                    // Refresh the combo timer (approx 15 frames to execute the next crouch)
                    m_wavedashWindow = 15;

                    // Save current direction for the next dash check
                    m_lastWavedashKeyX = m_activeX;
                    m_lastWavedashKeyZ = m_activeZ;
                }
            }
        }
        else if (!wantCrouch && camera.isCrouched) {
            // Attempt uncrouch (anti-clip check)
            // We project a "Ghost box" representing what the player's hitbox would look like standing
            vuron::AABB ghostBox = {
                {camera.position.x - 0.5f, (camera.position.y + 0.5f) - 2.0f, camera.position.z - 0.5f},
                {camera.position.x + 0.5f, (camera.position.y + 0.5f) + 0.2f, camera.position.z + 0.5f}
            };

            bool ceilingClear = true;
            for (size_t i = 0; i < m_cubes.size(); ++i) {
                if (vuron::AABB::checkCollision(ghostBox, m_cubes[i].getHitbox())) {
                    ceilingClear = false; // Head hit something. Stay crouched
                    break;
                }
            }

            if (ceilingClear) {
                // Execute Uncrouch
                camera.isCrouched = false;
                camera.position.y += 0.5f; // Raise the eyes back up
            }
        }
        // --------------------------------

        // 1. Calculate intended horizontal movement
        float baseSpeed = 0.1f;
        float sprintCap = 0.5f; // Soft speed cap
        float absoluteCeiling = 1.0f; // Hard speed cap
        float acceleration = 0.0025f;

        bool isMoving = (m_activeX != 0 || m_activeZ != 0);

        // --- Long Jump decay phase ---
        if (m_isBoosting) {
            m_currentMomentum -= 0.015f; // Hemorrhaging speed here

            // Once it drops to 0.35f, the decay ends
            if (m_currentMomentum <= 0.35f) {
                m_currentMomentum = 0.35f;
                m_isBoosting = false;
            }
        }

        // --- Standard Coasting and Acceleration ---
        if (!isMoving) {
            // Player let go of the keyboard
            // Auto-cancel the toggle and kill momentum
            m_isAccelerating = false;
            m_currentMomentum = baseSpeed;
        } else {
            // Player is actively moving
            if (m_isAccelerating) {
                // Only accelerate below the soft cap
                if (m_currentMomentum < sprintCap) {
                    m_currentMomentum += acceleration;
                    if (m_currentMomentum > sprintCap) m_currentMomentum = sprintCap;
                }
            }
        }
        // -------------------------------------------

        // Hard cap safety net
        // Ensures the tech never breaks (hopefully)
        if (m_currentMomentum > absoluteCeiling) {
            m_currentMomentum = absoluteCeiling;
        }

        // Get raw directional inputs (-1, 0, or 1)
        float inputX = 0.0f;
        float inputZ = 0.0f;

        if (m_activeZ == 'w') inputZ = 1.0f;
        else if (m_activeZ == 's') inputZ = -1.0f;

        if (m_activeX == 'd') inputX = 1.0f;
        else if (m_activeX == 'a') inputX = -1.0f;

        // Vector Normalization (fix for the hypotenuse bug)
        float inputMag = std::sqrt(inputX * inputX + inputZ * inputZ);
        if (inputMag > 0.0f) {
            inputX /= inputMag;
            inputZ /= inputMag;
        }

        // Apply Trigonometry based on where the camera is looking
        float moveX = (inputZ * fwdX + inputX * rightX) * m_currentMomentum;
        float moveZ = (inputZ * fwdZ + inputX * rightZ) * m_currentMomentum;

        // 2. X-axis collision (Move, check, revert if hit)
        camera.position.x += moveX;
        for (size_t i = 0; i < m_cubes.size(); ++i) {
            if (vuron::AABB::checkCollision(camera.getHitbox(), m_cubes[i].getHitbox())) {
                camera.position.x -= moveX; // Wall hit. Slide along it instead
                m_currentMomentum = baseSpeed; // Wall slam penalty
                break;
            }
        }

        // 3. Z-axis collision (move, check, revert if hit)
        camera.position.z += moveZ;
        for (size_t i = 0; i < m_cubes.size(); ++i) {
            if (vuron::AABB::checkCollision(camera.getHitbox(), m_cubes[i].getHitbox())) {
                camera.position.z -= moveZ; // Wall hit
                m_currentMomentum = baseSpeed;// Wall slam penalty
                break;
            }
        }

        // 4. Gravity and Y-axis collision
        float baseGravity = -0.008f; // Standard falling speed
        float floatGravity = -0.002f; // Slowed fall while holding space
        float heavyGravity = -0.02f; // Aggressive falling cutting a jump short
        float jumpForce = 0.15f; // The upward burst
        float fastFallGravity = -0.025f; // Pulls you down when holding crouch

        float currentGravity = baseGravity;
        // Dynamic Gravity Calculator
        if (camera.velocityY > 0.0f && !m_keySpace) {
            // Player is moving up, but let go of space early
            currentGravity = heavyGravity;
        }
        else if (camera.velocityY < 0.0f && m_keyShift) {
            // Shift wins over space for fast falling
            currentGravity = fastFallGravity;
        }
        else if (camera.velocityY < 0.0f && m_keySpace) {
            // Player is falling down, but holding spacebar
            currentGravity = floatGravity;
        }

        // 1. Always apply gravity to our vertical velocity
        camera.velocityY += currentGravity;
        // 2. Apply the velocity to player's position
        camera.position.y += camera.velocityY;

        camera.isGrounded = false; // Reset the grounded state every frame to force proof

        vuron::AABB yHitbox = camera.getHitbox();
        yHitbox.min.x += 0.05f; yHitbox.max.x -= 0.05f;
        yHitbox.min.z += 0.05f; yHitbox.max.z -= 0.05f;

        // 3. Collision detection
        for (size_t i = 0; i < m_cubes.size(); ++i)
        {
            vuron::AABB cubeBox = m_cubes[i].getHitbox();
            if (vuron::AABB::checkCollision(yHitbox, cubeBox))
            {

                // Falling down into a surface (floor)
                if (camera.velocityY < 0.0f)
                {
                    float currentHeight = camera.isCrouched ? 1.5f : 2.0f;
                    // Snap the player's feet perfectly to the top of the cube
                    // +0.001f to prevent floating-point glitching
                    camera.position.y = cubeBox.max.y + currentHeight + 0.001f;
                    camera.velocityY = 0.0f;
                    camera.isGrounded = true;
                    camera.crouchedMidAir = false; // Reset midair strict lock when landing
                }
                // Jumping into a surface (ceiling)
                else if (camera.velocityY > 0.0f)
                {
                    // Snap player head to the bottom of the cube
                    camera.position.y = cubeBox.min.y - 0.201f;
                    camera.velocityY = 0.0f;
                }
                break;
            }
        }

        // ================================================
        // 4. Jump Execution (Relying purely on Geometrical physics)
        // ================================================

        // Always reset the physical key lock if the player let go of space
        if (!m_keySpace)
        {
            m_hasJumped = false;
        }

        // --- Rocket Jumping ---
        if (camera.isGrounded)
        {
            m_hasRocketJumped = false; // Reset the moment the feet touch the floor

            if ((m_keySpace && !m_hasJumped) || m_jumpBuffer > 0)
            {
                // --- Boost Boots (Long Jump) ---
                bool isMoving = (m_activeX != 0 || m_activeZ != 0);
                if (camera.isCrouched && isMoving)
                {
                    m_currentMomentum = 0.75f; // The velocity spike
                    m_boostHangTimer = 30;     // 30 frames of hang time
                    m_isBoosting = false;      // Ensure decay is off

                }

                camera.velocityY = jumpForce;
                m_hasJumped = true;
                m_jumpBuffer = 0; // Consume the buffer so no double trigger
            }
        } else {
            // -- Mid-air Logic --
            if (m_keySpace && !m_hasJumped)
            {
                // The player released and presses space again in midair
                float peakWindow = 0.08f; // How forgiving the apex timing is
                float rocketForce = 0.45f; // 3x the standard jump height

                // Condition 1: Are they holding Crouch?
                // Condition 2: Did they Initiate that crouch midair?
                // Condition 3: Have they not already RJumped?
                // Condition 4: Is their vertical velocity floating around 0.0f?
                if (camera.isCrouched && camera.crouchedMidAir && !m_hasRocketJumped &&
                    camera.velocityY <= peakWindow && camera.velocityY >= -peakWindow)
                    {
                        // Kaboom.
                        camera.velocityY = rocketForce;
                        m_hasRocketJumped = true; // Locking RJump
                        m_hasJumped = true;
                    }
                else
                {
                    // They missed the rocket jump
                    m_jumpBuffer = 10; // 10 frames ~ 0.166s
                    m_hasJumped = true; // Lock further midair inputs
                }
            }
        }
        // ================================================


        // ===========================================
        // -- 5. Debug Menu --
        // ===========================================
        static NSTextField* debugLabel = nil;

        // 1. Capture the exact variables we need
        bool showMenu = m_showDebugMenu;
        float px = camera.position.x;
        float py = camera.position.y;
        float pz = camera.position.z;
        float currentSpeed = m_currentMomentum;
        bool isAccel = m_isAccelerating;

        // 2. Throw the UI drawing logic over to the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if (showMenu) {
                // Lazy Initialization
                if (!debugLabel) {
                    NSWindow *window = [NSApp mainWindow];
                    if (!window) window = [NSApp keyWindow]; // Fallback if mainWindow isn't set yet
                    if (window) {
                        NSView*mainView = window.contentView;
                        debugLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(16, mainView.bounds.size.height - 120, 400, 100)];
                        [debugLabel setEditable:NO];
                        [debugLabel setSelectable:NO];
                        [debugLabel setDrawsBackground:NO];
                        [debugLabel setBordered:NO];
                        [debugLabel setWantsLayer:YES];
                        [debugLabel setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
                        [mainView addSubview:debugLabel];
                    }
                }

                if (debugLabel) {
                    [debugLabel setHidden:NO];

                    // BUild the core text block
                    NSString *text = [NSString stringWithFormat:@"X: %.2f\nY: %.2f\nZ: %.2f\nSpeed: %.3f\nAccel: ",
                                      px, py, pz, currentSpeed];

                    NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithString:text];
                    [attrStr addAttribute:NSForegroundColorAttributeName value:[NSColor whiteColor] range:NSMakeRange(0, text.length)];
                    [attrStr addAttribute:NSFontAttributeName value:[NSFont fontWithName:@"Menlo" size:14.0f] range:NSMakeRange(0, text.length)];

                    // Color-code Acceleration
                    NSString *stateText = m_isAccelerating ? @"ON" : @"OFF";
                    NSColor * stateColor = m_isAccelerating ? [NSColor greenColor] : [NSColor redColor];

                    NSAttributedString *stateStr = [[NSAttributedString alloc] initWithString:stateText
                        attributes:@{NSForegroundColorAttributeName: stateColor, NSFontAttributeName: [NSFont fontWithName:@"Menlo-Bold" size:14.0f]}];

                    [attrStr appendAttributedString:stateStr];
                    [debugLabel setAttributedStringValue:attrStr];
                }
            } else {
                // Instantly hide overlay if turned off
                if (debugLabel) {
                    [debugLabel setHidden:YES];
                }
            }
        });



        // Grab the inverse matrix to physically shift the universe around the player
        vuron::Matrix4x4 viewMatrix = camera.getViewMatrix();

        float screenW = (float)drawable.texture.width;
        float screenH = (float)drawable.texture.height > 0 ? (float)drawable.texture.height : 1.0f;
        vuron::Matrix4x4 projectionMatrix = vuron::Matrix4x4::perspectiveFixed(screenW, screenH, 1500.0f, 0.1f, 100.0f);


        // 3. Prepping the GPU Pipeline
        [encoder setRenderPipelineState:(id<MTLRenderPipelineState>)m_pipelineState];
        [encoder setVertexBuffer:(id<MTLBuffer>)m_vertexBuffer offset:0 atIndex:0];
        [encoder setDepthStencilState:(id<MTLDepthStencilState>)m_depthStencilState];

        // 4. The Rendering loop (every entity drawn independently)
        for (size_t i = 0; i < m_cubes.size(); ++i) {

            // Calculate this specific cube's final matrix
            vuron::Matrix4x4 modelMatrix = m_cubes[i].getModelMatrix();
            vuron::Matrix4x4 mvpMatrix = modelMatrix * viewMatrix * projectionMatrix;

            // Inject the matrix directly into GPU Register slot 1
            [encoder setVertexBytes:&mvpMatrix length:sizeof(vuron::Matrix4x4) atIndex:1];

            // Execute the draw using the map, connecting the dots
            [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                indexCount:36
                                indexType:MTLIndexTypeUInt16
                                indexBuffer:(id<MTLBuffer>)m_indexBuffer
                                indexBufferOffset:0];

        }
      }

      [encoder endEncoding];
      [commandBuffer presentDrawable:drawable];
      [commandBuffer commit];
    }
}

    void MetalRenderer::shutdown() {
      m_metalLayer = nullptr;
      m_device = nullptr;
      m_commandQueue = nullptr;
    }
}