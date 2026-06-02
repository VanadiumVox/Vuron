#include "MetalRenderer.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Appkit/NSWindow.h>
#import <AppKit/NSView.h>
#include <iostream>
#include "../math/Math.h"

namespace vuron {
    MetalRenderer::MetalRenderer() : m_device(nullptr), m_commandQueue(nullptr), m_metalLayer(nullptr), m_pipelineState(nullptr), m_vertexBuffer(nullptr) {}
    MetalRenderer::~MetalRenderer() { shutdown(); }

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

      // Baking the pipeline descriptor into the GPUs memory
      id<MTLRenderPipelineState> pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
      if (!pipelineState) {
        std::cerr << "Pipeline error: " << [[error localizedDescription] UTF8String] << std::endl;
        return false;
      }
      m_pipelineState = (void*)pipelineState;
      std::cout << "Vuron Shaders successfuly compiled" << std::endl;

      // --=TEMP=--
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

      // Ask the hardware for the next screen frame
      id<CAMetalDrawable> drawable = [layer nextDrawable];
      if (!drawable) return;

      // Create the command buffer
      id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];

      // Configure a render pass to clear the window color
      MTLRenderPassDescriptor* renderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
      renderPassDesc.colorAttachments[0].texture = drawable.texture;
      renderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;

      // Vuron Dark Slate Blue background color : ClearColorMake(R, G, B, A)
      renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.14, 0.18, 1.0);
      renderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

      id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDesc];

      // New draw commands
      if (m_pipelineState && m_vertexBuffer) {
        // --=The Engine's Timepiece=--
        // Any static variable survives between frames. Because CVDisplayLink is locked to
        // the monitor's refresh rate, adding a fixed number here guarantees a smooth spin
        static float angle = 0.0f;
        angle += 0.02f;

        // Model : Spin the triangle around the z-axis
        vuron::Matrix4x4 modelMatrix = vuron::Matrix4x4::rotationZ(angle);
        // View : Push the triangle 2 units into the screen, away from the camera
        vuron::Matrix4x4 viewMatrix = vuron::Matrix4x4::translation(0.0f, 0.0f, 2.0f);
        // Projection : Create a 45º camera lens at 16:9 aspect ratio
        float aspectRatio = 1280.0f / 720.0f;
        vuron::Matrix4x4 projectionMatrix = vuron::Matrix4x4::perspective(45.0f, aspectRatio, 0.1f, 100.0f);
        // The MVP chain : Multiply in order: Model --> View --> Projection
        vuron::Matrix4x4 mvpMatrix = modelMatrix * viewMatrix * projectionMatrix;

        // ----------------------------------------

        // Tell the GPU which instruction manual (shader) to use
        [encoder setRenderPipelineState:(id<MTLRenderPipelineState>)m_pipelineState];
        // Bind our GPU memory to slot 0
        [encoder setVertexBuffer:(id<MTLBuffer>)m_vertexBuffer offset:0 atIndex:0];
        // Inject the matrix directly into GPU Register slot 1
        [encoder setVertexBytes:&mvpMatrix length:sizeof(vuron::Matrix4x4) atIndex:1];
        // -=New Indexed draw call=-
        // Execute the draw using the map, connecting the dots
        [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                            indexCount:36
                            indexType:MTLIndexTypeUInt16
                            indexBuffer:(id<MTLBuffer>)m_indexBuffer
                            indexBufferOffset:0];
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