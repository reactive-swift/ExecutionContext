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
import Boilerplate

#if os(Linux)
    import Glibc
#endif

#if !nodispatch
    import Dispatch
#endif

// return true if error successfully handled, false otherwise
public typealias ErrorHandler = (Error) throws -> Bool

private func stockErrorHandler(e:Error) throws -> Bool {
    let errorName = Mirror(reflecting: e).description
    print(errorName, " was thrown but not handled")
    return true
}

public protocol ErrorHandlerRegistry {
    var errorHandlers:[ErrorHandler] {get}
    
    func register(errorHandler:@escaping ErrorHandler)
}

public protocol TaskScheduler {
    func async(task:@escaping Task)
    func async(task:@escaping SafeTask)
    
    func async(after:Timeout, task:@escaping Task)
    func async(after:Timeout, task:@escaping SafeTask)
    
    //TODO: find a way of escaping/non-escaping enforcement. Logially sync is non-escaping
    func sync<ReturnType>(task:@escaping TaskWithResult<ReturnType>) rethrows -> ReturnType
}

public protocol ExecutionContextProtocol : TaskScheduler, ErrorHandlerRegistry, NonStrictEquatable {
    func execute(task:@escaping SafeTask)
    
    var kind:ExecutionContextKind {get}
    
    //in case of parallel contexts should return serial context bound to this parallel context. Returns self if already serial
    var serial:ExecutionContextProtocol {get}
    
    //in case of serial that is bound to a parallel context should return a parrallel context it is bound to. Returns "global" if it's not bound to any parallel context
    var parallel:ExecutionContextProtocol {get}
    
    static var current:ExecutionContextProtocol {get}
}

//DUMMY IMPLEMENTATION TO MAINTAIN BUILDABLE CODE. SUBJECT TO BE REMOVED ASAP
public extension ExecutionContextProtocol {
    public var kind:ExecutionContextKind {
        get {
            return .serial
        }
    }
    
    var serial:ExecutionContextProtocol {
        get {
            return self
        }
    }
    
    var parallel:ExecutionContextProtocol {
        get {
            return global
        }
    }
}

public extension ExecutionContextProtocol {
    public func execute(task:@escaping SafeTask) {
        async(task: task)
    }
    
    public var isCurrent:Bool {
        get {
            return Self.current.isEqual(to: self)
        }
    }
}

import RunLoop

public extension ExecutionContextProtocol {
    public func syncThroughAsync<ReturnType>(task:@escaping TaskWithResult<ReturnType>) rethrows -> ReturnType {
        if isCurrent {
            return try task()
        }
        
        return try {
            var result:Result<ReturnType, AnyError>?
            
            let sema = RunLoop.semaphore()
            
            async {
                result = materialize(task)
                let _ = sema.signal()
            }
            
            let _ = sema.wait()
            
            return try result!.dematerializeAny()
        }()
    }
}

public typealias Executor = (@escaping SafeTask)->Void

open class ExecutionContextBase : ErrorHandlerRegistry {
    public var errorHandlers = [ErrorHandler]()
    
    public init() {
        errorHandlers.append(stockErrorHandler)
    }
    
    public func register(errorHandler handler:@escaping ErrorHandler) {
        //keep last one as it's stock
        errorHandlers.insert(handler, at: errorHandlers.endIndex.advanced(by: -1))
    }
}

public extension ErrorHandlerRegistry where Self : TaskScheduler {
    func handle(error:Error) {
        for handler in errorHandlers {
            do {
                if try handler(error) {
                    break
                }
            } catch let e {
                handle(error: e)
                break
            }
        }
    }
    
    public func async(task:@escaping Task) {
        //specify explicitely, that it's safe task
        async { () -> Void in
            do {
                try task()
            } catch let e {
                self.handle(error: e)
            }
        }
    }
    
    //after is in seconds
    public func async(after:Timeout, task:@escaping Task) {
        //specify explicitely, that it's safe task
        async(after: after) { () -> Void in
            do {
                try task()
            } catch let e {
                self.handle(error: e)
            }
        }
    }
}

public enum ExecutionContextKind {
    case serial
    case parallel
}

public typealias ExecutionContext = DefaultExecutionContext

public let immediate:ExecutionContextProtocol = ImmediateExecutionContext()
public let main:ExecutionContextProtocol = ExecutionContext.main
public let global:ExecutionContextProtocol = ExecutionContext.global

public func executionContext(executor:@escaping Executor) -> ExecutionContextProtocol {
    return CustomExecutionContext(executor: executor)
}

//Never use it directly
public var _currentContext = try! ThreadLocal<ExecutionContextProtocol>()

public extension ExecutionContextProtocol {
    public static var current:ExecutionContextProtocol {
        get {
            if Thread.isMain {
                return ExecutionContext.main
            }
            if nil == _currentContext.value {
                //TODO: think
//                currentContext.value = RunLoopExecutionContext(inner: <#T##ExecutionContextType#>)
            }
            return _currentContext.value!
        }
    }
}

public extension ExecutionContextProtocol {
    //if context is current - executes immediately. Schedules to the context otherwise
    public func immediateIfCurrent(task:@escaping SafeTask) {
        //can avoid first check but is here for optimization
        if immediate.isEqual(to: self) || isCurrent {
            task()
        } else {
            execute(task: task)
        }
    }
}
