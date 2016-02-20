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
    
    func afterTest(context:ExecutionContextType) {
        let expectation = self.expectationWithDescription("OK AFTER")
        
        context.async(0.5) {
            sleep(1)
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(3, handler: nil)
    }
    
    func afterTestAdvanced(context:ExecutionContextType) {
        var ok = true
        
        context.async(3) {
            ok = false
        }
        
        sleep(2)
        
        XCTAssert(ok)
        
        sleep(2)
        
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
}

#if os(Linux)
extension ExecutionContextTests : XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testSerial", testSerial),
            ("testParallel", testParallel),
            ("testGlobal", testGlobal),
            ("testMain", testMain)
        ]
    }
}
#endif