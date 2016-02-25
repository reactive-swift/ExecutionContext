//===--- LoopSemaphore.swift -----------------------------------------------===//
//Copyright (c) 2016 Daniel Leping (dileping)
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//http://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
//===----------------------------------------------------------------------===//

import Foundation
import CoreFoundation

#if !os(Linux) || dispatch
    import Dispatch

    public class DispatchLoopSemaphore : SemaphoreType {
        let sema:dispatch_semaphore_t
    
        public required convenience init() {
            self.init(value: 0)
        }
    
        public required init(value: Int) {
            self.sema = dispatch_semaphore_create(value)
        }
    
        public func wait() -> Bool {
            return dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER) == 0
        }
    
        public func wait(until:NSDate?) -> Bool {
            let timeout = until?.timeIntervalSinceNow
            return wait(timeout)
        }
    
        public func wait(timeout: Double?) -> Bool {
            guard let timeout = timeout else {
                return wait()
            }
            let time = dispatch_time(DISPATCH_TIME_NOW, Int64(timeout * NSTimeInterval(NSEC_PER_SEC)))
            let result = dispatch_semaphore_wait(sema, time)
            return result == 0
        }
    
        public func signal() -> Int {
            return dispatch_semaphore_signal(sema)
        }
    }
#endif

extension Optional {
    func getOrElse(@autoclosure f:()->Wrapped) -> Wrapped {
        switch self {
        case .Some(let value):
            return value
        case .None:
            return f()
        }
    }
}

public class CFRunLoopSemaphore : SemaphoreType {
    var source: RunLoopSource?
    var signaled: Bool
    
    private(set) public var value: Int
    
    /// Creates a new semaphore with the given initial value
    /// See NSCondition and https://developer.apple.com/library/prerelease/mac/documentation/Cocoa/Conceptual/Multithreading/ThreadSafety/ThreadSafety.html#//apple_ref/doc/uid/10000057i-CH8-SW13
    public required init(value: Int) {
        self.value = value
        self.signaled = false
        self.source = RunLoopSource( { [unowned self] in
            self.signaled = true
            self.value += 1
            // On linux timeout not working in run loop
            #if os(Linux)
                CFRunLoopStop(CFRunLoopGetCurrent())
            #endif
        }, priority: 2)
    }
    
    /// Creates a new semaphore with initial value 0
    /// This kind of semaphores is useful to protect a critical section
    public convenience required init() {
        self.init(value: 0)
    }
    
    public func wait() -> Bool {
        return wait(nil)
    }
    
    /// returns true on success (false if timeout expired)
    /// if nil is passed - waits forever
    public func wait(until:NSDate?) -> Bool {
        let until = until.getOrElse(NSDate.distantFuture())
        
        defer {
            self.signaled = false
        }
        
        var timedout:Bool = false
        
        while value <= 0 {
            while !self.signaled && !timedout {
                RunLoop.runUntilOnce(RunLoop.defaultMode, until: until)
                timedout = until.timeIntervalSinceNow <= 0
            }
            if timedout {
                break
            }
        }
        
        if signaled {
            value -= 1
        }
        
        return signaled
    }
    
    /// Performs the signal operation on this semaphore
    public func signal() -> Int {
        source?.signal()
        return value
    }
    
    public func willUse() {
        let loop:RunLoop = RunLoop.currentRunLoop()
        loop.addSource(source!, mode: RunLoop.defaultMode)
    }
    
    public func didUse() {
        let loop:RunLoop = RunLoop.currentRunLoop()
        loop.removeSource(source!, mode: RunLoop.defaultMode)
    }
}

#if !os(Linux) || dispatch
    public typealias LoopSemaphore = DispatchLoopSemaphore
#else
    public typealias LoopSemaphore = CFRunLoopSemaphore
#endif
