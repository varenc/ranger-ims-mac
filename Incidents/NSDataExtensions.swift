//
//  NSDataExtensions.swift
//  Incidents
//
//  © 2015 Burning Man and its contributors. All rights reserved.
//  See the file COPYRIGHT.md for terms.
//

import Foundation



extension NSData {

    class func fromBytes(bytes: [UInt8]) -> NSData {
        return self.init(bytes: bytes, length: bytes.count)
    }


    func asBytes() -> [UInt8] {
        let pointer = UnsafePointer<UInt8>(self.bytes)

        // Get our buffer pointer and make an array out of it
        let buffer = UnsafeBufferPointer<UInt8>(
            start:pointer,
            count:self.length
        )

        return [UInt8](buffer)
    }

}
