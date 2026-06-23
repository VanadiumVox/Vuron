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
    };

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

    // A 3D transform that holds position, rotation and scale for any entity
    struct Transform
    {
        Vector3 position = {0.0f, 0.0f, 0.0f};
        Vector3 rotation = {0.0f, 0.0f, 0.0f};
        Vector3 scale = {1.0f, 1.0f, 1.0f};

        // Generates a 3D hitbox wrapped around the unrotated cube
        AABB getHitbox() const {
            // Assuming out base 3D cube model is exactly 2x2x2 units large
            return {
                {position.x - scale.x, position.y - scale.y, position.z - scale.z},
                {position.x + scale.x, position.y + scale.y, position.z + scale.z}
            };
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

    // The Player's POV in the 3D Universe
    struct Camera {
        // Starting pushed back from the origin so we don't spawn in a cube
        Vector3 position = {0.0f, 0.0f, -6.0f};

        // Player's neck and spine angles
        float pitch = 0.0f; // Looking up and down
        float yaw = 0.0f; // Looking left and right

        // Tracks vertical momentum
        float velocityY = 0.0f;

        bool isCrouched = false;

        // Physical state trackers
        bool isGrounded = false;
        bool crouchedMidAir = false; // The strict rocket jump lock

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