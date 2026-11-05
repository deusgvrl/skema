//
//  Skema_Tests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 05/11/26.
//

import Testing
import Foundation
@testable import Final_Challenge_App

@Suite("Project setup")
struct ProjectSetupTests {

    @Test("App uses the real bundle ID")
    func bundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "com.skema.adac5a10")
    }

    @Test("App is iPhone only")
    func iPhoneOnly() {
        let deviceFamilies = Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int]
        #expect(deviceFamilies == [1])
    }
}

