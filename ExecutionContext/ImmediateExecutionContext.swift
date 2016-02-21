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

public class ImmediateExecutionContext : ExecutionContextBase, ExecutionContextType {
    public func async(task:SafeTask) {
        task()
    }
    
    public func async(after:Double, task:SafeTask) {
        let sec = time_t(after)
        let nsec = Int((after - Double(sec)) * 1000 * 1000 * 1000)//nano seconds
        var time = timespec(tv_sec:sec, tv_nsec: nsec)
        
        nanosleep(&time, nil)
        async(task)
    }
    
    public func sync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType {
        return try task()
    }
}