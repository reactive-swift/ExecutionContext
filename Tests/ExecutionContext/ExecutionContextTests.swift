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

#if !os(tvOS)
    import XCTest3
#endif

#if os(Linux)
    import Glibc
#endif

import Boilerplate
import RunLoop

#if !os(tvOS)
class ExecutionContextTests: XCTestCase {
    //Tests does not create static variables. We need initialized main thread
    //let mainContext = DefaultExecutionContext.main
    
    func syncTest(context:ExecutionContextType) {
        
        let expectation = self.expectation(withDescription: "OK SYNC")
        
        context.sync {
            expectation.fulfill()
        }
        
        self.waitForExpectations(withTimeout: 0, handler: nil)
    }
    
    func asyncTest(context:ExecutionContextType, runRunLoop: Bool = false) {
        let expectation = self.expectation(withDescription: "OK ASYNC")
        
        context.async {
            if runRunLoop {
                (RunLoop.current as! RunnableRunLoopType).run(.In(timeout: 1))
            } else {
                Thread.sleep(1)
            }
            expectation.fulfill()
        }
        
        if runRunLoop {
            (RunLoop.current as! RunnableRunLoopType).run(.In(timeout: 2))
        }
        
        self.waitForExpectations(withTimeout: 2, handler: nil)
    }
    
    func afterTest(context:ExecutionContextType, runRunLoop: Bool = false) {
        let expectation = self.expectation(withDescription: "OK AFTER")
        
        context.async(0.5) {
            expectation.fulfill()
        }
        
        if runRunLoop {
            (RunLoop.current as! RunnableRunLoopType).run(.In(timeout: 3))
        }
        
        self.waitForExpectations(withTimeout: 3, handler: nil)
    }
    
    func afterTestAdvanced(context:ExecutionContextType, runRunLoop: Bool = false) {
        var ok = true
        
        context.async(3) {
            ok = false
        }
        
        if runRunLoop {
            (RunLoop.current as! RunnableRunLoopType).run(.In(timeout: 2))
        } else {
            Thread.sleep(2.0)
        }
        
        XCTAssert(ok)
        
        if runRunLoop {
            (RunLoop.current as! RunnableRunLoopType).run(.In(timeout: 2))
        } else {
            Thread.sleep(2.0)
        }
        
        XCTAssertFalse(ok)
    }
    
    func testSerial() {
        let context:ExecutionContextType = DefaultExecutionContext(kind: .serial)
        
        syncTest(context)
        asyncTest(context)
        afterTest(context)
        afterTestAdvanced(context)
    }
    
    func testParallel() {
        let context:ExecutionContextType = DefaultExecutionContext(kind: .parallel)
        
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
        #if os(Linux)
            let runRunLoop = true
        #else
            let runRunLoop = false
        #endif
        
        #if !os(Linux)
            syncTest(context)
        #endif
        asyncTest(context, runRunLoop: runRunLoop)
        afterTest(context, runRunLoop: runRunLoop)
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
        let context = executionContext(main.execute)
        #if os(Linux)
            let runRunLoop = true
        #else
            let runRunLoop = false
        #endif
        
//        syncTest(context)
        asyncTest(context, runRunLoop: runRunLoop)
        afterTest(context, runRunLoop: runRunLoop)
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
}
#endif

#if os(Linux)
extension ExecutionContextTests {
	static var allTests : [(String, ExecutionContextTests -> () throws -> Void)] {
		return [
			("testSerial", testSerial),
			("testParallel", testParallel),
			("testGlobal", testGlobal),
			("testMain", testMain),
			("testCustomOnGlobal", testCustomOnGlobal),
			("testCustomOnMain", testCustomOnMain),
			("testCustomSimple", testCustomSimple),
		]
	}
}
#endif
