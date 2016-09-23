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

private class ParallelContext : ExecutionContextBase, ExecutionContextProtocol {
    let id = NSUUID()
    
    func runAsync(task:SafeTask) {
        do {
            try Thread.detach {
                if (!RunLoop.trySetFactory {
                    return RunLoop()
                }) {
                    print("unable to set run loop")
                    exit(1)
                }
                
                guard let loop = RunLoop.current as? RunnableRunLoopProtocol else {
                    print("unable to run run loop")
                    exit(1)
                }
                
                loop.execute(task: task)
                
                let _ = loop.run()
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
        runAsync(task: task)
    }
    
    func async(after:Timeout, task:SafeTask) {
        runAsync {
            RunLoop.current!.execute(delay: after, task: task)
        }
    }
    
    func sync<ReturnType>(task:TaskWithResult<ReturnType>) rethrows -> ReturnType {
        return try syncThroughAsync(task: task)
    }
    
    func isEqual(to other: NonStrictEquatable) -> Bool {
        guard let other = other as? ParallelContext else {
            return false
        }
        return id.isEqual(other.id)
    }
}

private class SerialContext : ExecutionContextBase, ExecutionContextProtocol {
    private let loop:RunnableRunLoopProtocol
    
    override init() {
        let sema = BlockingSemaphore()
        let loop = MutableAnyContainer<RunnableRunLoopProtocol?>(nil)
        
        //yeah, fail for now
        try! Thread.detach {
            var _loop = (RunLoop.current as! RunnableRunLoopProtocol)
            loop.content = _loop
            
            let _ = sema.signal()
            
            _loop.protected = true
            let _ = _loop.run()
        }
        
        let _ = sema.wait()
        
        self.loop = loop.content!
    }
    
    init(runLoop:RunLoopProtocol) {
        loop = runLoop as! RunnableRunLoopProtocol
    }
    
    deinit {
        var loop = self.loop
        loop.execute {
            loop.protected = false
            loop.stop()
        }
    }
    
    func async(task:SafeTask) {
        loop.execute(task: task)
    }
    
    func async(after:Timeout, task:SafeTask) {
        loop.execute(delay: after, task: task)
    }
    
    func sync<ReturnType>(task:TaskWithResult<ReturnType>) rethrows -> ReturnType {
        return try loop.sync(task: task)
    }
    
    func isEqual(to other: NonStrictEquatable) -> Bool {
        guard let other = other as? SerialContext else {
            return false
        }
        return loop.isEqual(to: other.loop)
    }
}

private extension ExecutionContextKind {
    func createInnerContext() -> ExecutionContextProtocol {
        switch self {
        case .serial:
            return SerialContext()
        case .parallel:
            return ParallelContext()
        }
    }
}

public class RunLoopExecutionContext : ExecutionContextBase, ExecutionContextProtocol, DefaultExecutionContextProtocol {
    let inner:ExecutionContextProtocol
    
    init(inner:ExecutionContextProtocol) {
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
        inner.async(after: after) {
            currentContext.value = self
            task()
        }
    }
    
    public func sync<ReturnType>(task:TaskWithResult<ReturnType>) rethrows -> ReturnType {
        if self.isCurrent {
            return try task()
        }
        return try inner.sync {
            currentContext.value = self
            return try task()
        }
    }
    
    public func isEqual(to other: NonStrictEquatable) -> Bool {
        guard let other = other as? RunLoopExecutionContext else {
            return false
        }
        return inner.isEqual(to: other.inner)
    }
    
    public static let main:ExecutionContextProtocol = RunLoopExecutionContext(inner: SerialContext(runLoop: RunLoop.main))
    public static let global:ExecutionContextProtocol = RunLoopExecutionContext(kind: .parallel)
    
    
    public static func mainProc() -> Never {
        if !Thread.isMain {
            print("Main proc was called on non-main thread. Exiting")
            exit(1)
        }
        var loop = (RunLoop.reactive.main as! RunnableRunLoopProtocol)
        loop.protected = true
        while true {
            //Should we exit here somehow? quit the process?
            let _ = loop.run()
        }
    }
}
