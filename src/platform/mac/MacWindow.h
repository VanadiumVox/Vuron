//
// Created by Varun Verma on 5/13/26.
//

#ifndef VURON_MACWINDOW_H
#define VURON_MACWINDOW_H

#include "../platform.h"

namespace vuron
{
    struct MemoryArena;
    class MetalRenderer;
    class MacWindow : public PlatformWindow
    {
    public:
        MacWindow() :
            m_windowHandle(nullptr),
            m_shouldClose(false),
            m_displayLink(nullptr),
            m_running(false),
            m_renderer(nullptr) {}
        
        bool init(MemoryArena& arena) override;
        void update() override;
        void close() override;

        // This fulfils the contract to let main.cpp see m_shouldClose
        bool shouldClose() const override { return m_shouldClose; }
        // Public function
        void renderFrame();

    private:
        void* m_windowHandle; // Using void* because we don't want
        // Mac-specific headers in the C++ headers YET
        void* m_displayLink; // CVDisplayLinkRef
        bool m_running;
        bool m_shouldClose = false;
        MetalRenderer* m_renderer;
    };
}

#endif //VURON_MACWINDOW_H