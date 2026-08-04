#pragma once
#include <vector>
#include <cmath>
#include "../math/Math.h"

namespace vuron
{
    class SpatialHashGrid
    {
        public:
            static const int TABLE_SIZE = 4096;
            float cellSize = 8.0f; // 8x8x8 chunks

            // The 1D Hash table of Object Indices
            std::vector<int> table[TABLE_SIZE];

            // Zero allocation query buffers
            std::vector<int> queryBuffer;
            std::vector<bool> checkedMarker;

            SpatialHashGrid()
            {
                queryBuffer.reserve(256); // Pre-allocating memory
                checkedMarker.resize(10000, false); // Support up to 10k objects
            }

            void clear()
            {
                for (int i = 0; i < TABLE_SIZE; ++i)
                {
                    table[i].clear(); // Size becomes 0 but capacity remains (0 re-allocations)
                }
            }

            inline int hash(int cx, int cy, int cz) const
            {
                // Large prime multiplication to scatter coordinates evenly
                unsigned int h = (cx * 73856093) ^ (cy * 19349663) ^ (cz * 83492791);
                return h % TABLE_SIZE;
            }

            void insert(int objectIndex, const vuron::AABB& box)
            {
                int minX = std::floor(box.min.x / cellSize);
                int minY = std::floor(box.min.y / cellSize);
                int minZ = std::floor(box.min.z / cellSize);

                int maxX = std::floor(box.max.x / cellSize);
                int maxY = std::floor(box.max.y / cellSize);
                int maxZ = std::floor(box.max.z / cellSize);

                for (int x = minX; x <= maxX; ++x)
                {
                    for (int y = minY; y <= maxY; ++y)
                    {
                        for (int z = minZ; z <= maxZ; ++z)
                        {
                            table[hash(x, y, z)].push_back(objectIndex);
                        }
                    }
                }
            }

            const std::vector<int>& query(const vuron::AABB& box)
            {
                queryBuffer.clear();

                int minX = std::floor(box.min.x / cellSize);
                int minY = std::floor(box.min.y / cellSize);
                int minZ = std::floor(box.min.z / cellSize);

                int maxX = std::floor(box.max.x / cellSize);
                int maxY = std::floor(box.max.y / cellSize);
                int maxZ = std::floor(box.max.z / cellSize);

                for (int x = minX; x <= maxX; ++x)
                {
                    for (int y = minY; y <= maxY; ++y)
                    {
                        for (int z = minZ; z <= maxZ; ++z)
                        {
                            int h = hash(x, y, z);
                            for (int objIndex : table[h])
                            {
                                // O(1) duplicate check without expensive loops
                                if (!checkedMarker[objIndex])
                                {
                                    checkedMarker[objIndex] = true;
                                    queryBuffer.push_back(objIndex);
                                }
                            }
                        }
                    }
                }

                // O(1) reset of the marker array for the next query
                for (int objIndex : queryBuffer)
                {
                    checkedMarker[objIndex] = false;
                }

                return queryBuffer;
            }
    };
}