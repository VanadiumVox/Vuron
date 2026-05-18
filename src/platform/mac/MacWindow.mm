#include "MacWindow.h"
#import <Cocoa/Cocoa.h> // import = Objective-C version of include
#include "../../renderer/MetalRenderer.h"
#include "../../core/Memory.h"
#include <new> // For placement new

namespace vuron
{
	// This is a Static Callback function. It allows the Mac's OS to call
	// it whenever it wants. It doesn't belong to any one specific object since
	// it's static. So we've "snuck" a pointer to MacWindow into it by casting
	// the context back into the MacWindow.
	static CVReturn VuronDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                         const CVTimeStamp* inNow,
                                         const CVTimeStamp* inOutputTime,
                                         CVOptionFlags flagsIn,
                                         CVOptionFlags* flagsOut,
                                         void* displayLinkContext)
    {
          // This is the "Heartbeat"
          // We cast our 'context' back into a MacWindow
          vuron::MacWindow* window = (vuron::MacWindow*)displayLinkContext;
          // This triggers the update logic
          window->renderFrame();
          // Return success
          return kCVReturnSuccess;
    }

    bool MacWindow::init(MemoryArena& arena){
      // Initializing the global NSApp obj if it hasn't been already
      [NSApplication sharedApplication];
      // This just tells the OS that this is a regular "app"
      [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

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

      if (!window) return false;

      // Window creation code
      // Set the window title as Vuron Enigne
      [window setTitle:@"Vuron Engine"];
      // Bring the window to the front of the screen when opened
      [window makeKeyAndOrderFront:nil];
      // Brings the Vuron window to the front when we activate the engine
      [NSApp activateIgnoringOtherApps:YES];

      // Saving the handle for later use in update and close functions
      m_windowHandle = (void*)window;

      // ALlocate the new Metal Renderer straight out of the Permanent Arena
      void* rendererMemory = arena.push(sizeof(MetalRenderer));
      m_renderer = new (rendererMemory) MetalRenderer();

      if (!m_renderer->init(m_windowHandle)) return false;

      // Initialize CVDisplayLink here if it's nto already active
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

    void MacWindow::renderFrame() {
      // This is for the 3D rendering and logic
      if (m_renderer) m_renderer->drawFrame();
    }
}