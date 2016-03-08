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
                CoreFoundationRunLoop.runUntilOnce(CoreFoundationRunLoop.defaultMode, until: until)
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
        let loop:CoreFoundationRunLoop = CoreFoundationRunLoop.currentRunLoop()
        loop.addSource(source!, mode: CoreFoundationRunLoop.defaultMode)
    }
    
    public func didUse() {
        let loop:CoreFoundationRunLoop = CoreFoundationRunLoop.currentRunLoop()
        loop.removeSource(source!, mode: CoreFoundationRunLoop.defaultMode)
    }
}

import RunLoop
import Boilerplate

extension RunnableRunLoopType {
    func runWithConditionalDate(until:NSDate?) -> Bool {
        if let until = until {
            return self.run(Timeout(until: until))
        } else {
            return self.run()
        }
    }
}

class HashableAnyContainer<T> : AnyContainer<T>, Hashable {
    let hashValue: Int = random()
    
    override init(_ item: T) {
        super.init(item)
    }
}

func ==<T>(lhs:HashableAnyContainer<T>, rhs:HashableAnyContainer<T>) -> Bool {
    return lhs.hashValue == rhs.hashValue
}

public class RunLoopSemaphore : SemaphoreType {
    private var signals:[HashableAnyContainer<SafeTask>]
    private let lock:NSLock
    private var value:Int
    
    public required convenience init() {
        self.init(value: 0)
    }
    
    public required init(value: Int) {
        self.value = value
        signals = Array()
        lock = NSLock()
    }
    
    public func wait() -> Bool {
        return wait(nil)
    }
    
    public func wait(until:NSDate?) -> Bool {
        lock.lock()
        value -= 1
        defer {
            lock.unlock()
        }
        
        if value >= 0 {
            value += 1
            return true
        }
        
        var signaled = false
        var timedout = false
        
        let rl = RunLoop.current as! RunnableRunLoopType
        
        let signal = HashableAnyContainer {
            rl.execute {
                signaled = true
                rl.stop()
            }
        }
        
        signals.append(signal)
        
        while value < 0 {
            lock.unlock()
            defer {
                lock.lock()
            }
            while !signaled && !timedout {
                timedout = rl.runWithConditionalDate(until)
            }
            
            if timedout {
                break
            }
        }
        
        let index = signals.indexOf { element in
            element == signal
        }
        if let index = index {
            signals.removeAtIndex(index)
        }
        
        return signaled
    }
    
    public func signal() -> Int {
        lock.lock()
        value += 1
        let signal:AnyContainer<SafeTask>? = signals.isEmpty ? nil : signals.removeFirst()
        lock.unlock()
        signal?.content()
        return 1
    }
}

#if !os(Linux) || dispatch
    public typealias LoopSemaphore = RunLoopSemaphore
#else
    public typealias LoopSemaphore = CFRunLoopSemaphore
#endif
