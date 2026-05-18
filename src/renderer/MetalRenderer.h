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

        private:
        void* m_device; // id<MTLDevice>
        void* m_commandQueue; // id<MTLCommandQueue>
        void* m_metalLayer; // CAMetalLayer*

    };
}

#endif //VURONENGINE_METALRENDERER_H