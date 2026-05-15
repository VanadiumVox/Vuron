//
// Created by Varun Verma on 5/14/26.
//

#ifndef VURON_MEMORY_H
#define VURON_MEMORY_H
#include <cstdio>

namespace vuron
{
    struct MemoryArena
    {
        void* base;         // The start of the RAM block
        std::size_t size;   // The total capacity
        std::size_t offset; // The Next available spot

        // The "push" - The fastest way to get memory
        void* push(std::size_t requestSize);

        // Resets the memory arena
        void reset();
    };

    // System-level allocation using mmap
    MemoryArena create_arena(std::size_t megabytes);
    void destroy_arena(MemoryArena& arena);
}

#endif //VURON_MEMORY_H