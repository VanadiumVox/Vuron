//
// Created by Varun Verma on 5/18/26.
//

#ifndef VURONENGINE_METALRENDERER_H
#define VURONENGINE_METALRENDERER_H

namespace vuron
{
    class MetalRenderer
    {
        public:
        MetalRenderer();
        ~MetalRenderer();

        bool init(void* windowHandle);
        void drawFrame();
        void shutdown();

        // Exposes a bridge so OS can tell Vuron if a key is pressed
        void setKeyState(char key, bool isPressed);

        //Bridge for raw mo0use laster data
        void addMouseDelta(float dx, float dy);

        private:
        void* m_device; // id<MTLDevice>
        void* m_commandQueue; // id<MTLCommandQueue>
        void* m_metalLayer; // CAMetalLayer*
        void* m_pipelineState; // id<MTLRenderPipelineState>
        void* m_vertexBuffer; //  id<MTLBuffer>
        void* m_indexBuffer; // id<MTLBuffer
        void* m_depthTexture; // Stores z-dist of every pixel instead of color
        void* m_depthStencilState; // only re-draw if z-dist is smaller than cached

        // Hardware state flags for zero-latency movement
        // These stay true when held down
        bool m_keyW = false;
        bool m_keyA = false;
        bool m_keyS = false;
        bool m_keyD = false;

        //Space key for jumping
        bool m_keySpace = false;

        // Trackers for how far the mouse moved in the frame
        float m_mouseDeltaX = 0.0f;
        float m_mouseDeltaY = 0.0f;

    };
}

#endif //VURONENGINE_METALRENDERER_H