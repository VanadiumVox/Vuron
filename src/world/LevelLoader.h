//
// Created by Varun Verma on 6/24/26.
//

#ifndef VURONENGINE_LEVELLOADER_H
#define VURONENGINE_LEVELLOADER_H

#pragma once
#include <vector>
#include <string>
#include <fstream>
#include <sstream>
#include <iostream>
#include "../math/Math.h"

namespace vuron
{

    class LevelLoader
    {
        public:
            static std::vector<vuron::Transform> loadLevel(const std::string& filepath)
            {
                std::vector<vuron::Transform> levelGeometry;
                std::ifstream file(filepath);

                if (!file.is_open())
                {
                    std::cerr << "[Vuron Engine] FATAL: Failed to load level file: " << filepath << "\n";
                    return levelGeometry; // Returns empty, engine renders nothing
                }

                std::string line;
                while (std::getline(file, line))
                {
                    // Ignore empty lines and comments (lines starting with #)
                    if (line.empty() || line[0] == '#') continue;

                    std::istringstream iss(line);
                    std::string type;
                    iss >> type;

                    if (type == "CUBE" || type == "RAMP")
                    {
                        float x, y, z, w, h, d;
                        float rx = 0.0f, ry = 0.0f, rz = 0.0f; // Default to flat

                        // Read the standard 6 numbers
                        if (iss >> x >> y >> z >> w >> h >> d)
                        {
                            // Try to read the optional 3 rotational values
                            if (iss >> rx >> ry >> rz)
                            {
                                // Convert degrees to radians for the math engine
                                rx = rx * (3.14159265f / 180.0f);
                                ry = ry * (3.14159265f / 180.0f);
                                rz = rz * (3.14159265f / 180.0f);
                            }

                            vuron::Transform t;
                            t.position = {x, y, z};
                            t.rotation = {rx, ry, rz};
                            t.scale = {w, h, d};

                            // -- The Ramp Flag --
                            if (type == "RAMP")
                            {
                                t.isRamp = true;
                                // Calculate the normal vector
                                vuron::Matrix4x4 rot = vuron::Matrix4x4::rotation(rx, ry, rz);
                                t.normal = {rot.m[1][0], rot.m[1][1], rot.m[1][2]};
                            }

                            levelGeometry.push_back(t);
                        }
                        else
                        {
                            std::cerr << "[Vuron Engine] WARNING: Malformed CUBE data in level file.\n";
                        }
                    }

                }

                file.close();
                std::cout << "[Vuron Engine] Loaded Level geometry: " << levelGeometry.size() << " objects.\n";
                return levelGeometry;
            }
    };
}

#endif //VURONENGINE_LEVELLOADER_H
