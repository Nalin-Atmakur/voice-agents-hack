import CoreGraphics
import XCTest
@testable import TacNet

final class TargetFusionTests: XCTestCase {
    private func makeBox(
        yMin: Double,
        xMin: Double,
        yMax: Double,
        xMax: Double
    ) -> TargetSighting.NormalizedBox {
        TargetSighting.NormalizedBox(yMin: yMin, xMin: xMin, yMax: yMax, xMax: xMax)
    }

    func testBearingAtCenter_returnsHeading() throws {
        let box = makeBox(yMin: 100, xMin: 400, yMax: 300, xMax: 600) // centroid x = 500

        let bearing = try XCTUnwrap(
            TargetFusion.bearingDegrees(for: box, horizontalFoVDegrees: 68, headingTrueNorth: 90)
        )

        XCTAssertEqual(bearing, 90, accuracy: 0.01)
    }

    func testBearingAtLeftEdge_subtractsHalfFoV() throws {
        let box = makeBox(yMin: 100, xMin: 0, yMax: 300, xMax: 0) // centroid x = 0

        let bearing = try XCTUnwrap(
            TargetFusion.bearingDegrees(for: box, horizontalFoVDegrees: 68, headingTrueNorth: 0)
        )

        XCTAssertEqual(bearing, 326, accuracy: 0.5)
    }

    func testBearingAtRightEdge_addsHalfFoV() throws {
        let box = makeBox(yMin: 100, xMin: 1000, yMax: 300, xMax: 1000) // centroid x = 1000

        let bearing = try XCTUnwrap(
            TargetFusion.bearingDegrees(for: box, horizontalFoVDegrees: 68, headingTrueNorth: 0)
        )

        XCTAssertEqual(bearing, 34, accuracy: 0.5)
    }

    func testBearingWrapsAt360() throws {
        let box = makeBox(yMin: 100, xMin: 1000, yMax: 300, xMax: 1000) // offset +20 when FoV is 40

        let bearing = try XCTUnwrap(
            TargetFusion.bearingDegrees(for: box, horizontalFoVDegrees: 40, headingTrueNorth: 350)
        )

        XCTAssertEqual(bearing, 10, accuracy: 0.01)
    }

    func testBearingReturnsNil_whenHeadingNil() {
        let box = makeBox(yMin: 100, xMin: 400, yMax: 300, xMax: 600)

        let bearing = TargetFusion.bearingDegrees(for: box, horizontalFoVDegrees: 68, headingTrueNorth: nil)

        XCTAssertNil(bearing)
    }

    func testPinholeDistance_knownGeometry() throws {
        let box = makeBox(yMin: 100, xMin: 400, yMax: 300, xMax: 600) // height = 20% of frame

        let distance = try XCTUnwrap(
            TargetFusion.pinholeDistanceMeters(
                for: box,
                imagePixelSize: CGSize(width: 4032, height: 3024),
                verticalFoVDegrees: 51,
                realWorldHeightMeters: 1.75
            )
        )

        XCTAssertEqual(distance, 9.1724, accuracy: 0.46)
    }

    func testPinholeDistance_returnsNil_onDegenerateBox() {
        let box = makeBox(yMin: 200, xMin: 300, yMax: 200, xMax: 700) // zero height

        let distance = TargetFusion.pinholeDistanceMeters(
            for: box,
            imagePixelSize: CGSize(width: 4032, height: 3024),
            verticalFoVDegrees: 51,
            realWorldHeightMeters: 1.75
        )

        XCTAssertNil(distance)
    }

    func testSuggestedHeight_coversCanonicalLabels() throws {
        XCTAssertEqual(try XCTUnwrap(TargetFusion.suggestedTargetHeightMeters(for: "person")), 1.75, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(TargetFusion.suggestedTargetHeightMeters(for: "truck")), 2.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(TargetFusion.suggestedTargetHeightMeters(for: "drone")), 0.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(TargetFusion.suggestedTargetHeightMeters(for: "car")), 1.5, accuracy: 0.001)
        XCTAssertNil(TargetFusion.suggestedTargetHeightMeters(for: "unknown"))
    }

    func testFuse_preferLidar_overPinhole() throws {
        let detection = RawDetection(
            box_2d: [100, 400, 300, 600],
            label: "person",
            description: "test target",
            confidence: 0.9
        )

        let sighting = try XCTUnwrap(
            TargetFusion.fuse(
                detection: detection,
                imagePixelSize: CGSize(width: 4032, height: 3024),
                horizontalFoVDegrees: 68,
                verticalFoVDegrees: 51,
                headingTrueNorth: 90,
                lidarRangeMeters: 42
            )
        )

        XCTAssertEqual(sighting.rangeSource, .lidar)
        XCTAssertEqual(try XCTUnwrap(sighting.rangeMeters), 42, accuracy: 0.001)
    }

    func testFuse_rejectsInvalidBox() {
        let detection = RawDetection(
            box_2d: [100, 500, 300, 500], // xMax == xMin
            label: "person",
            description: nil,
            confidence: nil
        )

        let sighting = TargetFusion.fuse(
            detection: detection,
            imagePixelSize: CGSize(width: 4032, height: 3024),
            horizontalFoVDegrees: 68,
            verticalFoVDegrees: 51,
            headingTrueNorth: 0,
            lidarRangeMeters: nil
        )

        XCTAssertNil(sighting)
    }

    func testPinholeFallbackSanityCheck() throws {
        let detection = RawDetection(
            box_2d: [400, 450, 900, 550],
            label: "person",
            description: "synthetic target",
            confidence: 0.8
        )

        let sighting = try XCTUnwrap(
            TargetFusion.fuse(
                detection: detection,
                imagePixelSize: CGSize(width: 4032, height: 3024),
                horizontalFoVDegrees: 68,
                verticalFoVDegrees: 51,
                headingTrueNorth: 0,
                lidarRangeMeters: nil
            )
        )

        XCTAssertEqual(sighting.rangeSource, .pinhole)
        XCTAssertEqual(try XCTUnwrap(sighting.rangeMeters), 3.6690, accuracy: 0.37)
        XCTAssertEqual(try XCTUnwrap(sighting.bearingDegreesTrueNorth), 0, accuracy: 1.0)
    }
}
