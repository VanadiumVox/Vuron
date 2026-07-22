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
    void MetalRenderer::addMouseDelta(float dx, float dy)
    {
        m_mouseDeltaX += dx;
        m_mouseDeltaY += dy;
    }

    // -=Mouse Click bridge=-
    void MetalRenderer::setMouseState(bool isPressed)
    {
        if (isPressed && !m_mouseLeftDown)
        {
            m_mouseJustClicked = true; // Captures the frame it was clicked
        }
        m_mouseLeftDown = isPressed;
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
      // --- Enabling Transparency Blending (for shadow) ---
      pipelineDesc.colorAttachments[0].blendingEnabled = YES;
      pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
      pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
      // ---------------------------------------------------
      // Tell the pipeline to expect 32-bit Float depth math
      pipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

      // Baking the pipeline descriptor into the GPUs memory
      id<MTLRenderPipelineState> pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
      if (!pipelineState) {
        std::cerr << "Pipeline error: " << [[error localizedDescription] UTF8String] << std::endl;
        return false;
      }
      m_pipelineState = (void*)pipelineState;

      // -= UI Pipeline (Color Inversion) =-
      // Changing the math to: 1.0 * (1.0 - destinationColor) + destinationColor * 0.0 = invertedColor
      pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOneMinusDestinationColor;
      pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorZero;

      id<MTLRenderPipelineState> uiState = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
      if (!uiState)
      {
        NSLog(@"Failed to create UI pipeline state: %@", error);
      }
      m_uiPipelineState = (void*)uiState;

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
//         vuron::Vertex cubeVertices[] = {
//         // Front face (z = -0.5)
//         {{-0.5f,  0.5f, -0.5f}, {1.0f, 0.0f, 0.0f}}, // 0: Top Left (Red)
//         {{ 0.5f,  0.5f, -0.5f}, {0.0f, 1.0f, 0.0f}}, // 1: Top Right (Green)
//         {{-0.5f, -0.5f, -0.5f}, {0.0f, 0.0f, 1.0f}}, // 2: Bottom Left (Blue)
//         {{ 0.5f, -0.5f, -0.5f}, {1.0f, 1.0f, 0.0f}}, // 3: Bottom Right (Yellow)
//         // Back face (z = 0.5)
//         {{-0.5f,  0.5f,  0.5f}, {1.0f, 0.0f, 1.0f}}, // 4: Top Left (Magenta)
//         {{ 0.5f,  0.5f,  0.5f}, {0.0f, 1.0f, 1.0f}}, // 5: Top Right (Cyan)
//         {{-0.5f, -0.5f,  0.5f}, {1.0f, 1.0f, 1.0f}}, // 6: Bottom Left (White)
//         {{ 0.5f, -0.5f,  0.5f}, {0.0f, 0.0f, 0.0f}}, // 7: Bottom Right (Black)
//         };
//
//         uint16_t cubeIndices[] = {
//         0, 2, 1,  1, 2, 3, // Front
//         1, 3, 5,  5, 3, 7, // Right
//         5, 7, 4,  4, 7, 6, // Back
//         4, 6, 0,  0, 6, 2, // Left
//         4, 0, 5,  5, 0, 1, // Top
//         2, 6, 3,  3, 6, 7  // Bottom
//         };


       // --- Creating the Shapes for Vuron ---
       vuron::Vertex allVertices[] =
       {
             // --- CUBE (Vertices 0-7) ---
             {{-0.5f,  0.5f, -0.5f}, {1.0f, 0.0f, 0.0f}}, // 0: Top Left (Red)
             {{ 0.5f,  0.5f, -0.5f}, {0.0f, 1.0f, 0.0f}}, // 1: Top Right (Green)
             {{-0.5f, -0.5f, -0.5f}, {0.0f, 0.0f, 1.0f}}, // 2: Bottom Left (Blue)
             {{ 0.5f, -0.5f, -0.5f}, {1.0f, 1.0f, 0.0f}}, // 3: Bottom Right (Yellow)
             {{-0.5f,  0.5f,  0.5f}, {1.0f, 0.0f, 1.0f}}, // 4: Top Left Back (Magenta)
             {{ 0.5f,  0.5f,  0.5f}, {0.0f, 1.0f, 1.0f}}, // 5: Top Right Back (Cyan)
             {{-0.5f, -0.5f,  0.5f}, {1.0f, 1.0f, 1.0f}}, // 6: Bottom Left Back (White)
             {{ 0.5f, -0.5f,  0.5f}, {0.0f, 0.0f, 0.0f}}, // 7: Bottom Right Back (Black)

             // --- WEDGE (Vertices 8-13) ---
             // A Wedge tall at the front (-z) and flat at the back (+z), matching our Up/Forward normal
             {{-0.5f, -0.5f, -0.5f}, {1.0f, 0.0f, 0.0f}}, // 8: Bottom Left Front
             {{ 0.5f, -0.5f, -0.5f}, {0.0f, 1.0f, 0.0f}}, // 9: Bottom Right Front
             {{-0.5f, -0.5f,  0.5f}, {0.0f, 0.0f, 1.0f}}, // 10: Bottom Left Back (The thin tip)
             {{ 0.5f, -0.5f,  0.5f}, {1.0f, 1.0f, 0.0f}}, // 11: Bottom Right Back (The thin tip)
             {{-0.5f,  0.5f, -0.5f}, {1.0f, 0.0f, 1.0f}}, // 12: Top Left Front (The high wall)
             {{ 0.5f,  0.5f, -0.5f}, {0.0f, 1.0f, 1.0f}},  // 13: Top Right Front (The high wall)

             // --- Shadow Quad (Vertices 14-17) ---
             {{-0.5f, 0.0f, -0.5f}, {0.0f, 0.0f, 0.0f}},
             {{ 0.5f, 0.0f, -0.5f}, {0.0f, 0.0f, 0.0f}},
             {{-0.5f, 0.0f,  0.5f}, {0.0f, 0.0f, 0.0f}},
             {{ 0.5f, 0.0f,  0.5f}, {0.0f, 0.0f, 0.0f}},

             // --- CROSSHAIR QUAD (Vertices 18-21) ---
             // A flat square facing the screen (using X and Y axes)
             {{-0.5f, -0.5f, 0.0f}, {1.0f, 1.0f, 1.0f}},
             {{ 0.5f, -0.5f, 0.0f}, {1.0f, 1.0f, 1.0f}},
             {{-0.5f,  0.5f, 0.0f}, {1.0f, 1.0f, 1.0f}},
             {{ 0.5f,  0.5f, 0.0f}, {1.0f, 1.0f, 1.0f}},

             // --- GREEN VISUAL BOX (Vertices 22-29) ---
             {{-0.5f,  0.5f, -0.5f}, {0.0f, 1.0f, 0.0f}},
             {{ 0.5f,  0.5f, -0.5f}, {0.0f, 1.0f, 0.0f}},
             {{-0.5f, -0.5f, -0.5f}, {0.0f, 1.0f, 0.0f}},
             {{ 0.5f, -0.5f, -0.5f}, {0.0f, 1.0f, 0.0f}},
             {{-0.5f,  0.5f,  0.5f}, {0.0f, 1.0f, 0.0f}},
             {{ 0.5f,  0.5f,  0.5f}, {0.0f, 1.0f, 0.0f}},
             {{-0.5f, -0.5f,  0.5f}, {0.0f, 1.0f, 0.0f}},
             {{ 0.5f, -0.5f,  0.5f}, {0.0f, 1.0f, 0.0f}},

             // --- RED PHYSICAL BOX (Vertices 30-37) ---
             {{-0.5f,  0.5f, -0.5f}, {1.0f, 0.0f, 0.0f}},
             {{ 0.5f,  0.5f, -0.5f}, {1.0f, 0.0f, 0.0f}},
             {{-0.5f, -0.5f, -0.5f}, {1.0f, 0.0f, 0.0f}},
             {{ 0.5f, -0.5f, -0.5f}, {1.0f, 0.0f, 0.0f}},
             {{-0.5f,  0.5f,  0.5f}, {1.0f, 0.0f, 0.0f}},
             {{ 0.5f,  0.5f,  0.5f}, {1.0f, 0.0f, 0.0f}},
             {{-0.5f, -0.5f,  0.5f}, {1.0f, 0.0f, 0.0f}},
             {{ 0.5f, -0.5f,  0.5f}, {1.0f, 0.0f, 0.0f}}
       };

       uint16_t allIndices[] =
       {
           // --- CUBE INDICES (0 to 35) ---
           0, 2, 1,  1, 2, 3, // Front
           1, 3, 5,  5, 3, 7, // Right
           5, 7, 4,  4, 7, 6, // Back
           4, 6, 0,  0, 6, 2, // Left
           4, 0, 5,  5, 0, 1, // Top
           2, 6, 3,  3, 6, 7, // Bottom

           // --- WEDGE INDICES (36 to 59) ---
           12, 8, 13,   13, 8, 9,    // Front Wall (Flat)
           8, 10, 9,    9, 10, 11,   // Bottom Floor (Flat)
           12, 13, 10,  13, 11, 10,  // Sloped Top Face (The Ramp itself)
           12, 10, 8,                // Left Triangle
           13, 9, 11,                 // Right Triangle

           // --- Shadow Indices (60 to 65) ---
           14, 16, 15,  15, 16, 17,

           // --- Crosshair Indices (66 to 71) ---
           18, 20, 19,  19, 20, 21,

           // --- Green Visual Wireframe (72 to 95) ---
           22,23, 23,25, 25,24, 24,22, // Front
           26,27, 27,29, 29,28, 28,26, // Back
           22,26, 23,27, 24,28, 25,29, // Connections

           // --- Red Physical Wireframe (96 to 119) ---
           30,31, 31,33, 33,32, 32,30, // Front
           34,35, 35,37, 37,36, 36,34, // Back
           30,34, 31,35, 32,36, 33,37  // Connections
       };


      // 1. Sending 14 points to the GPU
      id<MTLBuffer> vertexBuffer = [device newBufferWithBytes:allVertices
                                    length:(sizeof(vuron::Vertex) * 38)
                                    options:MTLResourceStorageModeShared];
      m_vertexBuffer = (void*)vertexBuffer;

      //2. Sending instruction map to the GPU
      id<MTLBuffer> indexBuffer = [device newBufferWithBytes:allIndices
                                    length:(sizeof(uint16_t) * 120)
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

        // --- The Grappling Hook logic (yeah, I know, it's weird up here too but makes sense) ---
        // Inputs are consumed instantly, no queues
        if (m_mouseJustClicked)
        {
            m_mouseJustClicked = false; // Consume the click

            if (!camera.isGrappling)
            {
                // Deny firing midair if no charges left
                if (!camera.isGrounded && camera.currentAirGrapples <= 0)
                {
                    // Do nothing
                }
                else
                {
                    // Generate a ray from the player's eye, shooting straight forward.
                    vuron::Ray grappleRay = { camera.position, camera.getForwardVector() };

                    float closestHit = 9999.0f;
                    int hitTarget = -1;

                    // Scan the world to find the closest pierce point
                    for (size_t i = 0; i < m_cubes.size(); ++i)
                    {
                        float hitDistance = grappleRay.intersectsOBB(m_cubes[i]);

                        // Valid hit must be in front of camera.
                        if (hitDistance > 0.1f && hitDistance < closestHit)
                        {
                            closestHit = hitDistance;
                            hitTarget = (int)i;
                        }
                    }

                    // Locking the state machine
                    if (hitTarget != -1)
                    {
                        camera.isGrappling = true;
                        camera.hookedEntityIndex = hitTarget;

                        // Projecting the ray endpoints to get the final coordinate
                        camera.grapplePoint =
                        {
                            grappleRay.origin.x + (grappleRay.direction.x * closestHit),
                            grappleRay.origin.y + (grappleRay.direction.y * closestHit),
                            grappleRay.origin.z + (grappleRay.direction.z * closestHit)
                        };

                        // Midair use consumes an air charge
                        if (!camera.isGrounded)
                        {
                            camera.currentAirGrapples--;
                        }
                    }
                }
            }
            else
            {
                // if already grappling, a second click detaches
                camera.isGrappling = false;
            }
        }

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
            for (size_t i = 0; i < m_cubes.size(); ++i)
            {
                if (vuron::AABB::checkCollision(ghostBox, m_cubes[i].getHitbox()))
                {
                    if (m_cubes[i].type == vuron::ShapeType::CUBE)
                    {
                        ceilingClear = false; // Hit ceiling
                        break;
                    }
                    else if (m_cubes[i].type == vuron::ShapeType::WEDGE)
                    {
                        // Calculate the slope height at the ghost box's position
                        float ny = m_cubes[i].normal.y == 0.0f ? 0.0001f : m_cubes[i].normal.y;
                        float slopeH = m_cubes[i].position.y - ((m_cubes[i].normal.x * (camera.position.x - m_cubes[i].position.x) + m_cubes[i].normal.z * (camera.position.z - m_cubes[i].position.z)) / ny);

                        // If our head is below the slanted roof, we are trapped
                        if (ghostBox.max.y < slopeH)
                        {
                            ceilingClear = false;
                            break;
                        }
                    }
                }
            }

            if (ceilingClear) {
                // Execute Uncrouch
                camera.isCrouched = false;
                camera.position.y += 0.5f; // Raise the eyes back up
            }
        }
        // --------------------------------

        // ==============================================
        // -= 1. Intended Movement & Directional Math =-
        // ==============================================
        float baseSpeed = 0.1f;
        float sprintCap = 0.5f;
        float absoluteCeiling = 1.0f;
        float acceleration = 0.0025f;

        bool isMoving = (m_activeX != 0 || m_activeZ != 0);

        // -- Long Jump Decay Phase --
        if (m_isBoosting)
        {
            m_currentMomentum -= 0.015f;
            if (m_currentMomentum <= 0.35f)
            {
                m_currentMomentum = 0.35f;
                m_isBoosting = false;
            }
        }

        // -- Standard Coasting and Acceleration --
        else if (!isMoving)
        {
            m_isAccelerating = false;
            m_currentMomentum = baseSpeed;
        }
        else
        {
            if (m_isAccelerating && m_currentMomentum < sprintCap)
            {
                m_currentMomentum += acceleration;
                if (m_currentMomentum > sprintCap) m_currentMomentum = sprintCap;
            }
        }

        if (m_currentMomentum > absoluteCeiling) m_currentMomentum = absoluteCeiling;

        // Get raw directional inputs (-1, 0, or 1)
        float inputX = 0.0f;
        float inputZ = 0.0f;
        if (m_activeZ == 'w') inputZ = 1.0f;
        else if (m_activeZ == 's') inputZ = -1.0f;
        if (m_activeX == 'd') inputX = 1.0f;
        else if (m_activeX == 'a') inputX = -1.0f;

        // 1. Calculate the pure intended direction
        float targetDirX = (inputZ * fwdX + inputX * rightX);
        float targetDirZ = (inputZ * fwdZ + inputX * rightZ);

        float dirMag = std::sqrt(targetDirX * targetDirX + targetDirZ * targetDirZ);
        if (dirMag > 0.0f)
        {
            targetDirX /= dirMag;
            targetDirZ /= dirMag;
        }

        // 2. Apply the throttle (momentum is preserved)
        float moveX = targetDirX * m_currentMomentum;
        float moveZ = targetDirZ * m_currentMomentum;

        // =============================================
        //  -= 2. Gravity Calculations =-
        // =============================================
        float baseGravity = -0.008f;
        float floatGravity = -0.002f;
        float heavyGravity = -0.02f;
        float jumpForce = 0.15f;
        float fastFallGravity = -0.025f;

        float currentGravity = baseGravity;
        if (camera.velocity.y > 0.0f && !m_keySpace) currentGravity = heavyGravity;
        else if (camera.velocity.y < 0.0f && m_keyShift) currentGravity = fastFallGravity;
        else if (camera.velocity.y < 0.0f && m_keySpace) currentGravity = floatGravity;

        camera.velocity.y += currentGravity;

        // ===================================================
        // -= 3. Unified Vector Physics & Clipping =-
        // ===================================================

        // --- Pendulum Math & Tension ---
        // 1. Combining intent with velocity to get momentum
        float totalVx = moveX + camera.velocity.x;
        float totalVy = camera.velocity.y;
        float totalVz = moveZ + camera.velocity.z;

        if (camera.isGrappling)
        {
            // Camera 3D Vector to the hook point
            float dx = camera.grapplePoint.x - camera.position.x;
            float dy = camera.grapplePoint.y - camera.position.y;
            float dz = camera.grapplePoint.z - camera.position.z;

            // Pythagoras (my math teacher was right.)
            float distance = std::sqrt(dx*dx + dy*dy + dz*dz);

            if (distance > 0.0f)
            {
                // Normalize the direction to the hook
                float nx = dx / distance;
                float ny = dy / distance;
                float nz = dz / distance;

                if (camera.isGrounded && ny > 0.1f)
                {
                    totalVy += 0.08f;
                    camera.isGrounded = false;
                }

                // 2. Tension: Project velocity to delete movement away from the pivot
                float velocityAway = (totalVx * -nx) + (totalVy * -ny) + (totalVz * -nz);

                if (velocityAway > 0)
                {
                    totalVx += nx * velocityAway;
                    totalVy += ny * velocityAway;
                    totalVz += nz * velocityAway;
                }

                // Radius-based dampening
                if (distance < 4.0f)
                {
                    // Dampen curve: 0.0 (center) to 1.0 (edge of deadzone)
                    float dampen = distance / 4.0f;
                    // Heavily multiply the velocity by smaller numbers as you aproach the point
                    float friction = 0.85f + (0.10f * dampen);

                    totalVx *= friction;
                    totalVy *= friction;
                    totalVz *= friction;
                }
                else
                {
                    // Standard air resistance for larger, wider swings
                    totalVx *= 0.995f;
                    totalVy *= 0.995f;
                    totalVz *= 0.995f;
                }

                // 3. The auto-retract (towards the anchor point)
                float retractSpeed = 0.05f;
                totalVx += nx * retractSpeed;
                totalVy += ny * retractSpeed;
                totalVz += nz * retractSpeed;

                // Dampening swing more since holding space fuckin launches ya
//                 float maxSwingHeight = 0.22f;
//                 if (totalVy > maxSwingHeight)
//                 {
//                     totalVy = maxSwingHeight;
//                 }
            }

            // 4. Extract the orbital physics back out to separate it from WASD movement
            camera.velocity.x = totalVx - moveX;
            camera.velocity.y = totalVy;
            camera.velocity.z = totalVz - moveZ;
        }
        else
        {
            // Air friction: If we aren't grappling, slowly decay existing orbital momentum
            camera.velocity.x *= 0.95f;
            camera.velocity.z *= 0.95f;

            // Recalculating the totals using the decayed momentum
            totalVx = moveX + camera.velocity.x;
            totalVz = moveZ + camera.velocity.z;
        }

        // ----------------------------------------------------

        // Apply everything to the final velocity vector
        vuron::Vector3 vel = {totalVx, camera.velocity.y, totalVz};
        float currentHeight = camera.isCrouched ? 1.5f : 2.0f;
        camera.isGrounded = false;

        // -- Flat Geometry Pass (X & Z)

        // X-Axis
        camera.position.x += vel.x;
        vuron::AABB xBox = camera.getHitbox();
        // Lift the feet slightly so we glide over floor polygons instead of snagging
        xBox.min.y += 0.05f; xBox.max.y -= 0.05f;
        for (size_t i = 0; i < m_cubes.size(); ++i)
        {
            if (vuron::AABB::checkCollision(xBox, m_cubes[i].getHitbox()))
            {
                if (m_cubes[i].type == vuron::ShapeType::CUBE)
                {
                    camera.position.x -= vel.x; vel.x = 0.0f; break;
                }
                else if (m_cubes[i].type == vuron::ShapeType::WEDGE)
                {
                    float ny = m_cubes[i].normal.y == 0.0f ? 0.0001f : m_cubes[i].normal.y;
                    float slopeH = m_cubes[i].position.y - ((m_cubes[i].normal.x * (camera.position.x - m_cubes[i].position.x) + m_cubes[i].normal.z * (camera.position.z - m_cubes[i].position.z)) / ny);
                    // If we are below the slope surface, we hit a solid wall
                    if (camera.position.y - currentHeight < slopeH - 1.5f)
                    {
                        camera.position.x -= vel.x; vel.x = 0.0f; break;
                    }
                }
            }
        }

        // Z-Axis
        camera.position.z += vel.z;
        vuron::AABB zBox = camera.getHitbox();
        // Lift feet to glide over floors, yadda yaddda
        zBox.min.y += 0.05f; zBox.max.y -= 0.05f;
        for (size_t i = 0; i < m_cubes.size(); ++i)
        {
            if (vuron::AABB::checkCollision(zBox, m_cubes[i].getHitbox()))
            {
                if (m_cubes[i].type == vuron::ShapeType::CUBE)
                {
                    camera.position.z -= vel.z; vel.z = 0.0f; break;
                }
                else if (m_cubes[i].type == vuron::ShapeType::WEDGE)
                {
                    float ny = m_cubes[i].normal.y == 0.0f ? 0.0001f : m_cubes[i].normal.y;
                    float slopeH = m_cubes[i].position.y - ((m_cubes[i].normal.x * (camera.position.x - m_cubes[i].position.x) + m_cubes[i].normal.z * (camera.position.z - m_cubes[i].position.z)) / ny);
                    // If we are below the slope surface, we hit a solid wall
                    if (camera.position.y - currentHeight < slopeH - 0.1f)
                    {
                        camera.position.z -= vel.z; vel.z = 0.0f; break;
                    }
                }
            }
        }

        // -- Y-Axis Pass (Gravity & Floors) --
        camera.position.y += vel.y;
        for (size_t i = 0; i < m_cubes.size(); ++i)
        {
            if (m_cubes[i].type != vuron::ShapeType::WEDGE && vuron::AABB::checkCollision(camera.getHitbox(), m_cubes[i].getHitbox()))
            {
                if (vel.y < 0.0f) // Floor
                {
                    camera.position.y = m_cubes[i].getHitbox().max.y + currentHeight + 0.001f;
                    camera.isGrounded = true;
                    camera.currentAirGrapples = camera.maxAirGrapples;
                    camera.crouchedMidAir = false;

                    // Geometry Cleanup
                    // Friction: Stops infinite sliding, but doesn't force-detach the grapple
                    camera.velocity.x *= 0.5f;
                    camera.velocity.z *= 0.5f;
                }
                else if (vel.y > 0.0f) // Ceiling
                {
                    camera.position.y = m_cubes[i].getHitbox().min.y - 0.201f;
                }
                vel.y = 0.0f;
                break;
            }
        }

        // -- Wedge Pass --
        for (size_t i = 0; i < m_cubes.size(); ++i)
        {
            if (m_cubes[i].type == vuron::ShapeType::WEDGE)
            {
                // Broad phase: is player anywhere near the bounding box?
                if (vuron::AABB::checkCollision(camera.getHitbox(), m_cubes[i].getHitbox()))
                {
                    float cx = m_cubes[i].position.x;
                    float cy = m_cubes[i].position.y;
                    float cz = m_cubes[i].position.z;
                    float nx = m_cubes[i].normal.x;
                    float ny = m_cubes[i].normal.y;
                    float nz = m_cubes[i].normal.z;

                    if (ny == 0.0f) ny = 0.0001f; // Prevent div by 0

                    float playerFeetY = camera.position.y - currentHeight;

                    // Narrow phase: the plane equation
                    // Calculate exact y height of the slope at player's coordinates
                    float slopeHeight = cy - ((nx * (camera.position.x - cx) + nz * (camera.position.z - cz)) / ny);

                    // If our feet clip the slanted face of the wedge but we aren't deeply beneath it
                    if (playerFeetY < slopeHeight && playerFeetY > slopeHeight - 1.5f)
                    {
                        // 1. Push the player up so they rest on the surface
                        camera.position.y = slopeHeight + currentHeight + 0.001f;

                        // 2. The vector clip
                        float impact = vuron::dot(vel, m_cubes[i].normal);

                        if (impact < 0.0f) // Moving into the slope
                        {
                            // Calculate the push-back vectors
                            float pushX = -(m_cubes[i].normal.x * impact);
                            float pushY = -(m_cubes[i].normal.y * impact);
                            float pushZ = -(m_cubes[i].normal.z * impact);

                            vel.x += pushX;
                            vel.y += pushY;
                            vel.z += pushZ;

                            // Physically slide the player
                            camera.position.x += pushX;
                            camera.position.z += pushZ;
                        }

                        // Ground the player if the slope is flat enough
                        if (ny > 0.7f)
                        {
                            camera.isGrounded = true;
                            camera.crouchedMidAir = false;

                            // FIX: Restore air charges when landing on a ramp
                            camera.currentAirGrapples = camera.maxAirGrapples;
                        }
                    }
                }
            }
        }

        // =================================================
        // -= 4. Decouple Throttle from Physics =-
        // =================================================
        float survivingSpeed = std::sqrt(vel.x * vel.x + vel.z * vel.z); // Y-axis strictly not here

        // If the player moved into a flat wall and was completely stopped on both axes
        if (survivingSpeed == 0.0f && isMoving)
        {
            m_currentMomentum = baseSpeed;
        }

        // Otherwise, leave m_currentMomentum along. Don't let wall friction shrink the throttle.baseSpeed

        camera.velocity.y = vel.y;


        // ===================================================================
        //  -= 5. Jump Execution (Relying purely on Geometrical physics) =-
        // ===================================================================

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

                camera.velocity.y = jumpForce;
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
                    camera.velocity.y <= peakWindow && camera.velocity.y >= -peakWindow)
                    {
                        // Kaboom.
                        camera.velocity.y = rocketForce;
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


        // Grab the inverse matrix to physically shift the universe around the player
        vuron::Matrix4x4 viewMatrix = camera.getViewMatrix();

        float screenW = (float)drawable.texture.width;
        float screenH = (float)drawable.texture.height > 0 ? (float)drawable.texture.height : 1.0f;
        vuron::Matrix4x4 projectionMatrix = vuron::Matrix4x4::perspectiveFixed(screenW, screenH, 1500.0f, 0.1f, 200.0f);


        // 3. Prepping the GPU Pipeline
        [encoder setRenderPipelineState:(id<MTLRenderPipelineState>)m_pipelineState];
        [encoder setVertexBuffer:(id<MTLBuffer>)m_vertexBuffer offset:0 atIndex:0];
        [encoder setDepthStencilState:(id<MTLDepthStencilState>)m_depthStencilState];

        // Ensure normal geometry draws completely solid
        float solidAlpha = 1.0f;
        [encoder setFragmentBytes:&solidAlpha length:sizeof(float) atIndex:2];

        // =============================================================
        // --- Shadow Drop Cast Algorithm ---
        // =============================================================
        float shadowY = -9999.0f;
        vuron::Vector3 shadowRot = {0.0f, 0.0f, 0.0f};
        bool shadowOnWedge = false;
        bool drawShadow = false;

        // Shoot a line straight down to find the highest floor beneath us
        for (size_t i = 0; i < m_cubes.size(); ++i)
        {
            vuron::AABB box = m_cubes[i].getHitbox();

            // Check if our X/Z coords are hovering over this specific objext
            if (camera.position.x >= box.min.x && camera.position.x <= box.max.x &&
                camera.position.z >= box.min.z && camera.position.z <= box.max.z)
                {
                    float testY = -9999.0f;

                    if (m_cubes[i].type == vuron::ShapeType::CUBE)
                    {
                        testY = box.max.y; // Flat roof
                    }
                    else if (m_cubes[i].type == vuron::ShapeType::WEDGE)
                    {
                        // Sloped roof. Calculate the exact plane height
                        float ny = m_cubes[i].normal.y == 0.0f ? 0.0001f : m_cubes[i].normal.y;
                        testY = m_cubes[i].position.y - ((m_cubes[i].normal.x * (camera.position.x - m_cubes[i].position.x) + m_cubes[i].normal.z * (camera.position.z - m_cubes[i].position.z)) / ny);
                    }

                    // If this object is below us & it's higher than the last floor we checked
                    if (testY <= camera.position.y && testY > shadowY)
                    {
                        shadowY = testY;
                        shadowRot = m_cubes[i].rotation; // Steal the geometry's exact rotation
                        shadowOnWedge = (m_cubes[i].type == vuron::ShapeType::WEDGE);
                    }
                }
        }

        // Optimization: Only draw if the floor is within 100 units
        if (camera.position.y - shadowY <= 200.0f && shadowY != -9999.0f)
        if (camera.position.y - shadowY <= 200.0f && shadowY != -9999.0f)
        {
            drawShadow = true;
        }

        // ===========================================================


        // ========================================
        // -- Frustum Culling Algorithm --
        // ========================================
        // Generate the view-projection matrix once, and extract the 6 vision planes
        vuron::Matrix4x4 viewProj = viewMatrix * projectionMatrix;
        vuron::Frustum camFrustum = vuron::Frustum::extract(viewProj);

        int renderedObjectCount = 0; // Keep track of how many objects on screen

        // 4. The Rendering loop (every entity drawn independently)
        for (size_t i = 0; i < m_cubes.size(); ++i) {

            // Check if the object is visible BEFORE the math
            if (!m_cubes[i].getHitbox().isOnScreen(camFrustum))
            {
                continue; // Skip the object entirely
            }

            renderedObjectCount++; // Increment if on screen

            // Calculate this specific cube's final matrix
            vuron::Matrix4x4 modelMatrix = m_cubes[i].getModelMatrix();
            vuron::Matrix4x4 mvpMatrix = modelMatrix * viewProj;

            // Inject the matrix directly into GPU Register slot 1
            [encoder setVertexBytes:&mvpMatrix length:sizeof(vuron::Matrix4x4) atIndex:1];

            if (m_cubes[i].type == vuron::ShapeType::CUBE)
            {
                // Execute the draw using the map, connecting the dots
                [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                    indexCount:36
                                    indexType:MTLIndexTypeUInt16
                                    indexBuffer:(id<MTLBuffer>)m_indexBuffer
                                    indexBufferOffset:0];
            }
            else if (m_cubes[i].type == vuron::ShapeType::WEDGE)
            {
                // Offset by exactly 72 bytes (36 cube indices * 2 bytes each()
                [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                indexCount:24
                                indexType:MTLIndexTypeUInt16
                                indexBuffer:(id<MTLBuffer>)m_indexBuffer
                                indexBufferOffset:72];
            }
        }

        // ===========================================
        // 4.5 Draw Bounding box Wireframe
        // ===========================================
        if (m_showBoundingBoxes)
        {
            for (size_t i = 0; i < m_cubes.size(); ++i)
            {
                // Ignore culled objects
                if (!m_cubes[i].getHitbox().isOnScreen(camFrustum)) continue;

                // 1. Visual Bounding box (Green)
                // Represents the exact transformation applied
                vuron::Matrix4x4 visualModel = m_cubes[i].getModelMatrix();
                vuron::Matrix4x4 visualMVP = visualModel * viewProj;

                [encoder setVertexBytes:&visualMVP length:sizeof(vuron::Matrix4x4) atIndex:1];
                [encoder drawIndexedPrimitives:MTLPrimitiveTypeLine
                                    indexCount:24
                                    indexType: MTLIndexTypeUInt16
                                    indexBuffer:(id<MTLBuffer>)m_indexBuffer
                                    indexBufferOffset:144]; // offset exactly by 144 (72 indices * 2)

                // 2. Physical Hitbox (Red)
                // represents the raw AABB.
                vuron::AABB box = m_cubes[i].getHitbox();

                // Calculate AABB center and exact physical span
                float cx = (box.min.x + box.max.x) * 0.5f;
                float cy = (box.min.y + box.max.y) * 0.5f;
                float cz = (box.min.z + box.max.z) * 0.5f;
                float sx = box.max.x - box.min.x;
                float sy = box.max.y - box.min.y;
                float sz = box.max.z - box.min.z;

                // Consturct a raw translation/scale matrix, with 0 rotation
                vuron::Matrix4x4 physModel = vuron::Matrix4x4::scale(sx, sy, sz) * vuron::Matrix4x4::translation(cx, cy, cz);
                vuron::Matrix4x4 physMVP = physModel * viewProj;

                [encoder setVertexBytes:&physMVP length:sizeof(vuron::Matrix4x4) atIndex:1];
                [encoder drawIndexedPrimitives:MTLPrimitiveTypeLine
                                    indexCount:24
                                    indexType: MTLIndexTypeUInt16
                                    indexBuffer:(id<MTLBuffer>)m_indexBuffer
                                    indexBufferOffset:192]; // Offset at 192 (96 indices * 2)
            }
        }
        // ===========================================

        // 5. Draw the Shadow (on top of the rest)
        if (drawShadow)
        {
            // Flip the swithc in the Fragment shader to activate transparency & circle math
            float shadowAlpha = 0.5f;
            [encoder setFragmentBytes:&shadowAlpha length:sizeof(float) atIndex:2];

            // Build the shadow matrix manually
            vuron::Matrix4x4 intrinsicRot = vuron::Matrix4x4::rotationX(shadowOnWedge ? -0.785398f : 0.0f);
            vuron::Matrix4x4 rx = vuron::Matrix4x4::rotationX(shadowRot.x);
            vuron::Matrix4x4 ry = vuron::Matrix4x4::rotationY(shadowRot.y);
            vuron::Matrix4x4 rz = vuron::Matrix4x4::rotationZ(shadowRot.z);
            // Snap it to exactly 0.01f units above the floor
            vuron::Matrix4x4 t = vuron::Matrix4x4::translation(camera.position.x, shadowY + 0.01f, camera.position.z);

            vuron::Matrix4x4 shadowMVP = intrinsicRot * rx * ry * rz * t * viewMatrix * projectionMatrix;

            [encoder setVertexBytes:&shadowMVP length:sizeof(vuron::Matrix4x4) atIndex:1];

            // Offset exactly 120 bytes (60 previous indices * 2 bytes each) to reach the shadow indices
            [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                indexCount:6
                                indexType:MTLIndexTypeUInt16
                                indexBuffer:(id<MTLBuffer>)m_indexBuffer
                                indexBufferOffset:120];
        }

        // =======================================
        // --- Draw the UI (Crosshair) ---
        // =======================================
        // 1. Switch the GPU to the Inversion pipeline
        [encoder setRenderPipelineState:(id<MTLRenderPipelineState>)m_uiPipelineState];

        // 2. Set the alphaFlag > 1.5 to trigger the crosshair carving-out
        float uiAlpha = 2.0f;
        [encoder setFragmentBytes:&uiAlpha length:sizeof(float) atIndex:2];

        // 3. The single number to change crosshair size
        float crosshairScale = 0.04f;

        // 4. The aspect ratio fix
        float aspectSquish = 16.0f / 9.0f;

        //We only scale. No translations, no camera matrices. It thus stays perfectly centered (hypothetically)
        vuron::Matrix4x4 uiMVP = vuron::Matrix4x4::scale(crosshairScale / aspectSquish, crosshairScale, 1.0f);
        [encoder setVertexBytes:&uiMVP length:sizeof(vuron::Matrix4x4) atIndex:1];

        // 5. Draw it. Offset exactly 132 bytes (66 indices * 2 bytes each)
        [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                            indexCount:6
                            indexType:MTLIndexTypeUInt16
                            indexBuffer:(id<MTLBuffer>)m_indexBuffer
                            indexBufferOffset:132];

        // ===========================================
        // -= 6. Debug Menu =-
        // ===========================================
        static NSTextField* debugLabel = nil;

        // 1. Capture the exact variables we need
        bool showMenu = m_showDebugMenu;
        float px = camera.position.x;
        float py = camera.position.y;
        float pz = camera.position.z;
        float currentSpeed = std::sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z);
        bool isAccel = m_isAccelerating;
        int renderCount = renderedObjectCount;
        int totalCount = (int)m_cubes.size();
        int grappleCharges = camera.currentAirGrapples;

        // 2. Throw the UI drawing logic over to the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if (showMenu) {
                // Lazy Initialization
                if (!debugLabel) {
                    NSWindow *window = [NSApp mainWindow];
                    if (!window) window = [NSApp keyWindow]; // Fallback if mainWindow isn't set yet
                    if (window) {
                        NSView*mainView = window.contentView;
                        debugLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(16, mainView.bounds.size.height - 140, 400, 140)];
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
                    NSString *text = [NSString stringWithFormat:@"X: %.2f\nY: %.2f\nZ: %.2f\nSpeed: %.3f\nRendered: %d / %d\nGrapples: %d\nAccel: ",
                                      px, py, pz, currentSpeed, renderCount, totalCount, grappleCharges];

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