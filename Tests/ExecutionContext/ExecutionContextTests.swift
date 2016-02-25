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

#if os(Linux)
    import Glibc
#endif

class ExecutionContextTests: XCTestCase {
    //Tests does not create static variables. We need initialized main thread
    //let mainContext = DefaultExecutionContext.main
    
    func syncTest(context:ExecutionContextType) {
        let expectation = self.expectationWithDescription("OK SYNC")
        
        context.sync {
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(0, handler: nil)
    }
    
    func asyncTest(context:ExecutionContextType) {
        let expectation = self.expectationWithDescription("OK ASYNC")
        
        context.async {
            sleep(1.0)
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func afterTest(context:ExecutionContextType) {
        let expectation = self.expectationWithDescription("OK AFTER")
        
        context.async(0.5) {
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(3, handler: nil)
    }
    
    func afterTestAdvanced(context:ExecutionContextType) {
        var ok = true
        
        context.async(3) {
            ok = false
        }
        
        sleep(2.0)
        
        XCTAssert(ok)
        
        sleep(2.0)
        
        XCTAssertFalse(ok)
    }
    
    func testSerial() {
        let context:ExecutionContextType = DefaultExecutionContext(kind: .Serial)
        
        syncTest(context)
        asyncTest(context)
        afterTest(context)
        afterTestAdvanced(context)
    }
    
    func testParallel() {
        let context:ExecutionContextType = DefaultExecutionContext(kind: .Parallel)
        
        syncTest(context)
        asyncTest(context)
        afterTest(context)
        afterTestAdvanced(context)
    }
    
    func testGlobal() {
        let context:ExecutionContextType = DefaultExecutionContext.global
        
        syncTest(context)
        asyncTest(context)
        afterTest(context)
        afterTestAdvanced(context)
    }
    
    func testMain() {
        let context:ExecutionContextType = DefaultExecutionContext.main
        
        syncTest(context)
        asyncTest(context)
        afterTest(context)
        //afterTestAdvanced - no it will not work here
    }
    
    func testCustomOnGlobal() {
        let context = executionContext(global.execute)
        
        syncTest(context)
        asyncTest(context)
        afterTest(context)
        afterTestAdvanced(context)
    }
    
    func testCustomOnMain() {
        let context = executionContext(global.execute)
        
        syncTest(context)
        asyncTest(context)
        afterTest(context)
        //afterTestAdvanced - no it will not work here
    }
    
    func testCustomSimple() {
        let context = executionContext { task in
            task()
        }
        
        syncTest(context)
        asyncTest(context)
        afterTest(context)
        //afterTestAdvanced - no it will not work here
    }
    
    func testSemaphore() {
        let sema = Semaphore(value: 1)
        var n = 0
        for _ in [0...100] {
            global.execute {
                sema.willUse()
                defer {
                    sema.didUse()
                }
                sema.wait()
                XCTAssert(n == 0, "Should always be zero")
                n += 1
                sleep(0.1)
                n -= 1
                sema.signal()
            }
        }
    }
}

#if os(Linux)
extension ExecutionContextTests : XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testSerial", testSerial),
            ("testParallel", testParallel),
            ("testGlobal", testGlobal),
            ("testMain", testMain),
            ("testCustomOnGlobal", testCustomOnGlobal),
            ("testCustomOnMain", testCustomOnMain),
            ("testCustomSimple", testCustomSimple)
        ]
    }
}
#endif