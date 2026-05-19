#include "MetalRenderer.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Appkit/NSWindow.h>
#import <AppKit/NSView.h>
#include <iostream>

namespace vuron {
    MetalRenderer::MetalRenderer() : m_device(nullptr), m_commandQueue(nullptr), m_metalLayer(nullptr), m_pipelineState(nullptr) {}
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
      CAMetalLayer* metalLayer = [CAMetalLayer layer];
      metalLayer.device = device;
      metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;

      NSView* view = [window contentView];
      [view setWantsLayer:YES];
      [view setLayer:metalLayer];

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
      return true;
    }

    void MetalRenderer::drawFrame() {
      if (!m_metalLayer || !m_commandQueue) return;

      CAMetalLayer* layer = (CAMetalLayer*)m_metalLayer;
      id<MTLCommandQueue> queue = (id<MTLCommandQueue>)m_commandQueue;

      // Get the next available screen frame swap surface
      id<CAMetalDrawable> drawable = [layer nextDrawable];
      if (!drawable) return;

      // Configure a render pass to clear the window color
      MTLRenderPassDescriptor* renderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
      renderPassDesc.colorAttachments[0].texture = drawable.texture;
      renderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;

      // Vuron Dark Slate Blue background color : ClearColorMake(R, G, B, A)
      renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.14, 0.18, 1.0);
      renderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

      id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];
      id<MTLCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDesc];

      [encoder endEncoding];
      [commandBuffer presentDrawable:drawable];
      [commandBuffer commit]; // Ship it to the screen hardware
    }

    void MetalRenderer::shutdown() {
      m_metalLayer = nullptr;
      m_device = nullptr;
      m_commandQueue = nullptr;
    }
}