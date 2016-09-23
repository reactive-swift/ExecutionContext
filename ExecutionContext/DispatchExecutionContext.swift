//===--- DispatchExecutionContext.swift ------------------------------------------------------===//
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

#if !os(Linux) || dispatch
    
    import Foundation
    import Dispatch
    import Boilerplate
    import RunLoop
    
    private extension ExecutionContextKind {
        func createDispatchQueue(id:String) -> DispatchQueue {
            switch self {
            case .serial:
                return DispatchQueue(label: id)
            case .parallel:
                return DispatchQueue(label: id, attributes: .concurrent)
            }
        }
    }
    
    public class DispatchExecutionContext : ExecutionContextBase, ExecutionContextProtocol, DefaultExecutionContextProtocol {
        private let loop:DispatchRunLoop
        
        public required convenience init(kind:ExecutionContextKind) {
            let id = NSUUID().uuidString
            let queue = kind.createDispatchQueue(id: id)
            self.init(queue: queue)
        }
        
        public init(queue:DispatchQueue) {
            self.loop = DispatchRunLoop(queue: queue)
            super.init()
            loop.execute {
                currentContext.value = self
            }
        }
        
        public func async(task:SafeTask) {
            loop.execute {
                currentContext.value = self
                task()
            }
        }
        
        public func async(after:Timeout, task:SafeTask) {
            loop.execute(delay: after) {
                currentContext.value = self
                task()
            }
        }
        
        public func sync<ReturnType>(task:TaskWithResult<ReturnType>) rethrows -> ReturnType {
            if isCurrent {
                return try task()
            }
            
            return try loop.sync {
                currentContext.value = self
                return try task()
            }
        }
        
        public static let main:ExecutionContextProtocol = DispatchExecutionContext(queue: .main)
        public static let global:ExecutionContextProtocol = DispatchExecutionContext(queue: .global())
        
        public static func mainProc() -> Never  {
            if !Thread.isMain {
                print("Main proc was called on non-main thread. Exiting")
                exit(1)
            }
            dispatchMain()
        }
        
        public func isEqual(to other: NonStrictEquatable) -> Bool {
            guard let other = other as? DispatchExecutionContext else {
                return false
            }
            return loop.isEqual(to: other.loop)
        }
    }

#endif
