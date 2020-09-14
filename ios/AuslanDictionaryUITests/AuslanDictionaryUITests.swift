//
//  AuslanDictionaryUITests.swift
//  AuslanDictionaryUITests
//
//  Created by Daniel Porteous on 9/15/20.
//

import XCTest

class AuslanDictionaryUITests: XCTestCase {
    
    override func setUp() {
        let app = XCUIApplication()
        
        continueAfterFailure = false
        
        setupSnapshot(app)
        app.launch()
        super.setUp()
    }

    // Importantly, this function name must start with test.
    func testTakeScreenshots() {
        
        let app = XCUIApplication()
        let searchButton = app/*@START_MENU_TOKEN@*/.buttons["Search"]/*[[".keyboards",".buttons[\"search\"]",".buttons[\"Search\"]"],[[[-1,2],[-1,1],[-1,0,1]],[[-1,2],[-1,1]]],[0]]@END_MENU_TOKEN@*/
        searchButton.tap()
        
        sleep(1)
        
        snapshot("01-InitialSearchScreen")
        
        app.textFields["Search for a word"].tap()
        
        let bKey = app/*@START_MENU_TOKEN@*/.keys["b"]/*[[".keyboards.keys[\"b\"]",".keys[\"b\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        bKey.tap()
        
        let aKey = app/*@START_MENU_TOKEN@*/.keys["a"]/*[[".keyboards.keys[\"a\"]",".keys[\"a\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        aKey.tap()
        
        let nKey = app/*@START_MENU_TOKEN@*/.keys["n"]/*[[".keyboards.keys[\"n\"]",".keys[\"n\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        nKey.tap()
        
        searchButton.tap()
        
        sleep(1)
        
        snapshot("02-PostSearchScreen")
        
        app.buttons["ban"].tap()
        
        sleep(5)
        snapshot("03-WordScreen")
        
    }
}
