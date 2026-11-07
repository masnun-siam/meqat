import Foundation

/// The subset of `FileManager` the bundle replacer uses, so tests can fail any step.
public protocol FileMoving {
    func url(
        for directory: FileManager.SearchPathDirectory, in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?, create shouldCreate: Bool
    ) throws -> URL
    func copyItem(at srcURL: URL, to dstURL: URL) throws
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func removeItem(at URL: URL) throws
}

extension FileManager: FileMoving {}
