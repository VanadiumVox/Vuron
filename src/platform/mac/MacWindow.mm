#include "MacWindow.h"
#import <Cocoa/Cocoa.h> // import = Objective-C version of include

namespace vuron
{
    bool MacWindow::init(){
      // Creating the window's position, and size
      NSRect frame = NSMakeRect(0, 0, 1280, 720);
                   //NSMakeRect(float x, float y, float width, float height)
      // Defining the style, it's titled, it's closable, it's mini-able, and resizable
      NSUInteger styleMask = NSWindowStyleMaskTitled |
      NSWindowStyleMaskClosable |
      NSWindowStyleMaskMiniaturizable |
      NSWindowStyleMaskResizable;

      // Allocating and initializing the NSWindow
      NSWindow* window = [[NSWindow alloc] initWithContentRect: frame
              styleMask : styleMask
              backing:NSBackingStoreBuffered
              defer:NO];

      if (!window) {
        return false;
      }

      // Set the window title as Vuron Enigne
      [window setTitle:@"Vuron Engine"];
      // Bring the window to the front of the screen when opened
      [window makeKeyAndOrderFront:nil];
      // Saving the handle for later use in update and close functions
      m_windowHandle = (void*)window;

      return true;

    }

    // Closing function
    // We managing our own memory, we manually call close without Automatic
    // Reference Counting. Because 'alloc' must eventually 'release', we use this instead
    void MacWindow::close() {
      if (m_windowHandle) {
        // Casting back from void* to the actual Mac obj
        NSWindow* window = (NSWindow*)m_windowHandle;
        // Tell the OS to close the window
        [window close];
        // Set it back to nullptr so we don't close it twice
        m_windowHandle = nullptr;
      }
    }

    // Update function *VERY IMPORTANT*
    void MacWindow::update() {
      // We're casting the handle so we can talk to the window directly
      NSWindow* window = (NSWindow*)m_windowHandle;
      // This is the main "Event Loop" which pulls messages from the MacOS queue
      NSEvent* event;
      while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
              untilDate:[NSDate distantPast]
              inMode:NSDefaultRunLoopMode
              dequeue:YES]))

      {
        // Send the event to the OS to handle basic events like moving the window
        [NSApp sendEvent:event];
      }
    }
}