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
    import Result
    
    public class DispatchExecutionContext : ExecutionContextBase, ExecutionContextType, DefaultExecutionContextType {
        private let queue:dispatch_queue_t
        
        public required init(kind:ExecutionContextKind) {
            let id = NSUUID().UUIDString
            switch kind {
            case .Serial: queue = dispatch_queue_create(id, DISPATCH_QUEUE_SERIAL)
            case .Parallel: queue = dispatch_queue_create(id, DISPATCH_QUEUE_CONCURRENT)
            }
        }
        
        public init(queue:dispatch_queue_t) {
            self.queue = queue
        }
        
        public func async(task:SafeTask) {
            dispatch_async(queue) {
                task()
            }
        }
        
        public func async(after:Double, task:SafeTask) {
            if after > 0 {
                let time = dispatch_time(DISPATCH_TIME_NOW, Int64(after * NSTimeInterval(NSEC_PER_SEC)))
                dispatch_after(time, queue) {
                    task()
                }
            } else {
                async(task)
            }
        }
        
        public func sync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType {
            if dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == dispatch_queue_get_label(queue) {
                return try task()
            } else {
                var result:Result<ReturnType, AnyError>?
                
                dispatch_sync(queue) {
                    result = materialize(task)
                }
                
                return try result!.dematerializeAnyError()
            }
        }
        
        public static let main:ExecutionContextType = DispatchExecutionContext(queue: dispatch_get_main_queue())
        public static let global:ExecutionContextType = DispatchExecutionContext(queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
    }

#endif