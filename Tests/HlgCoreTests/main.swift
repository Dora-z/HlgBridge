import Foundation

// A dependency-free test runner, runnable with Command Line Tools (no XCTest SDK needed).
var failures = 0
struct CheckError: Error {}
func fail(_ message: String, file: StaticString, line: UInt) {
    failures += 1; print("FAIL \(file):\(line): \(message)")
}
func XCTAssertEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try left(), b = try right(); if a != b { fail("values differ", file: file, line: line) } }
    catch { fail("\(error)", file: file, line: line) }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { fail("expected true", file: file, line: line) } }
    catch { fail("\(error)", file: file, line: line) }
}
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { fail("expected nil", file: file, line: line) }
}
func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value == nil { fail("unexpected nil", file: file, line: line) }
}
func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw CheckError() }; return value }
func XCTAssertThrowsError<T>(_ block: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try block(); fail("expected an error", file: file, line: line) } catch {}
}
let cases: [(String, (ConverterTests) throws -> Void)] = [
    ("HLG 双输出 / 元数据 / HDR 解码 / SDR 底图一致", { try $0.testHLGDualOutputMetadataAndHDRDecode() }),
    ("SDR 不生成 HDR", { try $0.testSDRDoesNotInventHDR() }),
    ("方向和 GPS", { try $0.testOrientationAndGPS() }),
    ("未知色彩和损坏文件", { try $0.testUnknownProfileAndCorruption() }),
    ("文件冲突不覆盖", { try $0.testCollisionDoesNotReplaceOriginal() }),
    ("取消和无写入权限清理", { try $0.testCancelledAndUnwritableLeaveNoTemporaryFiles() }),
    ("主体提亮 / 中性色 / 黑白端点 / SDR 不变", { try $0.testSubjectTonePreservesEndpointsAndRaisesMidtones() }),
    ("机内近似 / 灰阶单调 / 高光 / SDR 不变", { try $0.testCameraToneMonotonicNeutralAndSDRBypass() }),
    ("导出与预览不重复压暗 HDR", { try $0.testExportedSDRDoesNotRemapHDRTwice() }),
    ("递归扫描去重", { try $0.testRecursiveScannerDeduplicates() })
]
for (name, test) in cases {
    let suite = ConverterTests(), before = failures
    do {
        try suite.setUpWithError()
        defer { try? suite.tearDownWithError() }
        try autoreleasepool { try test(suite) }
    } catch { failures += 1; print("FAIL \(name): \(error)") }
    if failures == before { print("PASS \(name)") }
}
print("\(cases.count) scenarios; \(failures) failures")
exit(failures == 0 ? 0 : 1)
