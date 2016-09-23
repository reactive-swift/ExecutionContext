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
import Boilerplate
import RunLoop

private class ParallelContext : ExecutionContextBase, ExecutionContextType {
    let id = NSUUID()
    
    func runAsync(task:SafeTask) {
        do {
            try Thread.detach {
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
    
    func async(after:Timeout, task:SafeTask) {
        runAsync {
            RunLoop.current.execute(after, task: task)
        }
    }
    
    func sync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
        return try syncThroughAsync(task)
    }
    
    func isEqualTo(other: NonStrictEquatable) -> Bool {
        guard let other = other as? ParallelContext else {
            return false
        }
        return id.isEqual(other.id)
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
        var loop = self.loop
        loop.execute {
            loop.protected = false
            loop.stop()
        }
    }
    
    func async(task:SafeTask) {
        loop.execute(task)
    }
    
    func async(after:Timeout, task:SafeTask) {
        loop.execute(after, task: task)
    }
    
    func sync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
        return try loop.sync(task)
    }
    
    func isEqualTo(other: NonStrictEquatable) -> Bool {
        guard let other = other as? SerialContext else {
            return false
        }
        return loop.isEqualTo(other.loop)
    }
}

private extension ExecutionContextKind {
    func createInnerContext() -> ExecutionContextType {
        switch self {
        case .serial:
            return SerialContext()
        case .parallel:
            return ParallelContext()
        }
    }
}

public class RunLoopExecutionContext : ExecutionContextBase, ExecutionContextType, DefaultExecutionContextType {
    let inner:ExecutionContextType
    
    init(inner:ExecutionContextType) {
        self.inner = inner
    }
    
    public required convenience init(kind:ExecutionContextKind) {
        self.init(inner: kind.createInnerContext())
    }
    
    public func async(task:SafeTask) {
        inner.async {
            currentContext.value = self
            task()
        }
    }
    
    public func async(after:Timeout, task:SafeTask) {
        inner.async(after) {
            currentContext.value = self
            task()
        }
    }
    
    public func sync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
        if self.isCurrent {
            return try task()
        }
        return try inner.sync {
            currentContext.value = self
            return try task()
        }
    }
    
    public func isEqualTo(other: NonStrictEquatable) -> Bool {
        guard let other = other as? RunLoopExecutionContext else {
            return false
        }
        return inner.isEqualTo(other.inner)
    }
    
    public static let main:ExecutionContextType = RunLoopExecutionContext(inner: SerialContext(runLoop: RunLoop.main))
    public static let global:ExecutionContextType = RunLoopExecutionContext(kind: .parallel)
    
    @noreturn
    public static func mainProc() {
        if !Thread.isMain {
            print("Main proc was called on non-main thread. Exiting")
            exit(1)
        }
        var loop = (RunLoop.main as! RunnableRunLoopType)
        loop.protected = true
        while true {
            loop.run()
        }
    }
}