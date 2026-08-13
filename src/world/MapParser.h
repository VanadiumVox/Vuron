#pragma once
#include <string>
#include <fstream>
#include <sstream>
#include <vector>
#include <iostream>
#include <cmath>
#include <cfloat>
#include <algorithm>
#include "../math/Math.h"
#include "LevelLoader.h"

namespace vuron
{

    struct MapPlane
    {
        vuron::Vector3 normal;
        float distance;
    };

    struct MapBrush
    {
        std::vector<MapPlane> planes;
    };

    struct MapData
    {
        vuron::Vector3 playerSpawn;
        float playerYaw = 0.0f;
        std::vector<MapBrush> brushes;
    };

    class MapParser
    {
        public:
            static MapData loadMap(const std::string& filepath)
            {
                MapData data;
                data.playerSpawn = {0.0f, 2.0f, 0.0f}; // Default fallback spawn

                std::ifstream file(filepath);
                if (!file.is_open())
                {
                    std::cerr << "Vuron Error: Could not open map file " << filepath << std::endl;
                    return data;
                }

                std::string line;
                bool insideEntity = false;
                bool isWorldSpawn = false;
                bool insideBrush = false;
                MapBrush currentBrush;

                while (std::getline(file, line))
                {
                    // Trim whitespace
                    line.erase(0, line.find_first_not_of(" \t\r\n"));
                    if (line.empty() || line.substr(0, 2) == "//") continue;

                    if (line == "{") {
                        if (!insideEntity)
                        {
                            insideEntity = true;
                            isWorldSpawn = false;
                        } else if (insideEntity)
                        {
                            insideBrush = true;
                            currentBrush.planes.clear();
                        }
                        continue;
                    }

                    if (line == "}")
                    {
                        if (insideBrush)
                        {
                            insideBrush = false;
                            if (!currentBrush.planes.empty())
                            {
                                data.brushes.push_back(currentBrush);
                            }
                        }
                        else if (insideEntity)
                        {
                            insideEntity = false;
                        }
                        continue;
                    }

                    if (insideEntity && !insideBrush)
                    {
                        if (line.find("\"classname\" \"worldspawn\"") != std::string::npos)
                        {
                            isWorldSpawn = true;
                        }
                        if (line.find("\"origin\"") != std::string::npos)
                        {
                            parseOrigin(line, data.playerSpawn);
                        }
                        // reading the orientation of the player_start
                        if (line.find("\"angle\"") != std::string::npos)
                        {
                            parseAngle(line, data.playerYaw);
                        }
                    }

                    if (insideBrush)
                    {
                        if (line[0] == '(')
                        {
                            MapPlane plane = parsePlane(line);
                            currentBrush.planes.push_back(plane);
                        }
                    }
                }

                std::cout << "[Vuron] Successfully parsed " << data.brushes.size() << " CSG Brushes from map." << std::endl;
                return data;
            }

            // --- CSG PLANE INTERSECTION MATH ---

            static bool intersectPlanes(const MapPlane& p1, const MapPlane& p2, const MapPlane& p3, vuron::Vector3& outPoint) {
                // Determinant = n1 . (n2 x n3)
                vuron::Vector3 n2xn3 =
                {
                    p2.normal.y * p3.normal.z - p2.normal.z * p3.normal.y,
                    p2.normal.z * p3.normal.x - p2.normal.x * p3.normal.z,
                    p2.normal.x * p3.normal.y - p2.normal.y * p3.normal.x
                };

                float denom = p1.normal.x * n2xn3.x + p1.normal.y * n2xn3.y + p1.normal.z * n2xn3.z;
                if (std::abs(denom) < 1e-5f) return false; // Parallel planes

                vuron::Vector3 n3xn1 =
                {
                    p3.normal.y * p1.normal.z - p3.normal.z * p1.normal.y,
                    p3.normal.z * p1.normal.x - p3.normal.x * p1.normal.z,
                    p3.normal.x * p1.normal.y - p3.normal.y * p1.normal.x
                };

                vuron::Vector3 n1xn2 =
                {
                    p1.normal.y * p2.normal.z - p1.normal.z * p2.normal.y,
                    p1.normal.z * p2.normal.x - p1.normal.x * p2.normal.z,
                    p1.normal.x * p2.normal.y - p1.normal.y * p2.normal.x
                };

                outPoint.x = (p1.distance * n2xn3.x + p2.distance * n3xn1.x + p3.distance * n1xn2.x) / denom;
                outPoint.y = (p1.distance * n2xn3.y + p2.distance * n3xn1.y + p2.distance * n3xn1.y) / denom; // standardizing dot
                outPoint.y = (p1.distance * n2xn3.y + p2.distance * n3xn1.y + p3.distance * n1xn2.y) / denom;
                outPoint.z = (p1.distance * n2xn3.z + p2.distance * n3xn1.z + p3.distance * n1xn2.z) / denom;

                return true;
            }

            static bool isPointInsideBrush(const vuron::Vector3& pt, const MapBrush& brush, float epsilon = 1e-3f)
            {
                for (const auto& plane : brush.planes)
                {
                    float dot = plane.normal.x * pt.x + plane.normal.y * pt.y + plane.normal.z * pt.z;
                    if (dot > plane.distance + epsilon)
                    {
                        return false;
                    }
                }
                return true;
            }

            static void triangulateBrush(const MapBrush& brush, const std::vector<vuron::Vector3>& vertices, vuron::Transform& outShape)
            {
                for (const auto& plane : brush.planes)
                {
                    std::vector<vuron::Vector3> faceVerts;

                    // 1. Gather all vertices that sit flat on this specific plane
                    for (const auto& v : vertices)
                    {
                        float dist = plane.normal.x * v.x + plane.normal.y * v.y + plane.normal.z * v.z;
                        if (std::abs(dist - plane.distance) < 0.01f)
                        {
                            faceVerts.push_back(v);
                        }
                    }

                    if (faceVerts.size() >= 3)
                    {
                        // 2. Calculate the exact center point of this face
                        vuron::Vector3 center = {0.0f, 0.0f, 0.0f};
                        for (const auto& v : faceVerts)
                        {
                            center.x += v.x; center.y += v.y; center.z += v.z;
                        }
                        center.x /= faceVerts.size();
                        center.y /= faceVerts.size();
                        center.z /= faceVerts.size();

                        // 3. Create a local 2D coordinate system (Tangent/Bitangent) to sort the points
                        vuron::Vector3 up = {0.0f, 1.0f, 0.0f};
                        if (std::abs(plane.normal.y) > 0.99f) up = {1.0f, 0.0f, 0.0f};

                        vuron::Vector3 tangent =
                        {
                            plane.normal.y * up.z - plane.normal.z * up.y,
                            plane.normal.z * up.x - plane.normal.x * up.z,
                            plane.normal.x * up.y - plane.normal.y * up.x
                        };
                        float tMag = std::sqrt(tangent.x*tangent.x + tangent.y*tangent.y + tangent.z*tangent.z);
                        tangent.x /= tMag; tangent.y /= tMag; tangent.z /= tMag;

                        vuron::Vector3 bitangent =
                        {
                            plane.normal.y * tangent.z - plane.normal.z * tangent.y,
                            plane.normal.z * tangent.x - plane.normal.x * tangent.z,
                            plane.normal.x * tangent.y - plane.normal.y * tangent.x
                        };

                        // 4. Sort the vertices in a circle (Clockwise) so the GPU doesn't draw a mangled mess
                        std::sort(faceVerts.begin(), faceVerts.end(), [&](const vuron::Vector3& a, const vuron::Vector3& b)
                        {
                            vuron::Vector3 da = {a.x - center.x, a.y - center.y, a.z - center.z};
                            vuron::Vector3 db = {b.x - center.x, b.y - center.y, b.z - center.z};

                            float angleA = std::atan2(da.x*bitangent.x + da.y*bitangent.y + da.z*bitangent.z,
                                                      da.x*tangent.x + da.y*tangent.y + da.z*tangent.z);
                            float angleB = std::atan2(db.x*bitangent.x + db.y*bitangent.y + db.z*bitangent.z,
                                                      db.x*tangent.x + db.y*tangent.y + db.z*tangent.z);
                            return angleA < angleB;
                        });

                        // 5. Generate the Triangle Fan and feed it to the struct
                        for (size_t i = 1; i < faceVerts.size() - 1; ++i)
                        {
                            outShape.customTriangles.push_back(faceVerts[0]);
                            outShape.customTriangles.push_back(faceVerts[i]);
                            outShape.customTriangles.push_back(faceVerts[i+1]);
                        }
                    }
                }
            }

            // --- BRUSH TO VURON SHAPE CONVERTER ---
            static std::vector<vuron::Transform> generateShapes(const MapData& data)
            {
                std::vector<vuron::Transform> shapes;

                for (const auto& brush : data.brushes)
                {
                    std::vector<vuron::Vector3> vertices;
                    size_t numPlanes = brush.planes.size();

                    // Find all valid 3-plane intersection corners
                    for (size_t i = 0; i < numPlanes; ++i)
                    {
                        for (size_t j = i + 1; j < numPlanes; ++j)
                        {
                            for (size_t k = j + 1; k < numPlanes; ++k)
                            {
                                vuron::Vector3 pt;
                                if (intersectPlanes(brush.planes[i], brush.planes[j], brush.planes[k], pt))
                                {
                                    if (isPointInsideBrush(pt, brush))
                                    {
                                        // Deduplicate vertices
                                        bool exists = false;
                                        for (const auto& v : vertices)
                                        {
                                            float dx = v.x - pt.x, dy = v.y - pt.y, dz = v.z - pt.z;
                                            if (dx*dx + dy*dy + dz*dz < 1e-5f)
                                            {
                                                exists = true;
                                                break;
                                            }
                                        }
                                        if (!exists) vertices.push_back(pt);
                                    }
                                }
                            }
                        }
                    }

                    if (vertices.empty()) continue;

                    // Compute bounding box
                    vuron::Vector3 minB = { FLT_MAX, FLT_MAX, FLT_MAX };
                    vuron::Vector3 maxB = { -FLT_MAX, -FLT_MAX, -FLT_MAX };

                    for (const auto& v : vertices)
                    {
                        minB.x = std::min(minB.x, v.x); minB.y = std::min(minB.y, v.y); minB.z = std::min(minB.z, v.z);
                        maxB.x = std::max(maxB.x, v.x); maxB.y = std::max(maxB.y, v.y); maxB.z = std::max(maxB.z, v.z);
                    }

                    vuron::Transform shape;
                    shape.position = { (minB.x + maxB.x) * 0.5f, (minB.y + maxB.y) * 0.5f, (minB.z + maxB.z) * 0.5f };
                    shape.scale = { maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z };
                    shape.rotation = { 0.0f, 0.0f, 0.0f };

                    // -= Strict Shape Routing =-
                    bool isPerfectCube = false;
                    if (numPlanes == 6)
                    {
                        isPerfectCube = true;
                        for (const auto& plane : brush.planes)
                        {
                            // A perfect unrotated cube must face along exactly one axis
                            float maxAxis = std::max({std::abs(plane.normal.x), std::abs(plane.normal.y), std::abs(plane.normal.z)});
                            if (maxAxis < 0.99f)
                            {
                                //If it's rotated or skewed, Route to CUSTOM
                                isPerfectCube = false;
                                break;
                            }
                        }
                    }

                    if (isPerfectCube)
                    {
                        shape.type = vuron::ShapeType::CUBE;
                    }
                    else
                    {
                        // Everything else
                        shape.type = vuron::ShapeType::CUSTOM;
                        triangulateBrush(brush, vertices, shape);

                        // Save TrenchBroom planes directly to the physics engine
                        for (const auto& plane : brush.planes)
                        {
                            vuron::Transform::Plane tp;
                            tp.normal = plane.normal;
                            tp.distance = plane.distance;
                            shape.customPlanes.push_back(tp);
                        }
                    }

                    shapes.push_back(shape);
                }

                return shapes;
            }

        private:
            static void parseOrigin(const std::string& line, vuron::Vector3& spawn)
            {
                size_t firstQuote = line.find_first_of('"', 8);
                if (firstQuote != std::string::npos)
                {
                    size_t secondQuote = line.find_first_of('"', firstQuote + 1);
                    std::string coords = line.substr(firstQuote + 1, secondQuote - firstQuote - 1);
                    std::istringstream iss(coords);
                    float tx, ty, tz;
                    iss >> tx >> ty >> tz;

                    // Scale: 64 TrenchBroom units = 1.0 Vuron unit. Axis swap: Z -> Y, Y -> -Z
                    float scale = 1.0f / 2.0f;
                    spawn.x = -tx * scale;
                    spawn.y = tz * scale;
                    spawn.z = -ty * scale;
                }
            }

            static void parseAngle(const std::string& line, float& yaw)
            {
                size_t firstQuote = line.find_first_of('"', 7);
                if (firstQuote != std::string::npos)
                {
                    size_t secondQuote = line.find_first_of('"', firstQuote + 1);
                    std::string val = line.substr(firstQuote + 1, secondQuote - firstQuote - 1);
                    float angleDeg = std::stof(val);

                    // Converting TrenchBroom degrees to Vuron Radians.
                    // Offset by 90º so looking "0" in TrenchBroom aligns with vuron's 'forward' vector
                    yaw = (angleDeg - 90.0f) * (3.14159265f / 180.0f);
                }
            }

            static MapPlane parsePlane(const std::string& line)
            {
                std::string cleaned = line;
                for (char& c : cleaned)
                {
                    if (c == '(' || c == ')') c = ' ';
                }

                std::istringstream iss(cleaned);
                float p1x, p1y, p1z, p2x, p2y, p2z, p3x, p3y, p3z;
                iss >> p1x >> p1y >> p1z >> p2x >> p2y >> p2z >> p3x >> p3y >> p3z;

                float scale = 1.0f / 4.0f;
                vuron::Vector3 p1 = { -p1x * scale, p1z * scale, -p1y * scale };
                vuron::Vector3 p2 = { -p2x * scale, p2z * scale, -p2y * scale };
                vuron::Vector3 p3 = { -p3x * scale, p3z * scale, -p3y * scale };

                // Cross product of (p2 - p1) and (p3 - p1)
                vuron::Vector3 v1 = { p2.x - p1.x, p2.y - p1.y, p2.z - p1.z };
                vuron::Vector3 v2 = { p3.x - p1.x, p3.y - p1.y, p3.z - p1.z };

                // Reversed cross-product (v2 x v1) to match Vuron's coordinate handedness
                vuron::Vector3 normal =
                {
                    (v1.y * v2.z) - (v1.z * v2.y),
                    (v1.z * v2.x) - (v1.x * v2.z),
                    (v1.x * v2.y) - (v1.y * v2.x)
                };

                float mag = std::sqrt(normal.x*normal.x + normal.y*normal.y + normal.z*normal.z);
                if (mag > 0.0f)
                {
                    normal.x /= mag; normal.y /= mag; normal.z /= mag;
                }

                MapPlane plane;
                plane.normal = normal;
                plane.distance = (normal.x * p1.x) + (normal.y * p1.y) + (normal.z * p1.z);

                return plane;
            }
    };
}