//
//  PHFileCache.swift
//  PHImageKit
//
// Copyright (c) 2016 Product Hunt (http://producthunt.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import UIKit

class PHFileCache: NSObject, PHCacheProtocol {

    private let ioQueue = DispatchQueue(label: imageKitDomain  + ".ioQueue", attributes: DispatchQueueAttributes.serial)
    private let _fileManager = FileManager()
    private var directory : String!
    private var maxDiskCacheSize : UInt = 0

    override init() {
        super.init()

        directory = (NSSearchPathForDirectoriesInDomains(.cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true).first! as NSString).appendingPathComponent(imageKitDomain)

        createDirectoryIfNeeded()

        setCacheSize(200)
    }

    func saveImageObject(_ object: PHImageObject, key: String, completion: PHVoidCompletion? = nil) {
        ioDispatch {
            if let data = object.data {
                self._fileManager.createFile(atPath: self.pathFromKey(key), contents: data as Data, attributes: nil)
            }

            if let completion = completion {
                completion()
            }
        }
    }

    func getImageObject(_ key: String, completion: PHManagerCompletion) {
        ioDispatch {
            let data = try? Data(contentsOf: URL(fileURLWithPath: self.pathFromKey(key)))
            completion(object: PHImageObject(data: data))
        }
    }

    func isCached(_ key: String) -> Bool {
        return _fileManager.fileExists(atPath: pathFromKey(key))
    }

    func removeImageObject(_ key: String, completion: PHVoidCompletion?) {
        ioDispatch {
            do {
                try self._fileManager.removeItem(atPath: self.pathFromKey(key))
            } catch _ {}

            self.callCompletion(completion)
        }
    }

    func clear(_ completion: PHVoidCompletion? = nil) {
        ioDispatch { () -> Void in
            do {
                try self._fileManager.removeItem(atPath: self.directory)
            } catch _ {}

            self.createDirectoryIfNeeded()

            self.callCompletion(completion)
        }
    }

    func clearExpiredImages(_ completion: PHVoidCompletion? = nil) {
        ioDispatch {
            let targetSize: UInt = self.maxDiskCacheSize/2
            var totalSize: UInt = 0

            for object in self.getCacheObjects() {
                if object.modificationDate.ik_isExpired() || totalSize > targetSize {
                    do {
                        try self._fileManager.removeItem(at: object.url)
                    } catch _ {}
                } else {
                    totalSize += object.size
                }
            }

            self.callCompletion(completion)
        }
    }

    func setCacheSize(_ size: UInt) {
        maxDiskCacheSize = max(50, min(size, 500)) * 1024 * 1024
    }

    func cacheSize() -> UInt {
        var totalSize: UInt = 0

        getFiles().forEach {
            totalSize += getResourceValue($0, key: URLResourceKey.totalFileAllocatedSizeKey.rawValue, defaultValue: NSNumber()).uintValue
        }

        return totalSize
    }

    private func ioDispatch(_ operation : (() -> Void)) {
        ioQueue.async(execute: operation)
    }

    private func callCompletion(_ completion: PHVoidCompletion? = nil) {
        if let completion = completion {
            completion()
        }
    }

    private func pathFromKey(_ key : String) -> String {
        return (directory as NSString).appendingPathComponent(key)
    }

    private func createDirectoryIfNeeded() {
        ioDispatch {
            if !self._fileManager.fileExists(atPath: self.directory) {
                try! self._fileManager.createDirectory(atPath: self.directory, withIntermediateDirectories: true, attributes: nil)
            }
        }
    }

    private func getFiles() -> [URL] {
        let directoryUrl = URL(fileURLWithPath: self.directory)
        let resourceKeys = [URLResourceKey.isDirectoryKey.rawValue, URLResourceKey.contentModificationDateKey.rawValue, URLResourceKey.totalFileAllocatedSizeKey.rawValue]

        let fileEnumerator = self._fileManager.enumerator(at: directoryUrl, includingPropertiesForKeys: resourceKeys, options: .skipsHiddenFiles, errorHandler: nil)

        if let fileEnumerator = fileEnumerator, urls = fileEnumerator.allObjects as? [URL] {
            return urls
        }

        return []
    }

    private func getCacheObjects() -> [PHFileCacheObject] {
        return getFiles().map { (url) -> PHFileCacheObject in
            let object = PHFileCacheObject()

            object.url = url
            object.modificationDate = getResourceValue(url, key: URLResourceKey.contentModificationDateKey.rawValue, defaultValue: NSDate()) as NSDate as Date
            object.size = self.getResourceValue(url, key: URLResourceKey.totalFileAllocatedSizeKey.rawValue, defaultValue: NSNumber()).uintValue

            return object
            }.sorted(isOrderedBefore: {
                $0.modificationDate.compare($1.modificationDate) == .orderedAscending
            })
    }

    private func getResourceValue<T:AnyObject>(_ url: URL, key: String, defaultValue: T) -> T {
        var value: AnyObject?
        try! (url as NSURL).getResourceValue(&value, forKey: URLResourceKey(rawValue: key))

        if let value = value as? T {
            return value
        }
        
        return defaultValue
    }
    
}

class PHFileCacheObject {
    
    var url : URL!
    var size : UInt = 0
    var modificationDate = Date()
    
}
