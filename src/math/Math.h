//
// Created by Varun Verma on 5/19/26.
//

#ifndef VURONENGINE_MATH_H
#define VURONENGINE_MATH_H

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