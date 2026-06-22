//
// Created by Varun Verma on 5/18/26.
//

#ifndef VURONENGINE_METALRENDERER_H
#define VURONENGINE_METALRENDERER_H

#include <vector>
#include "../math/Math.h"

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

        //Bridge for raw mo0use laser data
        void addMouseDelta(float dx, float dy);

        // The 1-line building tool
        void addCube(float px, float py, float pz, float sx, float sy, float sz);
        void loadTestLevel();

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
        // Shift key for crouching
        bool m_keyShift = false;

        // SOCD (Last-Win) axis trackers
        char m_activeX = 0;
        char m_activeZ = 0;

        // Jump spam prevention lock
        bool m_hasJumped = false;

        // Trackers for how far the mouse moved in the frame
        float m_mouseDeltaX = 0.0f;
        float m_mouseDeltaY = 0.0f;

        // The dynamic, infinitely scalable list of world geometry (dash)
        std::vector<vuron::Transform> m_cubes;
        bool m_levelLoaded = false; // Ensures level spawns only once

    };
}

#endif //VURONENGINE_METALRENDERER_H