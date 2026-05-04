//
//  ClothIQUITests.swift
//  ClothIQUITests
//
//  Created by EUN YEON on 10/22/25.
//

import XCTest
import UIKit

final class ClothIQUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testUnsupportedDeviceGuidanceIsScrollableOnIPhone() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-in-memory")
        app.launch()

        let title = app.staticTexts["기기가 지원되지 않습니다"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        let supportedDevicesHeading = app.staticTexts["지원되는 기기"]
        if !supportedDevicesHeading.exists {
            app.swipeUp()
        }
        XCTAssertTrue(supportedDevicesHeading.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["iPhone"].exists)

        let footer = app.staticTexts["ClothIQ는 LiDAR 센서가 탑재된 기기에서만 사용할 수 있습니다."]
        if !footer.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(footer.waitForExistence(timeout: 2))
        XCTAssertTrue(footer.isHittable)
    }

    @MainActor
    func testIPhoneLibraryEmptyStateHasSinglePrimaryAddAction() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("iPhone compact UX 전용 검증")
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-in-memory",
            "--ui-testing-bypass-device-check"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["아직 저장된 의류가 없습니다"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["의류 추가하기"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["library-floating-add-button"].exists)
    }

    @MainActor
    func testIPadLibraryEmptyStateUsesSplitViewPlaceholder() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad split view UX 전용 검증")
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-in-memory",
            "--ui-testing-bypass-device-check"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["의류가 없습니다"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["상단의 + 버튼으로 첫 번째 의류를 추가하세요"].exists)
        XCTAssertTrue(app.staticTexts["+ 버튼을 눌러 첫 번째 의류를 추가하세요"].exists)
        XCTAssertTrue(app.buttons["library-ipad-add-button"].exists)
    }
}
