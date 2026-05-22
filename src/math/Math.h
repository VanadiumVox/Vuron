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
}

#endif //VURONENGINE_MATH_H