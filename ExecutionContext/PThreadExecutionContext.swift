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

    private func sourceMain(rls: UnsafeMutablePointer<Void>) {
        let runLoopSource = Unmanaged<RunLoopSource>.fromOpaque(COpaquePointer(rls)).takeUnretainedValue()
        runLoopSource.cfSource = nil
        runLoopSource.task()
    }

    private func sourceCancel(rls: UnsafeMutablePointer<Void>, rL: CFRunLoop!, mode:CFString!) {
        let runLoopSource = Unmanaged<RunLoopSource>.fromOpaque(COpaquePointer(rls)).takeUnretainedValue()
        runLoopSource.cfSource = nil
    }

    private func sourceRetain(rls: UnsafePointer<Void>) -> UnsafePointer<Void> {
        Unmanaged<RunLoopSource>.fromOpaque(COpaquePointer(rls)).retain()
        return rls
    }

    private func sourceRelease(rls: UnsafePointer<Void>) {
        Unmanaged<RunLoopSource>.fromOpaque(COpaquePointer(rls)).release()
    }

    private class RunLoopSource {
        private var cfSource:CFRunLoopSource? = nil
        private let task:SafeTask
        private let priority:Int

        init(_ task: SafeTask, priority: Int = 0) {
            self.task = task
            self.priority = priority
        }

        deinit {
            if let s = cfSource {
                if CFRunLoopSourceIsValid(s) { CFRunLoopSourceInvalidate(s) }
            }
        }

        func addToRunLoop(runLoop:CFRunLoop, mode: CFString) {
            if cfSource == nil {
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
                self.cfSource = CFRunLoopSourceCreate(nil, priority, &context)
            }
            
            CFRunLoopAddSource(runLoop, cfSource!, mode)
        }

        func signal() {
            if let s = cfSource {
                CFRunLoopSourceSignal(s)
            }
        }
    }
    
    private extension ExecutionContextType {
        func syncThroughAsync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType {
            var result:Result<ReturnType, AnyError>?
            
            let cond = NSCondition()
            cond.lock()

            async {
                result = materialize(task)
                cond.signal()
            }
            
            cond.wait()
            cond.unlock()
            
            return try result!.dematerializeAnyError()
        }
    }
    
    private class ParallelContext : ExecutionContextBase, ExecutionContextType {
        func async(task:SafeTask) {
            let thread = PThread(task: task)
            thread.start()
        }
        
        func sync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType {
            return try syncThroughAsync(task)
        }
    }
    
    private class SerialContext : ExecutionContextBase, ExecutionContextType {
        private let rl:CFRunLoop!
        private let ownRunLoop:Bool

        #if !os(Linux)
        private static let defaultMode:CFString = "kCFRunLoopDefaultMode" as NSString
        #else
        private static let defaultMode:CFString = "kCFRunLoopDefaultMode".bridge().cfString
        #endif
        
        override init() {
            ownRunLoop = true
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
        }
        
        init(runLoop:CFRunLoop!) {
            ownRunLoop = false
            rl = runLoop
        }

        deinit {
            if ownRunLoop {
                let runLoop = rl
                performRunLoopSource(RunLoopSource({
                        CFRunLoopStop(runLoop)
                    },
                    priority: -32768)
                )
            }
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

        private func performRunLoopSource(rls: RunLoopSource) {
            rls.addToRunLoop(rl, mode: SerialContext.defaultMode)
            rls.signal()
        }
        
        func async(task:SafeTask) {
            performRunLoopSource(RunLoopSource(task))
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
        
        public static let main:ExecutionContextType = PThreadExecutionContext(inner: SerialContext(runLoop: CFRunLoopGetMain()))
        public static let global:ExecutionContextType = PThreadExecutionContext(kind: .Parallel)
    }

#endif
