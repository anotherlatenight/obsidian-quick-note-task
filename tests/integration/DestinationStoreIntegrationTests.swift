import XCTest
@testable import ObsidianQuickNoteTask

final class DestinationStoreIntegrationTests: XCTestCase {
    private func resolvedPath(_ url: URL?) -> String? {
        url?.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func testPersistsDestinationAcrossStoreInstances() throws {
        let suiteName = "test.destination.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let dir = try makeTempDir()
        let first = DestinationStore(defaults: defaults, key: "destination")
        try first.saveDefaultFolderURL(dir)

        let second = DestinationStore(defaults: defaults, key: "destination")
        let loaded = second.loadDefaultFolderURL()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(resolvedPath(loaded), resolvedPath(dir))
    }

    func testPersistsVaultAcrossStoreInstances() throws {
        let suiteName = "test.destination.vault.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let vault = try makeTempDir()
        let first = DestinationStore(defaults: defaults, key: "destination")
        try first.saveVaultURL(vault)

        let second = DestinationStore(defaults: defaults, key: "destination")
        XCTAssertEqual(resolvedPath(second.loadVaultURL()), resolvedPath(vault))
    }

    func testLoadsPreviouslySavedSecurityScopedVaultBookmark() throws {
        let suiteName = "test.destination.legacy-vault.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let vault = try makeTempDir()
        let bookmark = try vault.bookmarkData(options: .withSecurityScope,
                                              includingResourceValuesForKeys: nil,
                                              relativeTo: nil)
        defaults.set(bookmark, forKey: "obsidian.vault.bookmark")

        let store = DestinationStore(defaults: defaults)
        XCTAssertEqual(resolvedPath(store.loadVaultURL()), resolvedPath(vault))
    }

    func testRejectsInaccessibleDestinationInput() throws {
        let suiteName = "test.destination.invalid.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)

        let store = DestinationStore(defaults: defaults, key: "destination")
        XCTAssertThrowsError(try store.saveDefaultFolderURL(fileURL))
        XCTAssertThrowsError(try store.saveVaultURL(fileURL))
    }

    func testDestinationSelectionPersistsAfterFolderIconRemoval() throws {
        let suiteName = "test.destination.folder-affordance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DestinationStore(defaults: defaults, key: "destination")
        let settings = SettingsController(destinationStore: store)
        XCTAssertFalse(settings.visualProfile().folderAffordance.iconVisible)

        let destination = try makeTempDir()
        try settings.selectDestination(destination)

        XCTAssertEqual(resolvedPath(store.loadDestinationURL()), resolvedPath(destination))
    }

    func testTaskExclusionTextPersistsAcrossStoreInstances() throws {
        let suiteName = "test.destination.exclusion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = DestinationStore(defaults: defaults, key: "destination")
        try first.saveTaskExclusionText("#snooze")

        let second = DestinationStore(defaults: defaults, key: "destination")
        XCTAssertEqual(second.loadTaskExclusionText(), "#snooze")
    }
}
