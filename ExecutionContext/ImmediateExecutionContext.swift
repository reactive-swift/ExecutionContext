//===--- ImmediateExecutionContext.swift ------------------------------------------------------===//
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

class ImmediateExecutionContext : ExecutionContextBase, ExecutionContextProtocol {
    func async(task:@escaping SafeTask) {
        let context = currentContext.value
        defer {
            currentContext.value = context
        }
        currentContext.value = self
        
        task()
    }
    
    func async(after:Timeout, task:@escaping SafeTask) {
        async {
            Thread.sleep(timeout: after)
            task()
        }
    }
    
    func sync<ReturnType>(task:@escaping TaskWithResult<ReturnType>) rethrows -> ReturnType {
        let context = currentContext.value
        defer {
            currentContext.value = context
        }
        currentContext.value = self
        
        return try task()
    }
    
    func isEqual(to other:NonStrictEquatable) -> Bool {
        return other is ImmediateExecutionContext
    }
}
