//===--- RunLoop.swift ------------------------------------------------------===//
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
import CoreFoundation

//#if os(Linux)

	private extension NSString {
        var cfString: CFString { return unsafeBitCast(self, CFString.self) }
    }

	private class RunLoopCallbackInfo {
		private var task: SafeTask
		private var runLoops: [RunLoop] = []

		init(_ task: SafeTask) {
			self.task = task
		}

		func run() {
			task()
		}
	}

	private func runLoopCallbackInfoRun(i: UnsafeMutablePointer<Void>) {
        let info = Unmanaged<RunLoopCallbackInfo>.fromOpaque(COpaquePointer(i)).takeRetainedValue()
        info.run()
    }

	private protocol RunLoopCallback {
		var info : RunLoopCallbackInfo { get }
		var cfObject: AnyObject { get }
	}

	class RunLoopSource : RunLoopCallback {
		private let info : RunLoopCallbackInfo
		private let priority : Int
        private var _source: CFRunLoopSource! = nil

		private var cfObject : AnyObject {
            get {
                if _source == nil {
                    var context = CFRunLoopSourceContext(
                        version: 0,
                        info: UnsafeMutablePointer<Void>(Unmanaged.passRetained(info).toOpaque()),
                        retain: nil,
                        release: nil,
                        copyDescription: nil,
                        equal: nil,
                        hash: nil,
                        schedule: nil,
                        cancel: nil,
                        perform: runLoopCallbackInfoRun
                    )
                    _source = CFRunLoopSourceCreate(nil, priority, &context)
                }
                return _source
            }
		}

		init(_ task: SafeTask, priority: Int = 0) {
			self.info = RunLoopCallbackInfo(task)
			self.priority = priority
		}
	}

	private func timerRunCallback(timer: CFRunLoopTimer!, i: UnsafeMutablePointer<Void>) {
        runLoopCallbackInfoRun(i)
    }

	class RunLoopDelay : RunLoopCallback {
		private let info : RunLoopCallbackInfo
		private let delay: Double
        private var _timer: CFRunLoopTimer! = nil

		private var cfObject : AnyObject {
            get {
                if _timer == nil {
                    var context = CFRunLoopTimerContext(
                        version: 0,
                        info: UnsafeMutablePointer<Void>(Unmanaged.passRetained(info).toOpaque()),
                        retain: nil,
                        release: nil,
                        copyDescription: nil
                    )
                    _timer = CFRunLoopTimerCreate(nil, CFAbsoluteTimeGetCurrent()+delay, -1, 0, 0, timerRunCallback, &context)
                }
                return _timer
            }
		}
		
		init(_ task: SafeTask, delay: Double) {
            self.delay = delay
            self.info = RunLoopCallbackInfo(task)
        }
	}

	class RunLoop {
		private let cfRunLoop: CFRunLoop!
		private let autoStop: Bool

		#if !os(Linux)
    		static let defaultMode:NSString = "kCFRunLoopDefaultMode" as NSString
		#else
    		static let defaultMode:NSString = "kCFRunLoopDefaultMode".bridge()
		#endif

        init(_ cfRunLoop: CFRunLoop, autoStop: Bool = true) {
            self.cfRunLoop = cfRunLoop
            self.autoStop = autoStop
        }
        
		convenience init(_ runLoop: AnyObject, autoStop: Bool = true) {
            self.init(unsafeBitCast(runLoop, CFRunLoop.self), autoStop: autoStop)
		}

		deinit {
			if autoStop && cfRunLoop != nil {
				CFRunLoopStop(cfRunLoop)
			}
		}

		static func currentRunLoop(autoStop: Bool = false) -> RunLoop {
			return RunLoop(CFRunLoopGetCurrent(), autoStop: autoStop)
		}

		static func mainRunLoop() -> RunLoop {
			return RunLoop(CFRunLoopGetMain(), autoStop: false)
		}
        
        static func currentCFRunLoop() -> AnyObject {
            return CFRunLoopGetCurrent()
        }

		func isCurrent() -> Bool {
			return cfRunLoop === CFRunLoopGetCurrent()
		}

		static func run() {
			runInMode(RunLoop.defaultMode)
		}

		static func runInMode(mode: NSString) {
			#if !os(Linux)
				while CFRunLoopRunInMode(mode.cfString, Double.infinity, false) != .Stopped {}
			#else
				while CFRunLoopRunInMode(mode.cfString, Double.infinity, false) != Int32(kCFRunLoopRunStopped) {}
			#endif
		}

		@noreturn static func runForever() {
			while true { run() }
		}

		func addSource(rls: RunLoopSource, mode: NSString) {
            let crls = unsafeBitCast(rls.cfObject, CFRunLoopSource.self)
            if CFRunLoopSourceIsValid(crls) {
                CFRunLoopAddSource(cfRunLoop, crls, mode.cfString)
                rls.info.runLoops.append(self)
                CFRunLoopSourceSignal(crls)
                CFRunLoopWakeUp(cfRunLoop)
            }
		}

		func addDelay(rld: RunLoopDelay, mode: NSString) {
            let crld = unsafeBitCast(rld.cfObject, CFRunLoopTimer.self)
            if CFRunLoopTimerIsValid(crld) {
                CFRunLoopAddTimer(cfRunLoop, crld, mode.cfString)
                rld.info.runLoops.append(self)
                CFRunLoopWakeUp(cfRunLoop)
            }
		}
	}
//#endif