//===--- PThreadExecutionContext.swift ------------------------------------------------------===//
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





//////////////////////////////////////////////////////////////////////////
//This file is a temporary solution, just until Dispatch will run on Mac//
//////////////////////////////////////////////////////////////////////////
#if os(Linux)
    
    import Foundation
    import CoreFoundation
    import Result
    #if os(Linux)
        import Glibc
    #endif
    
    private func thread_proc(pm: UnsafeMutablePointer<Void>) -> UnsafeMutablePointer<Void> {
        let pthread = Unmanaged<PThread>.fromOpaque(COpaquePointer(pm)).takeRetainedValue()
        pthread.task?()
        return nil
    }

    private extension NSString {
        var cfString: CFString { return unsafeBitCast(self, CFString.self) }
    }
    
    private class PThread {
        let thread: UnsafeMutablePointer<pthread_t>
        let task:SafeTask?
        
        init(task:SafeTask? = nil) {
            self.task = task
            self.thread = UnsafeMutablePointer<pthread_t>.alloc(1)
        }
        deinit {
            self.thread.destroy()
            self.thread.dealloc(1)
        }
        
        func start() {
            pthread_create(thread, nil, thread_proc, UnsafeMutablePointer<Void>(Unmanaged.passRetained(self).toOpaque()))
        }
    }
    
    
    private class RunLoopFinalizer {
        private let rl: CFRunLoop!
        init(_ runLoop: CFRunLoop!) {
            self.rl = runLoop
        }
        deinit {
            CFRunLoopStop(rl)
        }
    }
    
    private class RunLoopObject {
        private var cfObject:AnyObject? = nil
        private let task:SafeTask
        private let finalizer:RunLoopFinalizer?
        
        init(_ task:SafeTask, runLoopFinalizer: RunLoopFinalizer?) {
            self.task = task
            self.finalizer = runLoopFinalizer
        }
        
        func addToRunLoop(runLoop:CFRunLoop, mode: CFString) {
            if cfObject == nil {
                self.cfObject = createCFObject()
            }
            addCFObject(runLoop, mode: mode)
        }
        
        func signal() {}

        private func createCFObject() -> AnyObject? { return nil }
        
        private func addCFObject(runLoop:CFRunLoop, mode: CFString) {}
    }

    private func sourceMain(rls: UnsafeMutablePointer<Void>) {
        let runLoopSource = Unmanaged<RunLoopObject>.fromOpaque(COpaquePointer(rls)).takeUnretainedValue()
        runLoopSource.cfObject = nil
        runLoopSource.task()
    }

    private func sourceCancel(rls: UnsafeMutablePointer<Void>, rL: CFRunLoop!, mode:CFString!) {
        let runLoopSource = Unmanaged<RunLoopObject>.fromOpaque(COpaquePointer(rls)).takeUnretainedValue()
        runLoopSource.cfObject = nil
    }

    private func sourceRetain(rls: UnsafePointer<Void>) -> UnsafePointer<Void> {
        Unmanaged<RunLoopObject>.fromOpaque(COpaquePointer(rls)).retain()
        return rls
    }

    private func sourceRelease(rls: UnsafePointer<Void>) {
        Unmanaged<RunLoopObject>.fromOpaque(COpaquePointer(rls)).release()
    }

    private class RunLoopSource : RunLoopObject {
        private let priority:Int

        init(_ task: SafeTask, priority: Int = 0, finalizer: RunLoopFinalizer?) {
            self.priority = priority
            super.init(task, runLoopFinalizer: finalizer)
        }

        deinit {
            if let s = cfObject as! CFRunLoopSource? {
                if CFRunLoopSourceIsValid(s) { CFRunLoopSourceInvalidate(s) }
            }
        }
        
        private override func createCFObject() -> AnyObject? {
            var context = CFRunLoopSourceContext(
                version: 0,
                info: UnsafeMutablePointer<Void>(Unmanaged.passUnretained(self).toOpaque()),
                retain: sourceRetain,
                release: sourceRelease,
                copyDescription: nil,
                equal: nil,
                hash: nil,
                schedule: nil,
                cancel: sourceCancel,
                perform: sourceMain
            )
            return CFRunLoopSourceCreate(nil, priority, &context)
        }
        
        private override func addCFObject(runLoop:CFRunLoop, mode: CFString) {
            CFRunLoopAddSource(runLoop, (cfObject as! CFRunLoopSource?)!, mode)
        }
        
        override func signal() {
            if let s = cfObject as! CFRunLoopSource? {
                CFRunLoopSourceSignal(s)
            }
        }
    }
    
    private func timerCallback(timer: CFRunLoopTimer!, rlt: UnsafeMutablePointer<Void>) {
        sourceMain(rlt)
    }
    
    private class RunLoopDelay : RunLoopObject {
        private let delay:CFTimeInterval
        
        init(_ task: SafeTask, delay: CFTimeInterval, finalizer: RunLoopFinalizer?) {
            self.delay = delay
            super.init(task, runLoopFinalizer: finalizer)
        }
        
        deinit {
            if let t = cfObject as! CFRunLoopTimer? {
                if CFRunLoopTimerIsValid(t) { CFRunLoopTimerInvalidate(t) }
            }
        }
        
        private override func createCFObject() -> AnyObject? {
            var context = CFRunLoopTimerContext(
                version: 0,
                info: UnsafeMutablePointer<Void>(Unmanaged.passUnretained(self).toOpaque()),
                retain: sourceRetain,
                release: sourceRelease,
                copyDescription: nil
            )
            return CFRunLoopTimerCreate(nil, CFAbsoluteTimeGetCurrent()+delay, -1, 0, 0, timerCallback, &context)
        }
        
        private override func addCFObject(runLoop:CFRunLoop, mode: CFString) {
            CFRunLoopAddTimer(runLoop, (cfObject as! CFRunLoopTimer?)!, mode)
        }
    }
    
    private class ParallelContext : ExecutionContextBase, ExecutionContextType {
        func async(task:SafeTask) {
            let thread = PThread(task: task)
            thread.start()
        }
        
        func async(after:Double, task:SafeTask) {
            let thread = PThread(task: {
                sleep(after)
                task()
            })
            thread.start()
        }
        
        func sync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType {
            return try syncThroughAsync(task)
        }
    }
    
#if !os(Linux)
    private let defaultMode:CFString = "kCFRunLoopDefaultMode" as NSString
#else
    private let defaultMode:CFString = "kCFRunLoopDefaultMode".bridge().cfString
#endif
    
    private class SerialContext : ExecutionContextBase, ExecutionContextType {
        private let rl:CFRunLoop!
        private let finalizer: RunLoopFinalizer?
        
        override init() {
            var runLoop:CFRunLoop?
            let cond = NSCondition()
            cond.lock()
            let thread = PThread(task: {
                runLoop = CFRunLoopGetCurrent()
                cond.signal()
                SerialContext.defaultLoop()
            })
            thread.start()
            cond.wait()
            cond.unlock()
            self.rl = runLoop!
            finalizer = RunLoopFinalizer(self.rl)
        }
        
        init(runLoop:CFRunLoop!) {
            rl = runLoop
            finalizer = nil
        }
        
        #if !os(Linux)
        static func defaultLoop() {
            while CFRunLoopRunInMode(defaultMode, 0, true) != .Stopped {}
        }
        #else
        static func defaultLoop() {
            while CFRunLoopRunInMode(defaultMode, 0, true) != Int32(kCFRunLoopRunStopped) {}
        }
        #endif

        private func performRunLoopObject(rlo: RunLoopObject) {
            rlo.addToRunLoop(rl, mode: SerialContext.defaultMode)
            rlo.signal()
            CFRunLoopWakeUp(rl)
        }
        
        func async(task:SafeTask) {
            performRunLoopObject(RunLoopSource(task, finalizer: finalizer))
        }
        
        func async(after:Double, task:SafeTask) {
            performRunLoopObject(RunLoopDelay(task, delay: after, finalizer: finalizer))
        }
        
        func sync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType {
            if rl === CFRunLoopGetCurrent() {
                return try task()
            } else {
                return try syncThroughAsync(task)
            }
        }
    }
    
    public class PThreadExecutionContext : ExecutionContextBase, ExecutionContextType, DefaultExecutionContextType {
        let inner:ExecutionContextType
        
        init(inner:ExecutionContextType) {
            self.inner = inner
        }
        
        public required init(kind:ExecutionContextKind) {
            switch kind {
            case .Serial: inner = SerialContext()
            case .Parallel: inner = ParallelContext()
            }
        }
        
        public func async(task:SafeTask) {
            inner.async(task)
        }
        
        public func sync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType {
            return try inner.sync(task)
        }
        
        public func async(after:Double, task:SafeTask) {
            inner.async(after, task: task)
        }
        
        public static let main:ExecutionContextType = PThreadExecutionContext(inner: SerialContext(runLoop: CFRunLoopGetMain()))
        public static let global:ExecutionContextType = PThreadExecutionContext(kind: .Parallel)
    }

#endif
