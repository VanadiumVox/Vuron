//
// Created by Varun Verma on 5/19/26.
//

#ifndef VURONENGINE_MATH_H
#define VURONENGINE_MATH_H

#include <cmath>
#include <numbers>

namespace vuron
{
    // Just a lean, 3D vector
    struct Vector3
    {
        float x;
        float y;
        float z;
    };

    // The data we will EVENTUALLY send to the GPU
    struct Vertex
    {
        Vector3 position;
        Vector3 color;
    };

    // -- Vector Math Helpers --
    inline float dot(const Vector3& a, const Vector3& b)
    {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    // a 4x4 Matrix for 3D transformations
    struct Matrix4x4
    {
        float m[4][4];

        // Creates an Identity matrix
        static Matrix4x4 identity()
        {
            Matrix4x4 result = {0}; // Initializing

            // Setting the diagonal to 1 (that's what an ID matrix is)
            result.m[0][0] = 1.0f;
            result.m[1][1] = 1.0f;
            result.m[2][2] = 1.0f;
            result.m[3][3] = 1.0f;
            return result;
        }

        // Creates an X-axis Rotation matrix
        static Matrix4x4 rotationX(float angle){
            Matrix4x4 result = identity();
            float c = std::cos(angle);
            float s = std::sin(angle);

            result.m[1][1] = c;
            result.m[1][2] = -s;
            result.m[2][1] = s;
            result.m[2][2] = c;

            return result;
        }

        // Creates a Y-axis Rotation matrix
        static Matrix4x4 rotationY(float angle) {
            Matrix4x4 result = identity();
            float c = std::cos(angle);
            float s = std::sin(angle);

            result.m[0][0] = c;
            result.m[0][2] = s;
            result.m[2][0] = -s;
            result.m[2][2] = c;

            return result;
        }

        // Creates a Z-axis Rotation matrix
        static Matrix4x4 rotationZ(float angle) {
        Matrix4x4 result = {0};

        float c = std::cos(angle);
        float s = std::sin(angle);

        result.m[0][0] = c;
        result.m[0][1] = -s;
        result.m[1][0] = s;
        result.m[1][1] = c;
        result.m[2][2] = 1.0f;
        result.m[3][3] = 1.0f;

        return result;
        }

        // Creates a combined XYZ rotation matrix
        static Matrix4x4 rotation(float rx, float ry, float rz)
        {
            Matrix4x4 xMat = rotationX(rx);
            Matrix4x4 yMat = rotationY(ry);
            Matrix4x4 zMat = rotationZ(rz);

            // Order matches getModelMatrix() logic
            return xMat * yMat * zMat;
        }

        // Creates a Scaling matrix
        static Matrix4x4 scale(float sx, float sy, float sz){
            Matrix4x4 result = identity();
            result.m[0][0] = sx;
            result.m[1][1] = sy;
            result.m[2][2] = sz;
            return result;
        }

        // Creates a Translation matrix
        static Matrix4x4 translation(float tx, float ty, float tz) {
            Matrix4x4 result = identity();
            // Stored in the bottom row as our Shader multiplies Vector * Matrix
            result.m[3][0] = tx;
            result.m[3][1] = ty;
            result.m[3][2] = tz;
            return result;
        }

        // Creates a 3D Perspective Lens
        static Matrix4x4 perspective(float fovDegrees, float aspect, float nearZ, float farZ) {
            float fovRadians = fovDegrees * (std::numbers::pi_v<float> / 180.0f);
            float yScale = 1.0f / std::tan(fovRadians * 0.5f);
            float xScale = yScale / aspect;
            float zRange = farZ - nearZ;

            Matrix4x4 result = {0};
            result.m[0][0] = xScale;
            result.m[1][1] = yScale;

            // Apple Metal uses a left-handed coordinate system(Z pushes into the screen)
            // and maps depth from 0.0 to 1.0
            result.m[2][2] = farZ / zRange;
            result.m[2][3] = 1.0f;
            result.m[3][2] = -(nearZ * farZ) / zRange;

            return result;
        }

        // This creates a Fixed-scale lens, meaning resizing crops the view,
        // it doesn't shrink the world.
        static Matrix4x4 perspectiveFixed(float screenWidth, float screenHeight, float zoom, float nearZ, float farZ) {
            Matrix4x4 result = {0};

            // By scaling inversely to the screen's dimensions, the window size
            // completely cancels out of the GPU's final pixel math
            result.m[0][0] = zoom / screenWidth;
            result.m[1][1] = zoom / screenHeight;

            float zRange = farZ - nearZ;
            result.m[2][2] = farZ / zRange;
            result.m[2][3] = 1.0f;
            result.m[3][2] = -(nearZ * farZ) / zRange;

            return result;
        }

        //Matrix multiplication
        Matrix4x4 operator*(const Matrix4x4& other) const
        {
            Matrix4x4 result = {0};

            for (int row = 0; row < 4; ++row)
            {
                for (int col = 0; col < 4; ++col)
                {
                    result.m[row][col] =
                        m[row][0] * other.m[0][col] +
                        m[row][1] * other.m[1][col] +
                        m[row][2] * other.m[2][col] +
                        m[row][3] * other.m[3][col];
                }
            }
            return result;
        }
    };

    // A single flat infinite plane used to slice camera vision
    struct FrustumPlane
    {
        Vector3 normal = {0.0f, 0.0f, 0.0f};
        float distance = 0.0f;

        void normalize()
        {
            float mag = std::sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
            normal.x /= mag;
            normal.y /= mag;
            normal.z /= mag;
            distance /= mag;
        }
    };

    // The 6-sided 3D cone representing exactly what the camera can see, and nothing else
    struct Frustum
    {
        FrustumPlane planes[6];

        // Exctracts the vision cone directly from the View-projection matrix
        static Frustum extract(const Matrix4x4& vp)
        {
            Frustum f;

            // Left & Right (w + x, w - x)
            f.planes[0] = {{vp.m[0][3] + vp.m[0][0], vp.m[1][3] + vp.m[1][0], vp.m[2][3] + vp.m[2][0]}, vp.m[3][3] + vp.m[3][0]};
            f.planes[1] = {{vp.m[0][3] - vp.m[0][0], vp.m[1][3] - vp.m[1][0], vp.m[2][3] - vp.m[2][0]}, vp.m[3][3] - vp.m[3][0]};

            // Bottom & Top (w + y, w - y)
            f.planes[2] = {{vp.m[0][3] + vp.m[0][1], vp.m[1][3] + vp.m[1][1], vp.m[2][3] + vp.m[2][1]}, vp.m[3][3] + vp.m[3][1]};
            f.planes[3] = {{vp.m[0][3] - vp.m[0][1], vp.m[1][3] - vp.m[1][1], vp.m[2][3] - vp.m[2][1]}, vp.m[3][3] - vp.m[3][1]};

            // Near & Far (Apple Metal uses 0 to 1 depth, not -1 to 1)
            // Near: z > 0
            f.planes[4] = {{vp.m[0][2], vp.m[1][2], vp.m[2][2]}, vp.m[3][2]};
            // Far: w - z > 0
            f.planes[5] = {{vp.m[0][3] - vp.m[0][2], vp.m[1][3] - vp.m[1][2], vp.m[2][3] - vp.m[2][2]}, vp.m[3][3] - vp.m[3][2]};

            for (int i = 0; i < 6; i++)
            {
                f.planes[i].normalize();
            }
            return f;
        }
    };

    // An Axis-Aligned Bounding Box (AABB) / Rigid Body
    struct AABB {
        Vector3 min; // Bottom-Left-Back corner
        Vector3 max; // Top-Right-Front corner

        // The master collision check; Returns tru if 2 hitboxes overlap
        static bool checkCollision(const AABB& a, const AABB& b) {
            return (a.min.x <= b.max.x && a.max.x >= b.min.x) &&
                   (a.min.y <= b.max.y && a.max.y >= b.min.y) &&
                   (a.min.z <= b.max.z && a.max.z >= b.min.z);
        }

        // Checks if this bounding box is on screen
        bool isOnScreen(const Frustum& frustum) const
        {
            for (int i = 0; i < 6; i++)
            {
                // Find the corner of the box closest to the plane
                Vector3 p = min;
                if (frustum.planes[i].normal.x >= 0.0f) p.x = max.x;
                if (frustum.planes[i].normal.y >= 0.0f) p.y = max.y;
                if (frustum.planes[i].normal.z >= 0.0f) p.z = max.z;

                // If that closest corner is behind the plane, the entire object is invisible
                if ((frustum.planes[i].normal.x * p.x +
                     frustum.planes[i].normal.y * p.y +
                     frustum.planes[i].normal.z * p.z +
                     frustum.planes[i].distance) < 0.0f)
                     {
                        return false;
                     }
            }
            return true;
        }
    };

    enum class ShapeType
    {
        CUBE,
        WEDGE
    };

    // A 3D transform that holds position, rotation and scale for any entity
    struct Transform
    {
        Vector3 position = {0.0f, 0.0f, 0.0f};
        Vector3 rotation = {0.0f, 0.0f, 0.0f};
        Vector3 scale = {1.0f, 1.0f, 1.0f};

        // --- Geometry Data ---
        ShapeType type = ShapeType::CUBE; // Default to a cube
        Vector3 normal = {0.0f, 1.0f, 0.0f}; // Only used if it's a wedge

        // Generates a 3D hitbox wrapped around the unrotated cube
        AABB getHitbox() const
        {
            // Fast path: If it's a flat, unrotated object, use cheaper math
            if (rotation.x == 0.0f && rotation.y == 0.0f && rotation.z == 0.0f)
            {
                return
                {
                    {position.x - (scale.x * 0.5f), position.y - (scale.y * 0.5f), position.z - (scale.z * 0.5f)},
                    {position.x + (scale.x * 0.5f), position.y + (scale.y * 0.5f), position.z + (scale.z * 0.5f)}
                };
            }

            // Dynamic path: The object is tilted. So we calculate an AABB that wraps the rotated corners
            else
            {
                Matrix4x4 model = getModelMatrix();
                Vector3 min = {99999.0f, 99999.0f, 99999.0f};
                Vector3 max = {-99999.0f, -99999.0f, -99999.0f};

                float dx[2] = {-0.5f, 0.5f};
                float dy[2] = {-0.5f, 0.5f};
                float dz[2] = {-0.5f, 0.5f};

                // Mapping all 8 corners through the rotation matrix to find the extreme edges
                for(int i = 0; i < 2; i++)
                {
                    for(int j = 0; j < 2; j++)
                    {
                        for(int k = 0; k < 2; k++)
                        {
                            float wx = dx[i] * model.m[0][0] + dy[j] * model.m[1][0] + dz[k] * model.m[2][0] + model.m[3][0];
                            float wy = dx[i] * model.m[0][1] + dy[j] * model.m[1][1] + dz[k] * model.m[2][1] + model.m[3][1];
                            float wz = dx[i] * model.m[0][2] + dy[j] * model.m[1][2] + dz[k] * model.m[2][2] + model.m[3][2];

                            if (wx < min.x) min.x = wx; if (wx > max.x) max.x = wx;
                            if (wy < min.y) min.y = wy; if (wy > max.y) max.y = wy;
                            if (wz < min.z) min.z = wz; if (wz > max.z) max.z = wz;
                        }
                    }
                }
                return {min, max};
            }
        }

        // Automatically generates the Model Matrix for the entity
        Matrix4x4 getModelMatrix() const
        {
            Matrix4x4 s = Matrix4x4::scale(scale.x, scale.y, scale.z);
            Matrix4x4 rx = Matrix4x4::rotationX(rotation.x);
            Matrix4x4 ry = Matrix4x4::rotationY(rotation.y);
            Matrix4x4 rz = Matrix4x4::rotationZ(rotation.z);
            Matrix4x4 t = Matrix4x4::translation(position.x, position.y, position.z);

            // Order matters a LOT here.
            // Scale first, then Rotate, then Translate
            return s * rx * ry * rz * t;
        }
    };

    // A math line used for hitscan weapons
    struct Ray
    {
        Vector3 origin;
        Vector3 direction;

        // The Slab Method: Calculates if and where a ray pierces a bounding box
        float intersects(const AABB& box) const
        {
            float dirX = direction.x == 0.0f ? 0.00001f : direction.x;
            float dirY = direction.y == 0.0f ? 0.00001f : direction.y;
            float dirZ = direction.z == 0.0f ? 0.00001f : direction.z;

            float tmin = (box.min.x - origin.x) / dirX;
            float tmax = (box.max.x - origin.x) / dirX;
            if (tmin > tmax) { float temp = tmin; tmin = tmax; tmax = temp; }

            float tymin = (box.min.y - origin.y) / dirY;
            float tymax = (box.max.y - origin.y) / dirY;
            if (tymin > tymax) { float temp = tymin; tymin = tymax; tymax = temp; }

            if ((tmin > tmax) || (tymin > tmax)) return -1.0f;
            if (tymin > tmin) tmin = tymin;
            if (tymax < tmax) tmax = tymax;

            float tzmin = (box.min.z - origin.z) / dirZ;
            float tzmax = (box.max.z - origin.z) / dirZ;
            if (tzmin > tzmax) { float temp = tzmin; tzmin = tzmax; tzmax = temp; }

            if ((tmin > tmax) || (tzmin > tmax)) return -1.0f;
            if (tzmin > tmin) tmin = tzmin;
            if (tzmax < tmax) tmax = tzmax;

            if (tmin < 0.0f) return -1.0f;
            return tmin;
        }

        // Advanced OBB (Oriented Bounding Box)
        // Converts the ray into the object's local 1x1x1 space to match the Green visual geometry (using ctrl + b)
        float intersectsOBB(const Transform& t) const
        {
            // 1. Inverse Translate
            Vector3 o = {origin.x - t.position.x, origin.y - t.position.y, origin.z - t.position.z};
            Vector3 d = direction;

            //Inverse Rotation Helpers
            auto rotX = [](Vector3 v, float a) -> Vector3
            {
                float c = std::cos(a), s = std::sin(a);
                return {v.x, v.y * c - v.z * s, v.y * s + v.z * c};
            };
            auto rotY = [](Vector3 v, float a) -> Vector3
            {
                float c = std::cos(a), s = std::sin(a);
                return {v.x * c + v.z * s, v.y, -v.x * s + v.z * c};
            };
            auto rotZ = [](Vector3 v, float a) -> Vector3
            {
                float c = std::cos(a), s = std::sin(a);
                return {v.x * c - v.y * s, v.x * s + v.y * c, v.z};
            };

            // 2. Inverse Rotate (reverse order: Z, Y, X with negative angles)
            o = rotZ(o, t.rotation.z); o = rotY(o, -t.rotation.y); o = rotX(o, -t.rotation.x);
            d = rotZ(d, t.rotation.z); d = rotY(d, -t.rotation.y); d = rotX(d, -t.rotation.x);

            // 3. Inverse Scale
            o.x /= t.scale.x; o.y /= t.scale.y; o.z /= t.scale.z;
            d.x /= t.scale.x; d.y /= t.scale.y; d.z /= t.scale.z;

            // 4. The Local Slab Method (Against a perfect 1x1x1 cube)
            float dirX = d.x == 0.0f ? 0.00001f : d.x;
            float dirY = d.y == 0.0f ? 0.00001f : d.y;
            float dirZ = d.z == 0.0f ? 0.00001f : d.z;

            float tmin = (-0.5f - o.x) / dirX;
            float tmax = (0.5f - o.x) / dirX;
            if (tmin > tmax) { float temp = tmin; tmin = tmax; tmax = temp; }

            float tymin = (-0.5f - o.y) / dirY;
            float tymax = (0.5f - o.y) / dirY;
            if (tymin > tymax) { float temp = tymin; tymin = tymax; tymax = temp; }

            if ((tmin > tymax) || (tymin > tmax)) return -1.0f;
            if (tymin > tmin) tmin = tymin;
            if (tymax < tmax) tmax = tymax;

            float tzmin = (-0.5f - o.z) / dirZ;
            float tzmax = (0.5f - o.z) / dirZ;
            if (tzmin > tzmax) { float temp = tzmin; tzmin = tzmax; tzmax = temp; }

            if ((tmin > tzmax) || (tzmin > tmax)) return -1.0f;
            if (tzmin > tmin) tmin = tzmin;
            if (tzmax < tmax) tmax = tzmax;

            if (tmin < 0.0f) return -1.0f;

            // 5. Advanced Wedge trimming (get it?)
            if (t.type == ShapeType::WEDGE)
            {
                // Calculate exact local hit coordinate
                Vector3 hitLocal = {o.x + d.x * tmin, o.y + d.y * tmin, o.z + d.z * tmin};
                // Sloped roof equation in local space: y = -z
                if (hitLocal.y > -hitLocal.z + 0.01f)
                {
                    return -1.0f; // Shot passed through the empty air
                }
            }

            return tmin;
        }
    };

    // The Player's POV in the 3D Universe
    struct Camera {
        // Starting pushed back from the origin so we don't spawn in a cube
        Vector3 position = {0.0f, 0.0f, -6.0f};

        // Player's neck and spine angles
        float pitch = 0.0f; // Looking up and down
        float yaw = 0.0f; // Looking left and right

        // Tracks the player's 3D Momentum
        Vector3 velocity = {0.0f, 0.0f, 0.0f};

        bool isCrouched = false;

        // Physical state trackers
        bool isGrounded = false;
        bool crouchedMidAir = false; // The strict rocket jump lock

        // Grappling Hook State
        bool isGrappling = false;
        Vector3 grapplePoint = {0.0f, 0.0f, 0.0f};
        int hookedEntityIndex = -1;

        // The Air-charge system for grappling hook
        int maxAirGrapples = 2;
        int currentAirGrapples = 2;

        // Converts the camera's Pitch and Yaw into a normal vector
        Vector3 getForwardVector() const
        {
            return
            {
                std::sin(yaw) * std::cos(pitch),
                -std::sin(pitch),
                std::cos(yaw) * std::cos(pitch)
            };
        }

        // The Player's hitbox
        AABB getHitbox() const {
            float radius = 0.5f; // How FAt the player is
            float height = isCrouched ? 1.5f : 2.0f; // How tall the character is

            // The camera position is at the player's eye-level
            // So the feet (min.y) are 'height' units below the eyes
            return {
                {position.x - radius, position.y - height, position.z - radius},
                {position.x + radius, position.y + 0.2f, position.z + radius} // 0.2f gives a little headroom
            };
        }

        // Generating the View matrix for the GPU
        Matrix4x4 getViewMatrix() const
        {
            // 1. Move the universe away from the player
            Matrix4x4 t = Matrix4x4::translation(-position.x, -position.y, -position.z);

            // 2. Rotate the universe
            Matrix4x4 ry = Matrix4x4::rotationY(yaw);
            Matrix4x4 rx = Matrix4x4::rotationX(pitch);

            // Multiply by translating the world first, then spinning it
            return t * ry * rx;
        }
    };
}

#endif //VURONENGINE_MATH_H