//===--- ExecutionContextTests.swift ------------------------------------------------------===//
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

import XCTest
@testable import ExecutionContext

class ExecutionContextTests: XCTestCase {
    
    func syncTest(context:ExecutionContextType) {
        let expectation = self.expectationWithDescription("OK SYNC")
        
        context.sync {
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(1, handler: nil)
    }
    
    func asyncTest(context:ExecutionContextType) {
        let expectation = self.expectationWithDescription("OK ASYNC")
        
        context.async {
            sleep(1)
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func testSerial() {
        let context:ExecutionContextType = DefaultExecutionContext(kind: .Serial)
        
        syncTest(context)
        asyncTest(context)
    }
    
    func testParallel() {
        let context:ExecutionContextType = DefaultExecutionContext(kind: .Parallel)
        
        syncTest(context)
        asyncTest(context)
    }
    
    func testGlobal() {
        let context:ExecutionContextType = DefaultExecutionContext.global
        
        syncTest(context)
        asyncTest(context)
    }
    
    func testMain() {
        let context:ExecutionContextType = DefaultExecutionContext.main
        
        syncTest(context)
        asyncTest(context)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock {
            // Put the code you want to measure the time of here.
        }
    }
    
}
