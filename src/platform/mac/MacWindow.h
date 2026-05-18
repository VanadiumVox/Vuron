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
        MacWindow() : m_windowHandle(nullptr) {} // Constructor
        // the part after the ':' is the Initializer list
        // This sets the window pointer (nullptr) to 0 as soon as it's created
        // Avoids garbage data and Undefined Behavior (UB)
        virtual ~MacWindow() { close(); } // Destructor
        // Now, whenever a MacWindow goes out of scope, it calls close()
        // It's a safety net to make sure the window is destroyed if we forget

        // Used 'override' keyword to make sure these match
        // the base class of PlatformWindow in platform.h
        bool init(MemoryArena& arena);
        void update() override;
        void close() override;

        // Public function
        void renderFrame();
        // This fulfils the contract to let main.cpp see m_shouldClose
        bool shouldClose() const override { return m_shouldClose; }

    private:
        void* m_windowHandle; // Using void* because we don't want
        // Mac-specific headers in the C++ headers YET
        void* m_displayLink; // CVDisplayLinkRef
        bool m_running;
        bool m_shouldClose = false;
        MetalRenderer* m_metalRenderer = nullptr;
    };
}

#endif //VURON_MACWINDOW_H