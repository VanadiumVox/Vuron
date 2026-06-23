#include "MacWindow.h"
#import <Cocoa/Cocoa.h> // import = Objective-C version of include
#import <CoreVideo/CVDisplayLink.h>
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
      // Forcing MacOS to treat this as a normal app with its own icon and all
      [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
      // This just tells the OS that this is a regular "app"
      [NSApp finishLaunching];

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

      // The closing 'x' button code
      // Listens for the OS notification saying that the window's closing
      [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
                                                  object:window
                                                  queue:nil
                                                  usingBlock:^(NSNotification *notification){
         exit(0);
       }];

      // ALlocate the new Metal Renderer straight out of the Permanent Arena
      void* rendererMemory = arena.push(sizeof(MetalRenderer));
      m_renderer = new (rendererMemory) MetalRenderer();

      if (!m_renderer->init(m_windowHandle)) return false;

      // Initialize CVDisplayLink here if it's nto already active
      CVDisplayLinkCreateWithActiveCGDisplays((CVDisplayLinkRef*)&m_displayLink);
      CVDisplayLinkSetOutputCallback((CVDisplayLinkRef)m_displayLink, &VuronDisplayLinkCallback, this);
      CVDisplayLinkStart((CVDisplayLinkRef)m_displayLink);
      m_running = true;
      return true;

    }

    // Closing function
    // We managing our own memory, we manually call close without Automatic
    // Reference Counting. Because 'alloc' must eventually 'release', we use this instead
    void MacWindow::close() {
      // Clean up the "heartbeat"
      if (m_displayLink) {
        CVDisplayLinkStop((CVDisplayLinkRef)m_displayLink);
        CVDisplayLinkRelease((CVDisplayLinkRef)m_displayLink);
      }

      // Clean up the Metal
      if (m_renderer) {
        m_renderer->shutdown();
      }
    }

    //Update function *VERY IMPORTANT*
    void MacWindow::update() {

      // This pool prevents OS window events from leaking memory every frame
      @autoreleasepool {
      // This is the main "Event Loop" which pulls messages from the MacOS queue
      NSEvent* event;
      // Hide the cursor and disconnect it from the OS screen edges
      CGAssociateMouseAndMouseCursorPosition(NO);
      [NSCursor hide];

      while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
              untilDate:[NSDate distantPast]
              inMode:NSDefaultRunLoopMode
              dequeue:YES]))
      {
        // A flag to track if Vuron is eating the input
        bool handled = false;

        // -=Raw hardware input interception=-
        if (event.type == NSEventTypeKeyDown) {
            // Convert the keystroke into a string
            NSString* chars = [[event charactersIgnoringModifiers] lowercaseString];

            // Engine Killswitch (cmd + q)
            if ([chars isEqualToString:@"q"] && ([event modifierFlags] & NSEventModifierFlagCommand)) {
                exit(0);
            }

            // Route the movement keys directly to the Renderer's input bridge
            if ([chars isEqualToString:@"w"]) {m_renderer->setKeyState('w', true); handled = true;}
            if ([chars isEqualToString:@"a"]) {m_renderer->setKeyState('a', true); handled = true;}
            if ([chars isEqualToString:@"s"]) {m_renderer->setKeyState('s', true); handled = true;}
            if ([chars isEqualToString:@"d"]) {m_renderer->setKeyState('d', true); handled = true;}
            if ([chars isEqualToString:@" "]) {m_renderer->setKeyState(' ', true); handled = true;}
            if ([chars isEqualToString:@"r"]) {m_renderer->setKeyState('r', true); handled = true;}
            NSString *unmodifiedChars = [[event charactersIgnoringModifiers] lowercaseString];
            if ([unmodifiedChars isEqualToString:@"v"] && ([event modifierFlags] & NSEventModifierFlagControl)) {
                m_renderer->toggleDebugMenu();
                handled = true;
            }
        }
        // When the key is released, stop movement instantly
        else if (event.type == NSEventTypeKeyUp) {
            NSString* chars = [[event charactersIgnoringModifiers] lowercaseString];
            if ([chars isEqualToString:@"w"]) {m_renderer->setKeyState('w', false); handled = true;}
            if ([chars isEqualToString:@"a"]) {m_renderer->setKeyState('a', false); handled = true;}
            if ([chars isEqualToString:@"s"]) {m_renderer->setKeyState('s', false); handled = true;}
            if ([chars isEqualToString:@"d"]) {m_renderer->setKeyState('d', false); handled = true;}
            if ([chars isEqualToString:@" "]) {m_renderer->setKeyState(' ', false); handled = true;}
            if ([chars isEqualToString:@"r"]) {m_renderer->setKeyState('r', false); handled = true;}
        }
        // Raw Mouse Intercept
        else if (event.type == NSEventTypeMouseMoved || event.type == NSEventTypeLeftMouseDragged || event.type == NSEventTypeRightMouseDragged) {
            // Read the raw physical delta from the hardware laser
            float dx = [event deltaX];
            float dy = [event deltaY];

            m_renderer->addMouseDelta(dx, dy);
            handled = true;
        }
        // --------------------------

        // --Modifier Key Intercept-- (Shift key)
        else if (event.type == NSEventTypeFlagsChanged) {
            // Check if the shift key is pressed
            bool isShift = ([event modifierFlags] & NSEventModifierFlagShift) != 0;

            // We pass 'C' to represent Crouch in our engine's input bridge
            m_renderer->setKeyState('C', isShift);
            handled = true;
        }
        // Send the event to the OS to handle basic events like moving the window
        // Only send the event to the OS if Vuron didn't need it
        if (!handled) {
            [NSApp sendEvent:event];
        }
      }
     }
    }

    // Called by the "heartbeat", displays the pixels
    void MacWindow::renderFrame() {
      // This is for the 3D rendering and logic
      if (m_renderer) m_renderer->drawFrame();
    }
}