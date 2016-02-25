//===--- ExecutionContext.swift ------------------------------------------------------===//
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

#if !os(Linux) || dispatch
    import Dispatch
#endif

public typealias Task = () throws -> Void
public typealias SafeTask = () -> Void

// return true if error successfully handled, false otherwise
public typealias ErrorHandler = (e:ErrorType) throws -> Bool

private func stockErrorHandler(e:ErrorType) throws -> Bool {
    let errorName = Mirror(reflecting: e).description
    print(errorName, " was thrown but not handled")
    return true
}

public protocol ErrorHandlerRegistryType {
    var errorHandlers:[ErrorHandler] {get}
    
    func registerErrorHandler(handler:ErrorHandler)
}

public protocol TaskSchedulerType {
    func async(task:Task)
    func async(task:SafeTask)
    
    //after is in seconds
    func async(after:Double, task:Task)
    func async(after:Double, task:SafeTask)
    
    func sync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType
    func sync<ReturnType>(task:() -> ReturnType) -> ReturnType
}

public protocol ExecutionContextType : TaskSchedulerType, ErrorHandlerRegistryType {
    func execute(task:SafeTask)
}

public extension ExecutionContextType {
    func execute(task:SafeTask) {
        async(task)
    }
}

public typealias Executor = (SafeTask)->Void

public class ExecutionContextBase : ErrorHandlerRegistryType {
    public var errorHandlers = [ErrorHandler]()
    
    public init() {
        errorHandlers.append(stockErrorHandler)
    }
    
    public func registerErrorHandler(handler:ErrorHandler) {
        //keep last one as it's stock
        errorHandlers.insert(handler, atIndex: errorHandlers.endIndex.advancedBy(-1))
    }
}

public extension ErrorHandlerRegistryType where Self : TaskSchedulerType {
    func handleError(e:ErrorType) {
        for handler in errorHandlers {
            do {
                if try handler(e: e) {
                    break
                }
            } catch let e {
                handleError(e)
                break
            }
        }
    }
    
    public func async(task:Task) {
        //specify explicitely, that it's safe task
        async { () -> Void in
            do {
                try task()
            } catch let e {
                self.handleError(e)
            }
        }
    }
    
    //after is in seconds
    func async(after:Double, task:Task) {
        //specify explicitely, that it's safe task
        async(after) { () -> Void in
            do {
                try task()
            } catch let e {
                self.handleError(e)
            }
        }
    }
}

public extension TaskSchedulerType {
    public func sync<ReturnType>(task:() -> ReturnType) -> ReturnType {
        return try! sync { () throws -> ReturnType in
            return task()
        }
    }
}

public enum ExecutionContextKind {
    case Serial
    case Parallel
}

public typealias ExecutionContext = DefaultExecutionContext

extension ExecutionContextType {
    func syncThroughAsync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType {
        var result:Result<ReturnType, AnyError>?
        
        let sema = LoopSemaphore()
        sema.willUse()
        defer {
            sema.didUse()
        }
        
        async {
            result = materialize(task)
            sema.signal()
        }
        
        sema.wait()
        
        return try result!.dematerializeAnyError()
    }
}

public let immediate:ExecutionContextType = ImmediateExecutionContext()
public let main:ExecutionContextType = ExecutionContext.main
public let global:ExecutionContextType = ExecutionContext.global

public func executionContext(executor:Executor) -> ExecutionContextType {
    return CustomExecutionContext(executor: executor)
}

public func sleep(timeout:Double) {
    let sec = time_t(timeout)
    let nsec = Int((timeout - Double(sec)) * 1000 * 1000 * 1000)//nano seconds
    var time = timespec(tv_sec:sec, tv_nsec: nsec)
    
    nanosleep(&time, nil)
}

@noreturn public func executionContextMain() {
    #if !os(Linux) || dispatch
        dispatch_main()
    #else
        RunLoop.runForever()
    #endif
}