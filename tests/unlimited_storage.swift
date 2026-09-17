import Foundation

// Bento's StorageCardContent does not invoke the GM2 mapper/cell. These callers
// exercise Swift -> imported Objective-C model getter dispatch directly.
@_cdecl("GSReadStorageFromSwift")
func readStorageFromSwift(_ object: UnsafeRawPointer) -> Int {
    Unmanaged<GSStorageFixtureData>.fromOpaque(object).takeUnretainedValue().storageState
}

@_cdecl("GSReadUnlimitedTitleFromSwift")
func readUnlimitedTitleFromSwift(_ object: UnsafeRawPointer) -> Bool {
    Unmanaged<GSStorageFixtureData>.fromOpaque(object).takeUnretainedValue().title == "Unlimited storage"
}
