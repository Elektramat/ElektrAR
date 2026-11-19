import XCTest
import simd
@testable import KabelmeterCore

final class CatalogTests: XCTestCase {
    func testBundledCatalogDecodesWithAPhotoPerRealCable() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Kabelmeter/Resources")
        let cables = try CableCatalog.decode(Data(contentsOf: resources.appendingPathComponent("cables.json")))
        XCTAssertTrue((10...15).contains(cables.count))
        for cable in cables where !cable.isSample {
            let photo = resources.appendingPathComponent("CableImages/\(cable.sku).jpg")
            XCTAssertTrue(FileManager.default.fileExists(atPath: photo.path), "No bundled photo for \(cable.sku)")
            XCTAssertTrue(cable.productUrl.absoluteString.hasPrefix("https://www.elektramat.nl/"))
            XCTAssertGreaterThan(cable.pricePerMeter, 0)
        }
    }

    func testRejectsEmptyFixedLengths() {
        let json = #"[{"id":"a","sku":"A","name":"A","crossSection":"x","use":"x","pricePerMeter":1,"sales":{"type":"fixedLengths","lengthsM":[]},"stock":"x","imageUrl":null,"productUrl":"https://www.elektramat.nl","isSample":true}]"#
        XCTAssertThrowsError(try CableCatalog.decode(Data(json.utf8)))
    }

    func testRejectsZeroStep() {
        let json = #"[{"id":"a","sku":"A","name":"A","crossSection":"x","use":"x","pricePerMeter":1,"sales":{"type":"perMeter","step":0,"minimum":1},"stock":"x","imageUrl":null,"productUrl":"https://www.elektramat.nl","isSample":true}]"#
        XCTAssertThrowsError(try CableCatalog.decode(Data(json.utf8)))
    }

    func testRejectsDuplicateIds() {
        let one = #"{"id":"a","sku":"A","name":"A","crossSection":"x","use":"x","pricePerMeter":1,"sales":{"type":"perMeter","step":1,"minimum":1},"stock":"x","imageUrl":null,"productUrl":"https://www.elektramat.nl","isSample":true}"#
        XCTAssertThrowsError(try CableCatalog.decode(Data("[\(one),\(one)]".utf8)))
    }
}

@MainActor
final class MeasureSessionTests: XCTestCase {
    func testTotalIncludesLivePreviewSegment() {
        let s = MeasureSession()
        s.cursor = [0, 0, 0]
        s.addPoint()
        s.cursor = [3, 0, 0]
        s.addPoint()
        XCTAssertEqual(s.confirmedLength, 3, accuracy: 1e-6)
        s.cursor = [3, 4, 0]
        XCTAssertEqual(s.totalLength, 7, accuracy: 1e-6)
    }

    func testNoPointWithoutCursor() {
        let s = MeasureSession()
        XCTAssertFalse(s.addPoint())
        XCTAssertTrue(s.points.isEmpty)
    }

    func testFinishFreezesPreviewAndUndoResumes() {
        let s = MeasureSession()
        s.cursor = [0, 0, 0]; s.addPoint()
        s.cursor = [1, 0, 0]; s.addPoint()
        s.cursor = [5, 0, 0]
        s.finish()
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.totalLength, 1, accuracy: 1e-6)
        XCTAssertFalse(s.addPoint())
        s.undo()
        XCTAssertFalse(s.isFinished)
        XCTAssertEqual(s.points.count, 1)
    }

    func testFinishNeedsTwoPoints() {
        let s = MeasureSession()
        s.cursor = [0, 0, 0]; s.addPoint()
        s.finish()
        XCTAssertFalse(s.isFinished)
    }

    func testReset() {
        let s = MeasureSession()
        s.cursor = [0, 0, 0]; s.addPoint()
        s.reset()
        XCTAssertTrue(s.points.isEmpty)
        XCTAssertEqual(s.totalLength, 0)
    }
}

@MainActor
final class CartStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "CartStoreTests-\(UUID().uuidString)")
    }

    private let cable = Cable(id: "c1", sku: "S1", name: "Kabel", crossSection: "3x1,5 mm²", use: "x",
                              pricePerMeter: 0.99, sales: .perMeter(step: 1, minimum: 1), stock: "x",
                              imageUrl: nil, productUrl: URL(string: "https://www.elektramat.nl")!, isSample: true)

    func testAddSameCableMergesMeters() {
        let store = CartStore(defaults: defaults)
        store.add(cable: cable, meters: 10)
        store.add(cable: cable, meters: 5)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.meters, 15)
        XCTAssertEqual(store.total, 14.85)
    }

    func testIgnoresZeroMeters() {
        let store = CartStore(defaults: defaults)
        store.add(cable: cable, meters: 0)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testPersists() {
        CartStore(defaults: defaults).add(cable: cable, meters: 11)
        XCTAssertEqual(CartStore(defaults: defaults).items.first?.meters, 11)
    }
}
