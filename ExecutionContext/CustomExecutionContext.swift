//===--- CustomExecutionContext.swift ------------------------------------------------------===//
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
import Foundation3
import Boilerplate

public class CustomExecutionContext : ExecutionContextBase, ExecutionContextType {
    let id = NSUUID()
    let executor:Executor
    
    public init(executor:Executor) {
        self.executor = executor
    }
    
    public func async(task:SafeTask) {
        executor {
            let context = currentContext.value
            defer {
                currentContext.value = context
            }
            currentContext.value = self
            
            task()
        }
    }
    
    public func async(after:Timeout, task:SafeTask) {
        async {
            Thread.sleep(after)
            task()
        }
    }
    
    public func sync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
        return try syncThroughAsync(task)
    }
    
    public func isEqualTo(other: NonStrictEquatable) -> Bool {
        guard let other = other as? CustomExecutionContext else {
            return false
        }
        return id.isEqual(other.id)
    }
}