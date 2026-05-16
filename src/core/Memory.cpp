//
// Created by Varun Verma on 5/15/26.
//

#include "Memory.h"
#include <sys/mman.h> // The header for memory mapping
#include <unistd.h>
#include <iostream>

namespace vuron
{
    // Function to create the memory arena/parking lot
    MemoryArena create_arena(std::size_t megabytes)
    {
        MemoryArena arena = {};
        arena.size = megabytes * 1024 * 1024;

        // mmap: Asking the kernel for raw pages
        // MAP_ANON: Not backed by named files, only RAM
        // MAP_PRIVATE: Only our process can see this
        arena.base = (uint8_t*)mmap(nullptr,
            arena.size,
            PROT_READ | PROT_WRITE,
            MAP_ANON | MAP_PRIVATE,
            -1, 0);

        if (arena.base == MAP_FAILED)
        {
            std::cerr << "Vuron Error: Could not mmap memory arena" << std::endl;
            return {};
        }

        arena.offset = 0;
        return arena;
    }

    void* vuron::MemoryArena::push(size_t requestSize)
    {
        // Alignment = the "Crisp" part
        // CPUs tend to access memory faster when aligned to 8 or 16 bytes
        std::size_t alignment = 8;
        std::size_t alignedSize = (requestSize + (alignment - 1)) & ~(alignment - 1);

        if (this->offset + alignedSize <= this->size)
        {
            void* ptr = (void*)((uint8_t*)base + this->offset);
            this->offset += alignedSize;
            return ptr;
        }

        return nullptr; // Out of memory
    }

    void MemoryArena::reset()
    {
        offset = 0; // Instant wipe
    }

    void destroy_arena(MemoryArena& arena)
    {
        // Destroying by unmapping mapped memory
        munmap(arena.base, arena.size);
    }

}