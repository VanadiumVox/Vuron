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


int main()
{
    vuron::MacWindow myWindow;
    myWindow.init();

    while (!myWindow.shouldClose())
    {
        myWindow.update();
        // Reduces CPU% usage from ~99.7% to 3.4%
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    return 0;
}