//===--- RunLoopExecutionContext.swift -----------------------------------------------===//
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
import Result
import Boilerplate
import RunLoop

private func thread_proc(arg: UnsafeMutablePointer<Void>) -> UnsafeMutablePointer<Void> {
    let task = Unmanaged<AnyContainer<SafeTask>>.fromOpaque(COpaquePointer(arg)).takeRetainedValue()
    task.content()
    return nil
}

private func detach_pthread(task:SafeTask) throws {
    var thread:pthread_t = pthread_t()
    let unmanaged = Unmanaged.passRetained(AnyContainer(task))
    let arg = UnsafeMutablePointer<Void>(unmanaged.toOpaque())
    do {
        try ccall(CError.self) {
            pthread_create(&thread, nil, thread_proc, arg)
        }
    } catch {
        unmanaged.release()
        throw error
    }
}

private class ParallelContext : ExecutionContextBase, ExecutionContextType {
    func runAsync(task:SafeTask) {
        do {
            try detach_pthread {
/*                if (!RunLoop.trySetFactory {
                    return RunLoop()
                }) {
                    print("unable to set run loop")
                    exit(1)
                }*/
                
                guard let loop = RunLoop.current as? RunnableRunLoopType else {
                    print("unable to run run loop")
                    exit(1)
                }
                
                loop.execute(task)
                
                loop.run()
            }
        } catch let e as CError {
            switch e {
            case .Unknown:
                print("Got unknown CError while creating pthread")
            case .Code(let code):
                print("Got CError with code \(code) while creating pthread")
            }
        } catch {
            print("Got Unknown error while creating pthread: ", error)
        }
    }
    
    func async(task:SafeTask) {
        runAsync(task)
    }
    
    func async(after:Double, task:SafeTask) {
        runAsync {
            RunLoop.current.execute(Timeout(timeout: after), task: task)
        }
    }
    
    func sync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType {
        return try syncThroughAsync(task)
    }
}

private class SerialContext : ExecutionContextBase, ExecutionContextType {
    private let rl:RunnableRunLoopType
    
    override init() {
        let sema = Semaphore()
        let loop = MutableAnyContainer<RunnableRunLoopType?>(nil)
        
        //yeah, fail for now
        try! detach_pthread {
            loop.content = (RunLoop.current as! RunnableRunLoopType)
            sema.signal()
            
            (RunLoop.current as! RunnableRunLoopType).run()
        }
        
        sema.wait()
        
        self.rl = loop.content!
    }
    
    init(runLoop:RunLoopType) {
        rl = runLoop as! RunnableRunLoopType
    }
    
    deinit {
        let rl = self.rl
        rl.execute {
            rl.stop()
        }
    }
    
    func async(task:SafeTask) {
        rl.execute(task)
    }
    
    func async(after:Double, task:SafeTask) {
        rl.execute(Timeout(timeout: after), task: task)
    }
    
    func sync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType {
        if rl.isEqualTo(RunLoop.current) {
            return try task()
        } else {
            return try syncThroughAsync(task)
        }
    }
}

public class RunLoopExecutionContext : ExecutionContextBase, ExecutionContextType, DefaultExecutionContextType {
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
    
    public static let main:ExecutionContextType = PThreadExecutionContext(inner: SerialContext(runLoop: RunLoop.main))
    public static let global:ExecutionContextType = PThreadExecutionContext(kind: .Parallel)
}