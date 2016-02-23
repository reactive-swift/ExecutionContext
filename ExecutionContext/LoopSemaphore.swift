//===--- Semaphore.swift ------------------------------------------------------===//
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

import Dispatch

public class LoopSemaphore : SemaphoreType {
    let sema:dispatch_semaphore_t
    
    public required convenience init() {
        self.init(value: 0)
    }
    
    public required init(value: Int) {
        self.sema = dispatch_semaphore_create(value)
    }
    
    public func wait() -> Bool {
        return dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER) == 0
    }
    
    public func wait(until:NSDate?) -> Bool {
        let timeout = until?.timeIntervalSinceNow
        return wait(timeout)
    }
    
    public func wait(timeout: Double?) -> Bool {
        guard let timeout = timeout else {
            return wait()
        }
        let time = dispatch_time(DISPATCH_TIME_NOW, Int64(timeout * NSTimeInterval(NSEC_PER_SEC)))
        let result = dispatch_semaphore_wait(sema, time)
        return result == 0
    }
    
    public func signal() -> Int {
        return dispatch_semaphore_signal(sema)
    }
}