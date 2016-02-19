//===--- Result+Some.swift ------------------------------------------------------===//
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
import Result

public protocol AnyErrorType : ErrorType {
    var error:ErrorType {
        get
    }
}

struct AnyError : AnyErrorType {
    private let e:ErrorType
    
    init(e:ErrorType) {
        self.e = e
    }
    
    var error:ErrorType {
        get {
            guard let anyError = e as? AnyError else {
                return e
            }
            return anyError.error
        }
    }
}

public extension Result where Error : AnyErrorType {
    public func dematerializeAnyError() throws -> T {
        switch self {
        case let .Success(value):
            return value
        case let .Failure(error):
            throw error.error
        }
    }
}

func materialize<T>(f: () throws -> T) -> Result<T, AnyError> {
    do {
        return .Success(try f())
    } catch let error {
        return .Failure(AnyError(e: error))
    }
}