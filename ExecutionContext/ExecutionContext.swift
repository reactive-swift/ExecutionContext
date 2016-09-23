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

#if !os(Linux) || dispatch
    import Dispatch
#endif

// return true if error successfully handled, false otherwise
public typealias ErrorHandler = (e:ErrorProtocol) throws -> Bool

private func stockErrorHandler(e:ErrorProtocol) throws -> Bool {
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
    
    func async(after:Timeout, task:Task)
    func async(after:Timeout, task:SafeTask)
    
    func sync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType
}

public protocol ExecutionContextType : TaskSchedulerType, ErrorHandlerRegistryType, NonStrictEquatable {
    func execute(task:SafeTask)
    
    var kind:ExecutionContextKind {get}
    
    //in case of parallel contexts should return serial context bound to this parallel context. Returns self if already serial
    var serial:ExecutionContextType {get}
    
    //in case of serial that is bound to a parallel context should return a parrallel context it is bound to. Returns "global" if it's not bound to any parallel context
    var parallel:ExecutionContextType {get}
    
    static var current:ExecutionContextType {get}
}

//DUMMY IMPLEMENTATION TO MAINTAIN BUILDABLE CODE. SUBJECT TO BE REMOVED ASAP
public extension ExecutionContextType {
    public var kind:ExecutionContextKind {
        get {
            return .serial
        }
    }
    
    var serial:ExecutionContextType {
        get {
            return self
        }
    }
    
    var parallel:ExecutionContextType {
        get {
            return global
        }
    }
}

public extension ExecutionContextType {
    public func execute(task:SafeTask) {
        async(task)
    }
    
    public var isCurrent:Bool {
        get {
            return Self.current.isEqualTo(self)
        }
    }
}

import RunLoop

extension ExecutionContextType {
    func syncThroughAsync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
        if isCurrent {
            return try task()
        }
        
        return try {
            var result:Result<ReturnType, AnyError>?
            
            let sema = RunLoop.current.semaphore()
            
            async {
                result = materializeAny(task)
                sema.signal()
            }
            
            sema.wait()
            
            return try result!.dematerializeAny()
        }()
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
        errorHandlers.insert(handler, at: errorHandlers.endIndex.advanced(by: -1))
    }
}

public extension ErrorHandlerRegistryType where Self : TaskSchedulerType {
    func handleError(e:ErrorProtocol) {
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
    public func async(after:Timeout, task:Task) {
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

public enum ExecutionContextKind {
    case serial
    case parallel
}

public typealias ExecutionContext = DefaultExecutionContext

public let immediate:ExecutionContextType = ImmediateExecutionContext()
public let main:ExecutionContextType = ExecutionContext.main
public let global:ExecutionContextType = ExecutionContext.global

public func executionContext(executor:Executor) -> ExecutionContextType {
    return CustomExecutionContext(executor: executor)
}

var currentContext = try! ThreadLocal<ExecutionContextType>()

public extension ExecutionContextType {
    public static var current:ExecutionContextType {
        get {
            if Thread.isMain {
                return ExecutionContext.main
            }
            if currentContext.value == nil {
                //TODO: think
//                currentContext.value = RunLoopExecutionContext(inner: <#T##ExecutionContextType#>)
            }
            return currentContext.value!
        }
    }
}

public extension ExecutionContextType {
    //if context is current - executes immediately. Schedules to the context otherwise
    public func immediateIfCurrent(task:SafeTask) {
        //can avoid first check but is here for optimization
        if immediate.isEqualTo(self) || isCurrent {
            task()
        } else {
            execute(task)
        }
    }
}