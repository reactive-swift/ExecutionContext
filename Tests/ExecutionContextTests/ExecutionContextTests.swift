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

import Boilerplate
import RunLoop

class ExecutionContextTests: XCTestCase {
    //Tests does not create static variables. We need initialized main thread
    //let mainContext = DefaultExecutionContext.main
    
    func syncTest(context:ExecutionContextProtocol) {
        
        let expectation = self.expectation(description: "OK SYNC")
        
        context.sync {
            expectation.fulfill()
        }
        
        self.waitForExpectations(timeout: 0, handler: nil)
    }
    
    func asyncTest(context:ExecutionContextProtocol, runRunLoop: Bool = false) {
        let expectation = self.expectation(description: "OK ASYNC")
        
        context.async {
            if runRunLoop {
                let _ = (RunLoop.reactive.current! as! RunnableRunLoopProtocol).run(timeout: .In(timeout: 1))
            } else {
                Thread.sleep(timeout: 1)
            }
            expectation.fulfill()
        }
        
        if runRunLoop {
            let _ = (RunLoop.reactive.current! as! RunnableRunLoopProtocol).run(timeout: .In(timeout: 2))
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func afterTest(context:ExecutionContextProtocol, runRunLoop: Bool = false) {
        let expectation = self.expectation(description: "OK AFTER")
        
        context.async(after: 0.5) {
            expectation.fulfill()
        }
        
        if runRunLoop {
            let _ = (RunLoop.reactive.current! as! RunnableRunLoopProtocol).run(timeout: .In(timeout: 3))
        }
        
        self.waitForExpectations(timeout: 3, handler: nil)
    }
    
    func afterTestAdvanced(context:ExecutionContextProtocol, runRunLoop: Bool = false) {
        var ok = true
        
        context.async(after: 3) {
            ok = false
        }
        
        if runRunLoop {
            let _ = (RunLoop.reactive.current! as! RunnableRunLoopProtocol).run(timeout: .In(timeout: 2))
        } else {
            Thread.sleep(timeout: 2.0)
        }
        
        XCTAssert(ok)
        
        if runRunLoop {
            let _ = (RunLoop.reactive.current! as! RunnableRunLoopProtocol).run(timeout: .In(timeout: 2))
        } else {
            Thread.sleep(timeout: 2.0)
        }
        
        XCTAssertFalse(ok)
    }
    
    func testSerial() {
        let context:ExecutionContextProtocol = DefaultExecutionContext(kind: .serial)
        
        syncTest(context: context)
        asyncTest(context: context)
        afterTest(context: context)
        afterTestAdvanced(context: context)
    }
    
    func testParallel() {
        let context:ExecutionContextProtocol = DefaultExecutionContext(kind: .parallel)
        
        syncTest(context: context)
        asyncTest(context: context)
        afterTest(context: context)
        afterTestAdvanced(context: context)
    }
    
    func testGlobal() {
        let context:ExecutionContextProtocol = DefaultExecutionContext.global
        
        syncTest(context: context)
        asyncTest(context: context)
        afterTest(context: context)
        afterTestAdvanced(context: context)
    }
    
    func testMain() {
        let context:ExecutionContextProtocol = DefaultExecutionContext.main
        //#if os(Linux)
        //    let runRunLoop = true
        //#else
            let runRunLoop = false
        //#endif
        
        //#if !os(Linux)
            syncTest(context: context)
        //#endif
        asyncTest(context: context, runRunLoop: runRunLoop)
        afterTest(context: context, runRunLoop: runRunLoop)
        //afterTestAdvanced - no it will not work here
    }
    
    func testCustomOnGlobal() {
        let context = executionContext(executor: global.execute)
        
        syncTest(context: context)
        asyncTest(context: context)
        afterTest(context: context)
        afterTestAdvanced(context: context)
    }
    
    func testCustomOnMain() {
        let context = executionContext(executor: main.execute)
        //#if os(Linux)
        //    let runRunLoop = true
        //#else
            let runRunLoop = false
        //#endif
        
//        syncTest(context)
        asyncTest(context: context, runRunLoop: runRunLoop)
        afterTest(context: context, runRunLoop: runRunLoop)
        //afterTestAdvanced - no it will not work here
    }
    
    func testCustomSimple() {
        let context = executionContext { task in
            task()
        }
        
        syncTest(context: context)
        asyncTest(context: context)
        afterTest(context: context)
        //afterTestAdvanced - no it will not work here
    }
}

#if os(Linux)
extension ExecutionContextTests {
	static var allTests : [(String, (ExecutionContextTests) -> () throws -> Void)] {
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
