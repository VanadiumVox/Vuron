//
// Created by Varun Verma on 5/13/26.
//

#ifndef VURON_PLATFORM_H
#define VURON_PLATFORM_H

namespace vuron
{
    class PlatformWindow
    {
        public:
            // Virtual destructor ensuring memory is cleaned up correctly
            // with no dangling pointers
            virtual ~PlatformWindow() {}

            // Defining Pure Virtual functions,
            // forcing any platform to implement them
            virtual bool init() = 0;
            virtual void update() = 0;
            virtual void close() = 0;
    };

    class MacWindow : public PlatformWindow
    {
        private:
            void* m_windowHandle; // Using void* because we don't want
        // Mac-specific headers in the C++ headers YET
    };
}

#endif //VURON_PLATFORM_H