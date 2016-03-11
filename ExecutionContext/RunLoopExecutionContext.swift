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

private class ParallelContext : ExecutionContextBase, ExecutionContextType {
    func runAsync(task:SafeTask) {
        do {
            try Thread.detach {
                if (!RunLoop.trySetFactory {
                    return RunLoop()
                }) {
                    print("unable to set run loop")
                    exit(1)
                }
                
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
    
    func sync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
        return try syncThroughAsync(task)
    }
}

private class SerialContext : ExecutionContextBase, ExecutionContextType {
    private let loop:RunnableRunLoopType
    
    override init() {
        let sema = BlockingSemaphore()
        let loop = MutableAnyContainer<RunnableRunLoopType?>(nil)
        
        //yeah, fail for now
        try! Thread.detach {
            var _loop = (RunLoop.current as! RunnableRunLoopType)
            loop.content = _loop
            
            sema.signal()
            
            _loop.protected = true
            _loop.run()
        }
        
        sema.wait()
        
        self.loop = loop.content!
    }
    
    init(runLoop:RunLoopType) {
        loop = runLoop as! RunnableRunLoopType
    }
    
    deinit {
        var rl = self.loop
        rl.execute {
            rl.protected = false
            rl.stop()
        }
    }
    
    func async(task:SafeTask) {
        loop.execute(task)
    }
    
    func async(after:Double, task:SafeTask) {
        loop.execute(Timeout(timeout: after), task: task)
    }
    
    func sync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
        return try loop.sync(task)
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
    
    public func sync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
        return try inner.sync(task)
    }
    
    public func async(after:Double, task:SafeTask) {
        inner.async(after, task: task)
    }
    
    public static let main:ExecutionContextType = RunLoopExecutionContext(inner: SerialContext(runLoop: RunLoop.main))
    public static let global:ExecutionContextType = RunLoopExecutionContext(kind: .Parallel)
}