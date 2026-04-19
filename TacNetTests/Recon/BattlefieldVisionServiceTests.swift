import CoreGraphics
import UIKit
import XCTest
@testable import TacNet

final class BattlefieldVisionServiceTests: XCTestCase {
    private struct FixedStorageChecker: StorageChecking {
        let availableBytes: Int64

        func availableStorageBytes(for _: URL) throws -> Int64 {
            availableBytes
        }
    }

    private func makeTestImage(size: CGSize = CGSize(width: 32, height: 32)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testBuildMessagesJSON_containsSystemPromptAndImagePath() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/recon-test-image.jpg")

        let messagesJSON = try BattlefieldVisionService.buildMessagesJSON(
            intent: "Identify dismounted combatants.",
            imageURL: imageURL
        )

        XCTAssertTrue(messagesJSON.contains("You are a military reconnaissance vision model"))
        let escapedPath = imageURL.path.replacingOccurrences(of: "/", with: "\\/")
        XCTAssertTrue(messagesJSON.contains(imageURL.path) || messagesJSON.contains(escapedPath))
    }

    func testBuildMessagesJSON_includesCactusNativeImagesField() throws {
        let imageURL = URL(fileURLWithPath: "/tmp/recon-test-image.jpg")

        let messagesJSON = try BattlefieldVisionService.buildMessagesJSON(
            intent: "Identify armored vehicles.",
            imageURL: imageURL
        )

        let jsonObject = try JSONSerialization.jsonObject(with: Data(messagesJSON.utf8), options: [])
        let messages = try XCTUnwrap(jsonObject as? [[String: Any]])
        let userMessage = try XCTUnwrap(messages.first { ($0["role"] as? String) == "user" })
        let images = try XCTUnwrap(userMessage["images"] as? [String])

        XCTAssertEqual(images, [imageURL.path])
    }

    func testBuildOptionsJSON_tokenBudget_matchesMode() throws {
        let expectedBudgets: [(ReconScanMode, Int)] = [
            (.quick, 280),
            (.standard, 560),
            (.detail, 1120)
        ]

        for (mode, expectedBudget) in expectedBudgets {
            let optionsJSON = BattlefieldVisionService.buildOptionsJSON(mode: mode)
            let object = try JSONSerialization.jsonObject(with: Data(optionsJSON.utf8), options: [])
            let dictionary = try XCTUnwrap(object as? [String: Any])
            let tokenBudget = (dictionary["image_token_budget"] as? NSNumber)?.intValue

            XCTAssertEqual(tokenBudget, expectedBudget, "Mode \(mode.rawValue) should map to expected image_token_budget")
        }
    }

    func testParseDetections_happyPath() throws {
        let response = """
        [
          {"box_2d":[100,200,300,400],"label":"person","description":"single soldier","confidence":0.95},
          {"box_2d":[50,60,250,260],"label":"truck","description":"light vehicle","confidence":0.72}
        ]
        """

        let detections = try BattlefieldVisionService.parseDetections(from: response)

        XCTAssertEqual(detections.count, 2)
        XCTAssertEqual(detections[0].box_2d, [100, 200, 300, 400])
        XCTAssertEqual(detections[0].label, "person")
        XCTAssertEqual(detections[0].description, "single soldier")
        XCTAssertEqual(try XCTUnwrap(detections[0].confidence), 0.95, accuracy: 0.0001)
        XCTAssertEqual(detections[1].box_2d, [50, 60, 250, 260])
        XCTAssertEqual(detections[1].label, "truck")
        XCTAssertEqual(detections[1].description, "light vehicle")
        XCTAssertEqual(try XCTUnwrap(detections[1].confidence), 0.72, accuracy: 0.0001)
    }

    func testParseDetections_stripsMarkdownFence() throws {
        let fencedResponse = """
        ```json
        [{"box_2d":[10,20,30,40],"label":"drone","description":"small UAV","confidence":0.88}]
        ```
        """

        let detections = try BattlefieldVisionService.parseDetections(from: fencedResponse)

        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections[0].box_2d, [10, 20, 30, 40])
        XCTAssertEqual(detections[0].label, "drone")
    }

    func testParseDetections_returnsEmptyForEmptyArray() throws {
        let detections = try BattlefieldVisionService.parseDetections(from: "[]")
        XCTAssertTrue(detections.isEmpty)
    }

    func testParseDetections_returnsEmptyForNonJSON() throws {
        let detections = try BattlefieldVisionService.parseDetections(from: "no targets visible.")
        XCTAssertTrue(detections.isEmpty)
    }

    func testParseDetections_filtersOutBadBoxLengths() throws {
        let response = """
        [
          {"box_2d":[1,2,3],"label":"invalid","description":"bad box","confidence":0.4},
          {"box_2d":[10,20,30,40],"label":"valid","description":"good box","confidence":0.9}
        ]
        """

        let detections = try BattlefieldVisionService.parseDetections(from: response)

        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections[0].label, "valid")
        XCTAssertEqual(detections[0].box_2d, [10, 20, 30, 40])
    }

    func testScan_invokesInjectedCompleteFunctionOnce() async throws {
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("BattlefieldVisionServiceTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: sandbox, withIntermediateDirectories: true)

        let suiteName = "BattlefieldVisionServiceTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
            try? fileManager.removeItem(at: sandbox)
        }

        let configuration = ModelDownloadConfiguration(
            modelURL: URL(string: "https://example.invalid/model.zip")!,
            expectedModelSizeBytes: 1,
            modelDirectoryName: "stub-model",
            modelFileName: ".complete",
            requiresZipArchive: true
        )

        let modelDirectory = sandbox.appendingPathComponent(configuration.modelDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        _ = fileManager.createFile(
            atPath: modelDirectory.appendingPathComponent(configuration.modelFileName, isDirectory: false).path,
            contents: Data(),
            attributes: nil
        )

        let downloadService = ModelDownloadService(
            configuration: configuration,
            storageChecker: FixedStorageChecker(availableBytes: 10_000_000),
            fileManager: fileManager,
            userDefaults: userDefaults,
            applicationSupportDirectory: sandbox,
            persistenceKeyPrefix: suiteName
        )

        let dummyModelHandle = try XCTUnwrap(UnsafeMutableRawPointer(bitPattern: 0xBEEF))
        let modelInitializationService = CactusModelInitializationService(
            downloadService: downloadService,
            initFunction: { _, _, _ in dummyModelHandle },
            destroyFunction: { _ in }
        )

        let callLogURL = sandbox.appendingPathComponent("complete-call-count.bin", isDirectory: false)
        try Data().write(to: callLogURL, options: .atomic)

        let cannedResponse = """
        [{"box_2d":[100,200,400,500],"label":"person","description":"single target","confidence":0.91}]
        """

        let service = BattlefieldVisionService(
            modelInitializationService: modelInitializationService,
            completeFunction: { _, _, _, _, _, _ in
                var callData = (try? Data(contentsOf: callLogURL)) ?? Data()
                callData.append(contentsOf: [0x01])
                try callData.write(to: callLogURL, options: .atomic)
                return cannedResponse
            },
            tempDirectory: sandbox,
            jpegQuality: 0.85
        )

        let detections = try await service.scan(
            image: makeTestImage(),
            intent: "Identify personnel.",
            mode: .standard
        )

        let callCount = try Data(contentsOf: callLogURL).count
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections[0].label, "person")
        XCTAssertEqual(detections[0].box_2d, [100, 200, 400, 500])
        XCTAssertEqual(try XCTUnwrap(detections[0].confidence), 0.91, accuracy: 0.0001)
    }
}
