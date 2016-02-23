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

    private class TaskQueueElement {
        private let task : SafeTask
        private let source: RunLoopSource
        var next: TaskQueueElement? = nil
        
        init(_ task: SafeTask, runLoopSource: RunLoopSource) {
            self.task = task
            self.source = runLoopSource
        }
        
        func run() {
            task()
        }
    }

    private class TaskQueue {
        private let lock = NSLock()
        private var head:TaskQueueElement? = nil
        private var tail:TaskQueueElement? = nil
        
        func enqueue(elem: TaskQueueElement) {
            defer {
                lock.unlock()
            }
            lock.lock()
            if tail == nil {
                head = elem
                tail = elem
            } else {
                tail!.next = elem
                tail = elem
            }
        }
        
        func dequeue() -> TaskQueueElement? {
            defer {
                lock.unlock()
            }
            lock.lock()
            let elem = head
            head = head?.next
            if head == nil {
                tail = nil
            }
            return elem
        }
    }

    internal protocol WakeableRunLoop : AnyObject {
        func wakeUp()
    }

	private class RunLoopCallbackInfo {
		private var task: SafeTask
		private var runLoops: [WakeableRunLoop] = []

		init(_ task: SafeTask) {
			self.task = task
		}

		func run() {
			task()
		}
	}

	private func runLoopCallbackInfoRun(i: UnsafeMutablePointer<Void>) {
        let info = Unmanaged<RunLoopCallbackInfo>.fromOpaque(COpaquePointer(i)).takeUnretainedValue()
        info.run()
    }

    private func runLoopCallbackInfoRetain(i: UnsafePointer<Void>) -> UnsafePointer<Void> {
        Unmanaged<RunLoopCallbackInfo>.fromOpaque(COpaquePointer(i)).retain()
        return i
    }

    private func runLoopCallbackInfoRelease(i: UnsafePointer<Void>) {
        Unmanaged<RunLoopCallbackInfo>.fromOpaque(COpaquePointer(i)).release()
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
                        info: UnsafeMutablePointer<Void>(Unmanaged.passUnretained(info).toOpaque()),
                        retain: runLoopCallbackInfoRetain,
                        release: runLoopCallbackInfoRelease,
                        copyDescription: nil,
                        equal: nil,
                        hash: nil,
                        schedule: nil,
                        cancel: nil,
                        perform: runLoopCallbackInfoRun
                    )
                    _source = CFRunLoopSourceCreate(nil, -priority, &context)
                }
                return _source
            }
		}

		init(_ task: SafeTask, priority: Int = 0) {
			self.info = RunLoopCallbackInfo(task)
			self.priority = priority
		}
        
        deinit {
            if _source != nil && CFRunLoopSourceIsValid(_source) {
                CFRunLoopSourceInvalidate(_source)
                _source = nil
            }
        }
        
        func signal() {
            if _source != nil {
                CFRunLoopSourceSignal(_source)
            }
            for loop in info.runLoops {
                loop.wakeUp()
            }
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
                        info: UnsafeMutablePointer<Void>(Unmanaged.passUnretained(info).toOpaque()),
                        retain: runLoopCallbackInfoRetain,
                        release: runLoopCallbackInfoRelease,
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

    private class CFRunLoopWakeupHolder: WakeableRunLoop {
        private let loop:CFRunLoop!
        
        init(loop: CFRunLoop!) {
            self.loop = loop
        }
        
        func wakeUp() {
            CFRunLoopWakeUp(loop)
        }
    }

    class RunLoop : WakeableRunLoop {
		private let cfRunLoop: CFRunLoop!
        
        private var taskQueueSource: RunLoopSource
        private var taskQueue: TaskQueue

		#if !os(Linux)
    		static let defaultMode:NSString = "kCFRunLoopDefaultMode" as NSString
		#else
    		static let defaultMode:NSString = "kCFRunLoopDefaultMode".bridge()
		#endif
        
        private static let threadKey = PThreadKey()
        
        private static let MainRunLoop = RunLoop.createMainRunLoop()

        init(_ cfRunLoop: CFRunLoop) {
            self.cfRunLoop = cfRunLoop
            
            let queue = TaskQueue()
            
            taskQueueSource = RunLoopSource({
                var element = queue.dequeue()
                let source = element?.source
                
                while element != nil {
                    element!.run()
                    element = queue.dequeue()
                }
                
                source?.signal()                
//                if let element = queue.dequeue() {
//                    element.run()
//                    element.source.signal()
//                }
            })
            taskQueue = queue
            addSource(taskQueueSource, mode: RunLoop.defaultMode, retainLoop: false)
        }
        
        deinit {
            addTask {
                PThread.setSpecific(nil, key: RunLoop.threadKey)
            }
        }
		convenience init(_ runLoop: AnyObject) {
            self.init(unsafeBitCast(runLoop, CFRunLoop.self))
		}
        
        private static func createMainRunLoop() -> RunLoop {
            let runLoop = RunLoop(CFRunLoopGetMain())
            if runLoop.isCurrent() {
                PThread.setSpecific(runLoop, key: RunLoop.threadKey)
            } else {
                let sema = Semaphore()
                runLoop.addTask({
                    PThread.setSpecific(runLoop, key: RunLoop.threadKey)
                    sema.signal()
                })
                sema.wait()
            }
            return runLoop
        }

		static func currentRunLoop() -> RunLoop {
            guard let loop = PThread.getSpecific(RunLoop.threadKey) else {
                let loop = RunLoop(CFRunLoopGetCurrent())
                PThread.setSpecific(loop, key: RunLoop.threadKey)
                return loop
            }
			return unsafeBitCast(loop, RunLoop.self)
		}

		static func mainRunLoop() -> RunLoop {
			return MainRunLoop
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
        
        static func runUntil(mode: NSString, until:NSDate) {
            RunLoop.runWithTimeout(mode, timeout: until.timeIntervalSinceNow)
        }
        
        static func runUntilOnce(mode: NSString, until:NSDate) {
            RunLoop.runWithOptions(mode, timeout: until.timeIntervalSinceNow, once: true)
        }
        
        static func runWithOptions(mode: NSString, timeout:NSTimeInterval, once:Bool) {
            #if !os(Linux)
                //var result:CFRunLoopRunResult
                //result =
                CFRunLoopRunInMode(mode.cfString, timeout, once)
            #else
                //var result:Int32
                //result =
                CFRunLoopRunInMode(mode.cfString, timeout, once)
                //Int32(kCFRunLoopRunStopped)
            #endif
        }
        
        static func runWithTimeout(mode: NSString, timeout:NSTimeInterval) {
            RunLoop.runWithOptions(mode, timeout: timeout, once: false)
        }

		static func runInMode(mode: NSString) {
            RunLoop.runWithTimeout(mode, timeout: Double.infinity)
		}

		@noreturn static func runForever() {
			while true { run() }
		}

        func addSource(rls: RunLoopSource, mode: NSString, retainLoop: Bool = true) {
            let crls = unsafeBitCast(rls.cfObject, CFRunLoopSource.self)
            if CFRunLoopSourceIsValid(crls) {
                CFRunLoopAddSource(cfRunLoop, crls, mode.cfString)
                if retainLoop {
                    rls.info.runLoops.append(self)
                } else {
                    rls.info.runLoops.append(CFRunLoopWakeupHolder(loop: cfRunLoop))
                }
                wakeUp()
            }
		}

		func addDelay(rld: RunLoopDelay, mode: NSString) {
            let crld = unsafeBitCast(rld.cfObject, CFRunLoopTimer.self)
            if CFRunLoopTimerIsValid(crld) && (rld.info.runLoops.count == 0 || rld.info.runLoops[0] === self) {
                CFRunLoopAddTimer(cfRunLoop, crld, mode.cfString)
                rld.info.runLoops.append(self)
                wakeUp()
            }
		}
        
        func addTask(task: SafeTask) {
            taskQueue.enqueue(TaskQueueElement(task, runLoopSource: taskQueueSource))
            taskQueueSource.signal()
            wakeUp()
        }
        
        func wakeUp() {
            CFRunLoopWakeUp(cfRunLoop)
        }
	}
//#endif