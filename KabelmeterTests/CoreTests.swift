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

final class WebShopOrderTests: XCTestCase {
    private func item(_ meters: Double, sku: String = "401169628") -> CartItem {
        CartItem(id: UUID(), cableId: sku, sku: sku, name: "YMvK kabel 3x1,5", crossSection: "3x1,5 mm²",
                 pricePerMeter: 1.45, meters: meters,
                 productUrl: URL(string: "https://www.elektramat.nl/ymvk-kabel-3x1-5-per-meter/")!, isSample: false)
    }

    func testWholeMetersStayTheSame() {
        XCTAssertEqual(WebShopOrder.lines(for: [item(10)]).map(\.quantity), [10])
    }

    func testFloatingPointNoiseDoesNotAddAMeter() {
        XCTAssertEqual(WebShopOrder.lines(for: [item(10.000000001)]).map(\.quantity), [10])
    }

    func testPartialMeterRoundsUp() {
        XCTAssertEqual(WebShopOrder.lines(for: [item(7.2)]).map(\.quantity), [8])
    }

    func testSkipsEmptyAndInvalidLengths() {
        XCTAssertTrue(WebShopOrder.lines(for: [item(0), item(-1), item(.nan), item(.infinity)]).isEmpty)
    }

    func testKeepsOrderAndProductData() {
        let lines = WebShopOrder.lines(for: [item(3, sku: "A"), item(12, sku: "B")])
        XCTAssertEqual(lines.map(\.sku), ["A", "B"])
        XCTAssertEqual(lines.map(\.quantity), [3, 12])
        XCTAssertEqual(lines.first?.productUrl.host, "www.elektramat.nl")
    }

    func testEmptyCartHasNoLines() {
        XCTAssertTrue(WebShopOrder.lines(for: []).isEmpty)
    }

    func testPassesShopProductId() {
        var withId = item(5)
        withId.shopProductId = 610957
        XCTAssertEqual(WebShopOrder.lines(for: [withId, item(3)]).map(\.productId), [610957, nil])
    }

    // MARK: missing(_:before:after:)

    private func line(_ sku: String, _ quantity: Int) -> WebShopLine {
        WebShopLine(sku: sku, name: sku, productUrl: URL(string: "https://www.elektramat.nl/")!,
                    productId: 1, quantity: quantity)
    }

    func testAllArrivedIntoEmptyCart() {
        XCTAssertTrue(WebShopOrder.missing([line("A", 7)], before: [:], after: ["A": 7]).isEmpty)
    }

    func testCountsOnlyWhatWasAddedOnTopOfAnExistingLine() {
        let result = WebShopOrder.missing([line("A", 7)], before: ["A": 4], after: ["A": 8])
        XCTAssertEqual(result, [.init(line: line("A", 7), arrived: 4)])
    }

    func testNothingArrived() {
        let result = WebShopOrder.missing([line("A", 3), line("B", 2)], before: ["B": 1], after: ["A": 3, "B": 1])
        XCTAssertEqual(result, [.init(line: line("B", 2), arrived: 0)])
    }

    func testCartShrankCountsAsNothingArrived() {
        let result = WebShopOrder.missing([line("A", 2)], before: ["A": 5], after: ["A": 1])
        XCTAssertEqual(result, [.init(line: line("A", 2), arrived: 0)])
    }

    func testSameSkuTwiceSharesWhatArrivedInOrder() {
        let result = WebShopOrder.missing([line("A", 3), line("A", 4)], before: [:], after: ["A": 5])
        XCTAssertEqual(result, [.init(line: line("A", 4), arrived: 2)])
    }

    func testNoLinesNoShortfall() {
        XCTAssertTrue(WebShopOrder.missing([], before: ["A": 1], after: [:]).isEmpty)
    }
}

@MainActor
final class CartStoreShopIdTests: XCTestCase {
    func testMergeFillsMissingShopProductId() {
        let defaults = UserDefaults(suiteName: "CartStoreShopIdTests")!
        defaults.removePersistentDomain(forName: "CartStoreShopIdTests")
        var old = Cable(id: "c1", sku: "S1", name: "Kabel", crossSection: "3x1,5 mm²", use: "x",
                        pricePerMeter: 1, sales: .perMeter(step: 1, minimum: 1), stock: "x",
                        imageUrl: nil, productUrl: URL(string: "https://www.elektramat.nl/")!, isSample: false)
        let store = CartStore(defaults: defaults)
        store.add(cable: old, meters: 2)
        old.shopProductId = 42
        store.add(cable: old, meters: 3)
        XCTAssertEqual(store.items.first?.shopProductId, 42)
        XCTAssertEqual(store.items.first?.meters, 5)
    }
}
