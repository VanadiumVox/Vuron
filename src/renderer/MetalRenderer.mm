#include "MetalRenderer.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Appkit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/AppKit.h>
#include <iostream>
#include <mach-o/dyld.h>
#include "../math/Math.h"
#include "../world/LevelLoader.h"
#include "../world/MapParser.h"

namespace vuron {
    // Constructor & destructor
    MetalRenderer::MetalRenderer() : m_device(nullptr), m_commandQueue(nullptr), m_metalLayer(nullptr), m_pipelineState(nullptr), m_vertexBuffer(nullptr), m_indexBuffer(nullptr), m_depthTexture(nullptr), m_depthStencilState(nullptr) {}
    MetalRenderer::~MetalRenderer() { shutdown(); }

    // Memory state for spawn
    static vuron::Vector3 g_activeRespawnPoint = {0.0f, 2.0f, -5.0f};

    static id<MTLDepthStencilState> g_uiDepthState = nil;

    // -=The input Bridge=-
    // Changes flags the exact millisecond a key is pressed
    // Bypasses standard keyboard delay
    void MetalRenderer::setKeyState(char key, bool isPressed)
    {
        // -= Double-tap acceleration logic =-
        if (key == 'w' || key == 'a' || key == 's' || key == 'd')
        {
            // Check if the key is already held down to filter out macOS key-repeat spam
            bool alreadyPressed = false;
            if (key == 'w') alreadyPressed = m_keyW;
            if (key == 'a') alreadyPressed = m_keyA;
            if (key == 's') alreadyPressed = m_keyS;
            if (key == 'd') alreadyPressed = m_keyD;

            if (isPressed && !alreadyPressed)
            {
                // if it's the same key and the timer is alive, accelerate
                if (m_lastTappedKey == key && m_doubleTapWindow > 0)
                {
                    m_isAccelerating = true;
                }
                // Record this physical tap and reset the timer (15 frames = 0.25s roughly)
                m_lastTappedKey = key;
                m_doubleTapWindow = 15;
            }
        }

        // Z-axis (forward/backwards)
        if (key == 'w' || key == 's')
        {
            if (key == 'w') m_keyW = isPressed;
            if (key == 's') m_keyS = isPressed;

            if (isPressed)
            {
                m_activeZ = key; // The most recent key
            }
            else
            {
                // If we let go of a key, check if opposite key is still held
                if (key == 'w' && m_keyS) m_activeZ = 's'; // First w then s
                else if (key == 's' && m_keyW) m_activeZ = 'w'; // First s then w
                else m_activeZ = 0; // Neither pressed
            }
        }

        //X-axis (left/right)
        if (key == 'a' || key == 'd')
        {
            if (key == 'a') m_keyA = isPressed;
            if (key == 'd') m_keyD = isPressed;

            if (isPressed)
            {
                m_activeX = key; // The most recent key
            }
            else
            {
                if (key == 'a' && m_keyD) m_activeX = 'd';
                else if (key == 'd' && m_keyA) m_activeX = 'a';
                else m_activeX = 0;
            }
        }

        // Jump logic
        if (key == ' ')
        {
            m_keySpace = isPressed;
            // The exact moment you let go
            if (!isPressed)
            {
                m_hasJumped = false;
            }
        }

        // Crouch logic
        if (key == 'C')
        {
            m_keyShift = isPressed;
        }

        // Acceleration toggle logic
        if (key == 'r')
        {
            if (isPressed && !m_keyR)
            {
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

      // 1. Ask the macOS Kernel exactly where this binary lives
      char pathBuffer[1024];
      uint32_t size = sizeof(pathBuffer);
      _NSGetExecutablePath(pathBuffer, &size);

      NSString* rawPath = [NSString stringWithUTF8String:pathBuffer];
      NSString* execPath = [rawPath stringByStandardizingPath];
      NSString* baseDir = [execPath stringByDeletingLastPathComponent];

      // 2. Demo Mode Check (Looks right next to the executable)
      NSString* shaderPath = [baseDir stringByAppendingPathComponent:@"src/renderer/Shaders.metal"];

      // 3. Dev Mode Fallback (If not found, step up one directory out of 'build' or 'bin')
      if (![[NSFileManager defaultManager] fileExistsAtPath:shaderPath])
      {
          shaderPath = [baseDir stringByAppendingPathComponent:@"../src/renderer/Shaders.metal"];
          // Clean up the string so it looks nice in the terminal
          shaderPath = [shaderPath stringByStandardizingPath];
      }

      std::cout << "[Vuron] Hunting for shaders at: " << [shaderPath UTF8String] << std::endl;

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

      // -= UI Depth State (Always drawn on top) =-
      MTLDepthStencilDescriptor* uiDepthDesc = [[MTLDepthStencilDescriptor alloc] init];
      uiDepthDesc.depthCompareFunction = MTLCompareFunctionAlways; // Ignores walls
      uiDepthDesc.depthWriteEnabled = NO;
      g_uiDepthState = [device newDepthStencilStateWithDescriptor:uiDepthDesc];

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

        // Decay the double-tap sprint window
        if (m_doubleTapWindow > 0) m_doubleTapWindow--;


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
        if (!m_levelLoaded)
        {
            char pathBuffer[1024];
            uint32_t size = sizeof(pathBuffer);
            _NSGetExecutablePath(pathBuffer, &size);

            NSString* rawPath = [NSString stringWithUTF8String:pathBuffer];
            NSString* execPath = [rawPath stringByStandardizingPath];
            NSString* baseDir = [execPath stringByDeletingLastPathComponent];

            // Loaded Level name
            NSString* targetFile = @"test_arena.map";

            // Primary Path (demo mode)
            NSString* levelPathNS = [[baseDir stringByAppendingPathComponent:@"src/levels/"] stringByAppendingPathComponent:targetFile];

            // Dev mode fallback (step out of build/ dir)
            if (![[NSFileManager defaultManager] fileExistsAtPath:levelPathNS])
            {
                levelPathNS = [[baseDir stringByAppendingPathComponent:@"../src/levels/"] stringByAppendingPathComponent:targetFile];
                levelPathNS = [levelPathNS stringByStandardizingPath];
            }

            std::string levelPath = [levelPathNS UTF8String];
            std::cout << "[Vuron] Loading TrenchBroom map from: " << levelPath << std::endl;

            // Route to the correct parser based  on file extension
            if (levelPath.length() >= 4 && levelPath.substr(levelPath.length() - 4) == ".map")
            {
                vuron::MapData mapData = vuron::MapParser::loadMap(levelPath);
                camera.position = mapData.playerSpawn;
                g_activeRespawnPoint = mapData.playerSpawn;
                m_cubes = vuron::MapParser::generateShapes(mapData);

                // -- GPU Bake Pass: Compiling custom Geometry
                id<MTLDevice> device = (id<MTLDevice>)m_device;
                for (size_t i = 0; i < m_cubes.size(); ++i)
                {
                    if (m_cubes[i].type == vuron::ShapeType::CUSTOM && !m_cubes[i].customTriangles.empty())
                    {
                        std::vector<vuron::Vertex> gpuVertices;

                        // Convert the World space points to Local space points by subtracting the center position
                        for (const auto& pt : m_cubes[i].customTriangles)
                        {
                            vuron::Vector3 localPt =
                            {
                                pt.x - m_cubes[i].position.x,
                                pt.y - m_cubes[i].position.y,
                                pt.z - m_cubes[i].position.z
                            };

                            // Giving custom shapes a distinct Orange color
                            gpuVertices.push_back({localPt, {1.0f, 0.5f, 0.2f}});
                        }
                        m_cubes[i].customVertexCount = (int)gpuVertices.size();

                        // Allocating a dedicated Metal Buffer just for the weird shapes
                        m_cubes[i].customVertexBuffer = (void*)[device newBufferWithBytes:gpuVertices.data()
                                                                    length:(sizeof(vuron::Vertex) * gpuVertices.size())
                                                                    options:MTLResourceStorageModeShared];
                    }
                }
            }
            else if (levelPath.length() >= 5 && levelPath.substr(levelPath.length() - 5) == ".vlvl")
            {
                // Keeping the original fallback camera spawn for .vlvl files
                camera.position = {0.0f, 2.0f, -5.0f};
                m_cubes = vuron::LevelLoader::loadLevel(levelPath);
            }
            else
            {
                std::cerr << "[Vuron] Fatal: Unknown level file extension." << std::endl;
            }

            m_levelLoaded = true;
        }

        // Update Geometry (dash) (2.2 when??)
        // We manually spin the first 3 cubes in our list
//         m_cubes[0].rotation = {angle, angle * 0.7f, 0.0f};
//         m_cubes[1].rotation = {0.0f, angle, angle * 0.5f};
//         m_cubes[2].rotation = {angle * 2.0f, angle * 2.0f, 0.0f};
        // R.I.P Rotating cubes.....
        // You will be missed. Perished 7th Aug 2026.

        // Rebuild Spatial Hash Grid safely for whatever objects exist
        m_grid.clear();
        for (size_t i = 0; i < m_cubes.size(); ++i)
        {
            m_grid.insert((int)i, m_cubes[i].getHitbox());
        }

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

        // Void Killplane
        if (camera.position.y < -500.0f)
        {
            camera.position = g_activeRespawnPoint;
            camera.velocity.y = 0.0f;
            camera.velocity.x = 0.0f;
            camera.velocity.z = 0.0f;
        }

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
        const std::vector<int>& xCandidates = m_grid.query(xBox);
        for (int i : xCandidates)
        {
            if (m_cubes[i].type == vuron::ShapeType::CUBE && vuron::AABB::checkCollision(xBox, m_cubes[i].getHitbox())) {
                camera.position.x -= vel.x; vel.x = 0.0f; break;
            }
        }

        // Z-Axis
        camera.position.z += vel.z;
        vuron::AABB zBox = camera.getHitbox();
        // Lift feet to glide over floors, yadda yaddda
        zBox.min.y += 0.05f; zBox.max.y -= 0.05f;
        const std::vector<int>& zCandidates = m_grid.query(zBox);
        for (int i : zCandidates)
        {
            if (m_cubes[i].type == vuron::ShapeType::CUBE && vuron::AABB::checkCollision(zBox, m_cubes[i].getHitbox())) {
                camera.position.z -= vel.z; vel.z = 0.0f; break;
            }
        }

        // -- Y-Axis Pass (Gravity & Floors) --

        // Time Slicing: Breaks massive speeds into safer, 0.25 unit chunks
        int ySteps = std::max(1, (int)std::ceil(std::abs(vel.y) / 0.25f));
        float stepY = vel.y / ySteps;

        for (int s = 0; s < ySteps; ++s)
        {
            camera.position.y += stepY;
            const std::vector<int>& yCandidates = m_grid.query(camera.getHitbox());

            for (int i : yCandidates)
            {
                if (m_cubes[i].type == vuron::ShapeType::CUBE && vuron::AABB::checkCollision(camera.getHitbox(), m_cubes[i].getHitbox()))
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
                    stepY = 0.0f; // Halt the time-slice loop
                    break;
                }
            }
            // If we hit a floor or ceiling, exit the time-slice loop
            if (vel.y == 0.0f) break;
        }

        // -- Convex Hull Wedge Pass --
        // 1. Getting the base hitbox
        vuron::AABB pBox = camera.getHitbox();

        // 2. Anti-phasing: Stretch hitbox to prevent clipping
        if (vel.y < 0.0f) pBox.max.y -= vel.y;
        else if (vel.y > 0.0f) pBox.min.y -= vel.y;

        // 3. Broad phase: Query the grid using the stretched hitbox
        const std::vector<int>& wedgeCandidates = m_grid.query(pBox);

        // 4. Narrow phase: SAT math
        for (int i : wedgeCandidates)
        {
            if (m_cubes[i].type == vuron::ShapeType::WEDGE || m_cubes[i].type == vuron::ShapeType::CUSTOM)
            {

                // Broad phase: Are we inside the AABB? (red box)
                if (vuron::AABB::checkCollision(pBox, m_cubes[i].getHitbox()))
                {
                    // Dynamically load the planes depending on the shape type
                    std::vector<vuron::Transform::Plane> planes;
                    if (m_cubes[i].type == vuron::ShapeType::WEDGE)
                    {
                        vuron::Transform::Plane wPlanes[5];
                        m_cubes[i].getWedgePlanes(wPlanes);
                        for (int p = 0; p < 5; p++) planes.push_back(wPlanes[p]);
                    }
                    else
                    {
                        // Load the true CSG planes from TrenchBroom
                        planes = m_cubes[i].customPlanes;
                    }

                    // Map the player's 3D hitbox
                    vuron::Vector3 center = { (pBox.min.x + pBox.max.x)*0.5f, (pBox.min.y + pBox.max.y)*0.5f, (pBox.min.z + pBox.max.z)*0.5f };
                    vuron::Vector3 ext = { (pBox.max.x - pBox.min.x)*0.5f, (pBox.max.y - pBox.min.y)*0.5f, (pBox.max.z - pBox.min.z)*0.5f };

                    float minPenetration = 9999.0f;
                    vuron::Vector3 pushNormal = {0, 0, 0};
                    bool colliding = true;

                    // Narrow phase - SAT check against all geometric planes dynamically
                    for (size_t p = 0; p < planes.size(); p++)
                    {
                        // Project the player's radius onto the plane's angle
                        float r = ext.x * std::abs(planes[p].normal.x) +
                                  ext.y * std::abs(planes[p].normal.y) +
                                  ext.z * std::abs(planes[p].normal.z);

                        // Distance from player center to plane
                        float d = vuron::dot(center, planes[p].normal) - planes[p].distance;

                        // If outside any plane, no collision occurs
                        if (d > r) { colliding = false; break; }

                        // Find the plane the player penetrated the least (path of least resistance)
                        float pen = r - d;
                        if (pen < minPenetration)
                        {
                            minPenetration = pen;
                            pushNormal = planes[p].normal;
                        }
                    }

                    if (colliding)
                    {
                        // 1. Physically push the player out
                        camera.position.x += pushNormal.x * minPenetration;
                        camera.position.y += pushNormal.y * minPenetration;
                        camera.position.z += pushNormal.z * minPenetration;

                        // 2. Kill velocity moving into the wall
                        float impact = vuron::dot(vel, pushNormal);
                        if (impact < 0.0f)
                        {
                            vel.x -= pushNormal.x * impact;
                            vel.y -= pushNormal.y * impact;
                            vel.z -= pushNormal.z * impact;
                        }

                        // 3. if the plane we hit was flat enough to stand on
                        if (pushNormal.y > 0.7f)
                        {
                            camera.isGrounded = true;
                            camera.crouchedMidAir = false;
                            camera.currentAirGrapples = camera.maxAirGrapples;
                            vel.x *= 0.5f; vel.z *=0.5f; // Friction
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
                float rocketForce = 0.75f; // 5x jump height

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

        float screenW = (float)drawable.texture.width;
        float screenH = (float)drawable.texture.height > 0 ? (float)drawable.texture.height : 1.0f;

        // a. -= Camera Tilt =- -----------------------------------
        float targetRoll = 0.0f;

        // Scale the tilt intensity by momentum.
        // 0.15f is the max multiplier. at 0.5f, the toll is 0.075f
        // at 1.0, roll is 0.15f
        float rollIntensity = m_currentMomentum * 0.15f;

        // SOCD roll: Lean into the strafe
        if (m_activeX == 'a')
        {
            targetRoll = -rollIntensity; // Lean left
        }
        else if (m_activeX == 'd')
        {
            targetRoll = rollIntensity; // Lean right
        }

        // Smoothly interpolate the camera's actual roll towards the target
        camera.roll += (targetRoll - camera.roll) * 0.15f;

        // b. Dynamic speed FOV (Zoom)
        float baseZoom = 1500.0f;

        // Widen the FOV based on momentum.
        float targetZoom = baseZoom - (m_currentMomentum * 1000.0f);

        // Hard capping the FOV so it doesn't invert
        if (targetZoom < 400.0f)
        {
            targetZoom = 400.0f;
        }

        // Smoothly interpolate the active zoom
        m_currentZoom += (targetZoom - m_currentZoom) * 0.25f;

        // c. Apply to matrices
        // viewmatrix now automatically applies the z-roll added in math.h
        vuron::Matrix4x4 viewMatrix = camera.getViewMatrix();

        // projectionMatrix now uses the interpolated m_currentZoom
        vuron::Matrix4x4 projectionMatrix = vuron::Matrix4x4::perspectiveFixed(
            screenW, screenH, m_currentZoom, 0.1f, 1000.0f // Last number is render distance
        );
        // --------------------------------------------------------

        // 3. Prepping the GPU Pipeline
        [encoder setRenderPipelineState:(id<MTLRenderPipelineState>)m_pipelineState];
        [encoder setVertexBuffer:(id<MTLBuffer>)m_vertexBuffer offset:0 atIndex:0];
        [encoder setDepthStencilState:(id<MTLDepthStencilState>)m_depthStencilState];

        // Ensure normal geometry draws completely solid
        float solidAlpha = 1.0f;
        [encoder setFragmentBytes:&solidAlpha length:sizeof(float) atIndex:2];

        // =====================================================
        // --- Dynamic Grapple Light Bridge ---
        // =====================================================
        // Array format: {x, y, z, radius}
        float grappleLightData[4] = {0.0f, 0.0f, 0.0f, 0.0f};

        if (camera.isGrappling)
        {
            // 1. Calculate direction from the wall to the player
            float dirX = camera.position.x - camera.grapplePoint.x;
            float dirY = camera.position.y - camera.grapplePoint.y;
            float dirZ = camera.position.z - camera.grapplePoint.z;

            float dist = std::sqrt(dirX*dirX + dirY*dirY + dirZ*dirZ);

            // Normalizing the vector
            if (dist > 0.0f)
            {
                dirX /= dist;
                dirY /= dist;
                dirZ /= dist;
            }

            grappleLightData[0] = camera.grapplePoint.x + (dirX * 0.2f);
            grappleLightData[1] = camera.grapplePoint.y + (dirY * 0.2f);
            grappleLightData[2] = camera.grapplePoint.z + (dirZ * 0.2f);
            grappleLightData[3] = 12.0f; // The radius of the grapple aura
        }

        // Injecting this into the GPU's fragment shader at buffer index 3
        [encoder setFragmentBytes:&grappleLightData length:sizeof(float) * 4 atIndex:3];


        // =============================================================
        // --- Smarter Shadow Drop Cast Algorithm ---
        // =============================================================
        float shadowY = -9999.0f;
        vuron::Vector3 shadowNormal = {0.0f, 1.0f, 0.0f}; // Default flat floor
        bool drawShadow = false;

        // Shoot a line straight down from the camera
        vuron::Ray downRay = { camera.position, {0.0f, -1.0f, 0.0f} };
        float closestFloorDist = 9999.0f;

        for (size_t i = 0; i < m_cubes.size(); ++i)
        {
            float hitDist = downRay.intersectsOBB(m_cubes[i]);

            // If the floor is directly below us, and it's the closest we've hit
            if (hitDist > 0.0f && hitDist < closestFloorDist)
            {
                closestFloorDist = hitDist;
                // Calculate exact y coordinate of the floor
                shadowY = camera.position.y - hitDist;

                // Steal the exact normal of the surface so we can tilt the shadow
                if (m_cubes[i].type == vuron::ShapeType::CUBE)
                {
                    shadowNormal = {0.0f, 1.0f, 0.0f};
                }
                else if (m_cubes[i].type == vuron::ShapeType::WEDGE)
                {
                    shadowNormal = m_cubes[i].normal;
                }
                else if (m_cubes[i].type == vuron::ShapeType::CUSTOM)
                {
                    // For custom geometry, find exactly which plane the ray struck.
                    for (const auto& plane : m_cubes[i].customPlanes)
                    {
                        vuron::Vector3 hitPt = { downRay.origin.x, downRay.origin.y - hitDist, downRay.origin.z };
                        float d = vuron::dot(hitPt, plane.normal) - plane.distance;

                        if (std::abs(d) < 0.01f)
                        {
                            shadowNormal = plane.normal;
                            break;
                        }
                    }
                }
            }
        }

        // Optimization: Only draw if the floor is within 200 units
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
            // Custom vertices are already their exact true size
            // So we strip the scale out of the matrix here so the GPU doesn't stretch them twice
            if (m_cubes[i].type == vuron::ShapeType::CUSTOM)
            {
                modelMatrix = vuron::Matrix4x4::translation(m_cubes[i].position.x, m_cubes[i].position.y, m_cubes[i].position.z);
            }
            vuron::Matrix4x4 mvpMatrix = modelMatrix * viewProj;

            // Inject the matrix directly into GPU Register slot 1
            [encoder setVertexBytes:&mvpMatrix length:sizeof(vuron::Matrix4x4) atIndex:1];

            // Inject the pure Model Matrix into the GPU register slot 3 for lighting calculations
            [encoder setVertexBytes:&modelMatrix length:sizeof(vuron::Matrix4x4) atIndex:3];

            if (m_cubes[i].type == vuron::ShapeType::CUBE)
            {

                // Re-binding the master Vuron buffer just in case a custom object changed it
                [encoder setVertexBuffer:(id<MTLBuffer>)m_vertexBuffer offset:0 atIndex:0];

                // Execute the draw using the map, connecting the dots
                [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                    indexCount:36
                                    indexType:MTLIndexTypeUInt16
                                    indexBuffer:(id<MTLBuffer>)m_indexBuffer
                                    indexBufferOffset:0];
            }
            else if (m_cubes[i].type == vuron::ShapeType::WEDGE)
            {

                // Re-binding the master Vuron buffer
                [encoder setVertexBuffer:(id<MTLBuffer>)m_vertexBuffer offset:0 atIndex:0];

                // Offset by exactly 72 bytes (36 cube indices * 2 bytes each()
                [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                indexCount:24
                                indexType:MTLIndexTypeUInt16
                                indexBuffer:(id<MTLBuffer>)m_indexBuffer
                                indexBufferOffset:72];
            }
            else if (m_cubes[i].type == vuron::ShapeType::CUSTOM && m_cubes[i].customVertexBuffer)
            {
                // Binding the specific object's unique geometry buffer
                [encoder setVertexBuffer:(id<MTLBuffer>)m_cubes[i].customVertexBuffer offset:0 atIndex:0];

                // Custom objects don't use the index map, they just draw raw triangles straight through
                [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                        vertexStart:0
                        vertexCount:m_cubes[i].customVertexCount];
            }
        }

        // ===========================================
        // 4.5 Draw Bounding box Wireframe
        // ===========================================
        if (m_showBoundingBoxes)
        {

            // Resetting the GPU to the Master Buffer
            [encoder setVertexBuffer:(id<MTLBuffer>)m_vertexBuffer offset:0 atIndex:0];

            // Tell the shader to bypass lighting for wireframes
            float wireframeFlag = 1.2f;
            [encoder setFragmentBytes:&wireframeFlag length:sizeof(float) atIndex:2];

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
            // Rebind master buffer so the shadow doesn't read junk memory
            [encoder setVertexBuffer:(id<MTLBuffer>)m_vertexBuffer offset:0 atIndex:0];

            // Flip the swithc in the Fragment shader to activate transparency & circle math
            float shadowAlpha = 0.5f;
            [encoder setFragmentBytes:&shadowAlpha length:sizeof(float) atIndex:2];

            // --- Perfect Normal alignment ---
            // 1. Create a dynamic rotation matrix from the normal vector
            vuron::Vector3 up = {0.0f, 1.0f, 0.0f};
            // If the floor is completely flat, use the X-axis as our reference instead
            if (std::abs(shadowNormal.y) > 0.99f) up = {1.0f, 0.0f, 0.0f};

            // Calculate Right axis: Cross Product of (Up x Normal)
            vuron::Vector3 right =
            {
                up.y * shadowNormal.z - up.z * shadowNormal.y,
                up.z * shadowNormal.x - up.x * shadowNormal.z,
                up.x * shadowNormal.y - up.y * shadowNormal.x
            };
            float rMag = std::sqrt(right.x*right.x + right.y*right.y + right.z*right.z);
            if (rMag > 0.0f) { right.x /= rMag; right.y /= rMag; right.z /= rMag; }

            // Calculate Forward axis: Cross Product of (Normal x Right)
            vuron::Vector3 forward =
            {
                shadowNormal.y * right.z - shadowNormal.z * right.y,
                shadowNormal.z * right.x - shadowNormal.x * right.z,
                shadowNormal.x * right.y - shadowNormal.y * right.x
            };

            // Build the rotation matrix directly
            vuron::Matrix4x4 alignMat = vuron::Matrix4x4::identity();
            alignMat.m[0][0] = right.x; alignMat.m[0][1] = right.y; alignMat.m[0][2] = right.z;
            alignMat.m[1][0] = shadowNormal.x; alignMat.m[1][1] = shadowNormal.y; alignMat.m[1][2] = shadowNormal.z;
            alignMat.m[2][0] = forward.x; alignMat.m[2][1] = forward.y; alignMat.m[2][2] = forward.z;

            // 2. Anti Z-Fighting: Push the shadow strictly OUT along the normal
            float hover = 0.03f;
            vuron::Matrix4x4 t = vuron::Matrix4x4::translation(
                camera.position.x + (shadowNormal.x * hover),
                shadowY + (shadowNormal.y * hover),
                camera.position.z + (shadowNormal.z * hover)
            );

            // Multiply them all together
            vuron::Matrix4x4 shadowMVP = alignMat * t * viewMatrix * projectionMatrix;

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

        // Rebind the master buffer so no junk memory
        [encoder setVertexBuffer:(id<MTLBuffer>)m_vertexBuffer offset:0 atIndex:0];

        // 1. Switch the GPU to the Inversion pipeline
        [encoder setRenderPipelineState:(id<MTLRenderPipelineState>)m_uiPipelineState];

        // 1.5. Apply UI Depth State
        [encoder setDepthStencilState:g_uiDepthState];

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