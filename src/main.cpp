//
// Created by Varun Verma on 5/13/26.
// Hello to whoever reads this! This is Varun here! I'm so excited to finally get started
// on creating Vuron, a project I have been thinking about for a long time. I hope this
// project is useful to anybody and everybody. I think great software should be free, so
// if this isn't great, or isn't free, then my job isn't done. Vuron is going to be an
// ultra-fast Game engine, capable of anything you want it to do, and exactly that. Nothing
// more, nothing less. I hope this may come in handy to somebody some day. To anybody who
// bothered reading this. I thank you, and I hope you can appreciate this project once it
// is completed.
//

#include "core/Memory.h"
#include "platform/mac/MacWindow.h"
#include <iostream>
#include <chrono>
#include <thread>


// This is the old main function before CVDisplayLink was implemented.
// Leaving this here just in case.
// int main()
// {
//     vuron::MacWindow myWindow;
//
//     if (!myWindow.init())
//     {
//         std::cout << "Failed to initialize Vuron Window" << std::endl;
//         return -1;
//     }
//
//     // Capturing the start time
//     auto lastTime = std::chrono::high_resolution_clock::now();
//
//     std::cout << "Vuron Engine started" << std::endl;
//
//     // Main Delta Time loop
//     while (true)
//     {
//         // Here, we calculate the delta time (don't ask)
//         auto currentTime = std::chrono::high_resolution_clock::now();
//         std::chrono::duration<float> elapsed = currentTime - lastTime;
//         float deltaTime = elapsed.count();
//         lastTime = currentTime;
//
//         // Over here we update the platform, with any other registered inputs
//         // like mouse clicks or resizes
//         myWindow.update();
//
//         // ----TEMP----
//         // For testing, we're printing out the Frame Time every 1000 frames
//         // so as to not bloat the terminal window with more
//         static int frameCount = 0;
//         if (++frameCount >= 1000)
//         {
//             std::cout << "Frame Time:" << deltaTime * 1000.0f << "ms | FPS:" << 1.0f / deltaTime << std::endl;
//             frameCount = 0;
//         }
//     }
//
//     return 0;
// }


// This is the second variation of int main(). This was used when testing / creating
// the memory arena. From here, I've implemented Engine.h and the next main will
// implement that into itself
// int main()
// {
//     vuron::MacWindow myWindow;
//     myWindow.init();
//
//     while (!myWindow.shouldClose())
//     {
//         myWindow.update();
//         // Reduces CPU% usage from ~99.7% to 3.4%
//         std::this_thread::sleep_for(std::chrono::milliseconds(1));
//     }
//
//     return 0;
// }


// This one was just mostly used for testing
// int main()
// {
//     // Create the Global Arena (512 MB)
//     vuron::MemoryArena globalArena = vuron::create_arena(512);
//     if (!globalArena.base) return -1;
//
//     // Allocating the Window from the Arena.
//     // We ask the exact size of the class
//     void* windowMemory = globalArena.push(sizeof(vuron::MacWindow));
//     std::cout << "DEBUG: Memory Address: " << windowMemory << std::endl;
//
//     // Use "Placement New" to initialize the obj into the Arena
//     vuron::MacWindow* myWindow = new (windowMemory) vuron::MacWindow();
//
//     if (!myWindow->init())
//     {
//         std::cout << "Failed to Initialize Vuron" << std::endl;
//         return -1;
//     }
//
//     std::cout << "Vuron Arena Active. Offset: " << globalArena.offset << std::endl;
//
//     // Second smaller arena for temporary stuff
//     vuron::MemoryArena frameArena = vuron::create_arena(64);
//     while (!myWindow->shouldClose())
//     {
//         myWindow->update();
//         frameArena.reset(); // Instant cleanup
//         // Tell the CPU to chill dawg
//         std::this_thread::sleep_for(std::chrono::milliseconds(1));
//     }
//
//     // Clean everything up and close it
//     myWindow->close();
//     vuron::destroy_arena(globalArena);
//
//     return 0;
//
// }

int main()
{
    // Grabbing land, 512MB permanent, 64MB frame
    vuron::MemoryArena permanentArena = vuron::create_arena(512);
    vuron::MemoryArena frameArena = vuron::create_arena(64);

    if (!permanentArena.base || !frameArena.base)
    {
        return -1;
    }

    void* windowMemory = permanentArena.push(sizeof(vuron::MacWindow));
    vuron::MacWindow* myWindow = new (windowMemory) vuron::MacWindow();

    if (!myWindow->init(permanentArena))
    {
        return -1;
    }

    std::cout << "Vuron Initialized. Permanent offset: " << permanentArena.offset << std::endl;

    // Core loop
    while (!myWindow->shouldClose())
    {
        myWindow->update();
        //Game logic would start here
        // And end here
        // Wipe the arena
        frameArena.reset();
        // Keeping CPU usage low
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    // Close and destroy memory arenas
    myWindow->close();
    vuron::destroy_arena(permanentArena);
    vuron::destroy_arena(frameArena);
    return 0;

    }