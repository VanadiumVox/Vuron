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

                    if (type == "CUBE")
                    {
                        float x, y, z, w, h, d;
                        if (iss >> x >> y >> z >> w >> h >> d)
                        {
                            vuron::Transform t;
                            t.position = {x, y, z};
                            t.rotation = {0.0f, 0.0f, 0.0f};
                            t.scale = {w, h, d};
                            levelGeometry.push_back(t);
                        }
                        else
                        {
                            std::cerr << "[Vuron Engine] WARNING: Malformed CUBE data in level file.\n";
                        }
                    }

                    // Later I'll add 'elfe if type == ramp' here
                }

                file.close();
                std::cout << "[Vuron Engine] Loaded Level geometry: " << levelGeometry.size() << " objects.\n";
                return levelGeometry;
            }
    };
}

#endif //VURONENGINE_LEVELLOADER_H
