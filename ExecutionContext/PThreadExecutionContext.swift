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
//#if os(Linux)
    
    import Foundation
    import Result
    #if os(Linux)
        import Glibc
    #endif
    
    private func thread_proc(pm: UnsafeMutablePointer<Void>) -> UnsafeMutablePointer<Void> {
        let pthread = Unmanaged<PThread>.fromOpaque(COpaquePointer(pm)).takeRetainedValue()
        pthread.task?()
        return nil
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
    
    private class SerialContext : ExecutionContextBase, ExecutionContextType {
        private let rl:RunLoop
        
        override init() {
            var runLoop:AnyObject?
            let sema = Semaphore()
            
            PThread(task: {
                runLoop = RunLoop.currentCFRunLoop()
                sema.signal()
                RunLoop.run()
            }).start()
            
            sema.wait()

            self.rl = RunLoop(runLoop!, autoStop: true)
        }
        
        init(runLoop:RunLoop) {
            rl = runLoop
        }
        
        func async(task:SafeTask) {
            rl.addSource(RunLoopSource(task), mode: RunLoop.defaultMode)
        }
        
        func async(after:Double, task:SafeTask) {
            rl.addDelay(RunLoopDelay(task, delay: after), mode: RunLoop.defaultMode)
        }
        
        func sync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType {
            if rl.isCurrent() {
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
        
        public static let main:ExecutionContextType = PThreadExecutionContext(inner: SerialContext(runLoop: RunLoop.mainRunLoop()))
        public static let global:ExecutionContextType = PThreadExecutionContext(kind: .Parallel)
    }

//#endif
