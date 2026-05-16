//
// Created by Varun Verma on 5/15/26.
//

#ifndef VURON_ENGINE_H
#define VURON_ENGINE_H

#include "Memory.h"
#include "../platform/mac/MacWindow.h"

namespace vuron
{
    struct EngineState
    {
        MemoryArena permanentArena;
        MacWindow* window;
        bool isRunning;
    };
}

#endif //VURON_ENGINE_H