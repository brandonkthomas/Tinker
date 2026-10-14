//
//  ApplicationsFolderTests.swift
//  TinkerTests
//

import Foundation
import Testing
@testable import Tinker

/// Deciding whether to offer the move to Applications, and doing the copy.
struct ApplicationsFolderTests {
    @Test func recognizesApplicationsFolders() {
        #expect(ApplicationsFolder.contains(URL(fileURLWithPath: "/Applications/Tinker.app")))
        #expect(ApplicationsFolder.contains(URL(fileURLWithPath: "/Users/sam/Applications/Tinker.app")))
        #expect(ApplicationsFolder.contains(URL(fileURLWithPath: "/Applications/Utilities/Tinker.app")))
        #expect(!ApplicationsFolder.contains(URL(fileURLWithPath: "/Users/sam/Downloads/Tinker.app")))
        #expect(!ApplicationsFolder.contains(URL(fileURLWithPath: "/Volumes/Tinker/Tinker.app")))
    }

    @Test func recognizesAnAppRunningFromAHiddenCopy() {
        let hidden = URL(fileURLWithPath: "/private/var/folders/ab/xyz/T/AppTranslocation/1234/d/Tinker.app")
        #expect(ApplicationsFolder.isTranslocated(hidden))
        #expect(!ApplicationsFolder.contains(hidden))
        #expect(!ApplicationsFolder.isTranslocated(URL(fileURLWithPath: "/Users/sam/Downloads/Tinker.app")))
    }

    @Test func installCopiesTheWholeBundle() throws {
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory.appending(path: "TinkerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: scratch) }

        let source = scratch.appending(path: "Downloads/Tinker.app", directoryHint: .isDirectory)
        let executable = source.appending(path: "Contents/MacOS/Tinker")
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: executable)
        let applications = scratch.appending(path: "Applications", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: applications, withIntermediateDirectories: true)

        let installed = try ApplicationsFolder.install(source, into: applications)

        #expect(installed.lastPathComponent == "Tinker.app")
        #expect(ApplicationsFolder.contains(installed))
        #expect(try Data(contentsOf: installed.appending(path: "Contents/MacOS/Tinker")) == Data("binary".utf8))
        // Installing is a copy; removing the original is the caller's decision.
        #expect(fileManager.fileExists(atPath: executable.path(percentEncoded: false)))
    }
}
