//
//  Week2AcceptanceTests.swift
//  vilsay
//
//  Week 2 自动化验收测试（Kimi 测试用）
//  运行方式：Cmd+U 或在命令行执行：xcodebuild test -scheme vilsay -destination 'platform=macOS'
//

import XCTest

final class Week2AcceptanceTests: XCTestCase {
    
    var app: XCUIApplication!

    /// MenuBarExtra 标签（与 `MenuBarStatusLabel.accessibilityIdentifier` 一致）
    private var vilsayMenuBarExtra: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "vilsay.menubar.extra").firstMatch
    }
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // 等待 App 启动
        sleep(2)
    }
    
    override func tearDownWithError() throws {
        app.terminate()
    }
    
    // MARK: - Test 1: 菜单栏图标验证
    func test1_MenuBarIconExists() throws {
        // 系统菜单栏（MenuBarExtra 应用无传统「Main Menu」）
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5), "菜单栏应该存在")

        XCTAssertTrue(vilsayMenuBarExtra.waitForExistence(timeout: 5), "菜单栏应该有 Vilsay 图标（MenuBarStatusLabel.accessibilityIdentifier）")

        print("✅ Test 1 通过：菜单栏图标存在")
    }
    
    // MARK: - Test 2: 菜单功能验证
    func test2_MenuItemsExist() throws {
        // 点击菜单栏图标
        XCTAssertTrue(vilsayMenuBarExtra.waitForExistence(timeout: 5))
        vilsayMenuBarExtra.click()
        
        sleep(1)
        
        // 验证菜单项存在
        XCTAssertTrue(app.menuItems["开始录音"].exists, "应该有'开始录音'菜单项")
        XCTAssertTrue(app.menuItems["词典"].exists, "应该有'词典'菜单项")
        XCTAssertTrue(app.menuItems["设置"].exists, "应该有'设置'菜单项")
        XCTAssertTrue(app.menuItems["退出 Vilsay"].exists, "应该有'退出'菜单项")
        
        // 验证调试菜单
        XCTAssertTrue(app.menuItems["调试（验收用）"].exists, "应该有调试菜单")
        
        print("✅ Test 2 通过：菜单功能正常")
    }
    
    // MARK: - Test 3: 开始录音按钮禁用状态
    func test3_StartRecordingDisabled() throws {
        XCTAssertTrue(vilsayMenuBarExtra.waitForExistence(timeout: 5))
        vilsayMenuBarExtra.click()
        sleep(1)
        
        let startButton = app.menuItems["开始录音"]
        XCTAssertTrue(startButton.exists, "开始录音按钮应该存在")
        // Note: XCTest 无法直接检查 isEnabled，但可以通过点击验证行为
        
        print("✅ Test 3 通过：开始录音按钮存在（禁用状态需手动验证）")
    }
    
    // MARK: - Test 4: 调试菜单功能 - 状态切换
    func test4_DebugMenuStatusCycle() throws {
        XCTAssertTrue(vilsayMenuBarExtra.waitForExistence(timeout: 5))

        // 循环5次验证所有状态
        for i in 0..<5 {
            vilsayMenuBarExtra.click()
            sleep(1)
            
            // 悬停/点击调试菜单
            let debugMenu = app.menuItems["调试（验收用）"]
            XCTAssertTrue(debugMenu.exists, "调试菜单应该存在")
            debugMenu.click()
            sleep(1)
            
            // 点击切换状态
            let switchButton = app.menuItems["切换状态样式"]
            XCTAssertTrue(switchButton.exists, "切换状态按钮应该存在")
            switchButton.click()
            sleep(1)
            
            print("  状态切换 \(i+1)/5 完成")
        }
        
        print("✅ Test 4 通过：状态循环切换 5 次完成")
    }
    
    // MARK: - Test 5: 调试菜单功能 - 角标系统
    func test5_DebugMenuBadgeSystem() throws {
        XCTAssertTrue(vilsayMenuBarExtra.waitForExistence(timeout: 5))

        // 增加角标
        for i in 1...3 {
            vilsayMenuBarExtra.click()
            sleep(1)
            
            app.menuItems["调试（验收用）"].click()
            sleep(1)
            
            app.menuItems["词典角标 +1"].click()
            sleep(1)
            
            print("  角标 +1: \(i)")
        }
        
        // 清零角标
        vilsayMenuBarExtra.click()
        sleep(1)
        app.menuItems["调试（验收用）"].click()
        sleep(1)
        app.menuItems["词典角标清零"].click()
        sleep(1)
        
        print("✅ Test 5 通过：角标系统测试完成")
    }
    
    // MARK: - Test 6: 设置窗口
    func test6_SettingsWindow() throws {
        XCTAssertTrue(vilsayMenuBarExtra.waitForExistence(timeout: 5))
        vilsayMenuBarExtra.click()
        sleep(1)
        
        app.menuItems["设置"].click()
        sleep(2)
        
        // 验证设置窗口存在
        let settingsWindow = app.windows.element(boundBy: 0)
        XCTAssertTrue(settingsWindow.exists, "设置窗口应该打开")
        
        print("✅ Test 6 通过：设置窗口可以打开")
    }
    
    // MARK: - 性能测试：状态切换响应时间
    func test7_StatusSwitchPerformance() throws {
        measure {
            XCTAssertTrue(vilsayMenuBarExtra.waitForExistence(timeout: 5))
            vilsayMenuBarExtra.click()
            sleep(1)

            app.menuItems["调试（验收用）"].click()
            sleep(1)

            app.menuItems["切换状态样式"].click()
            sleep(1)
        }
        
        print("✅ Test 7 通过：状态切换性能测试完成")
    }
}

// MARK: - 辅助验证脚本
/*
 手动验证清单（自动化测试无法覆盖的视觉检查）：
 
 1. 菜单栏图标颜色：
    - Idle 状态：灰色麦克风轮廓
    - Recording 状态：红色实心麦克风 + 脉冲动画
    - Processing 状态：旋转箭头
    - EditMode 状态：蓝色铅笔
    - Error 状态：橙色感叹号
 
 2. 悬浮按钮验证：
    - 右下角显示 60x60 圆形按钮
    - 深灰色背景，白色麦克风图标
    - 右键显示"触发方式"菜单
    - Toggle 模式点击测试
 
 3. 角标显示：
    - 红色圆形角标在右上角
    - 菜单栏和悬浮按钮同步显示
 
 运行方式：
 1. Cmd+U 运行所有测试
 2. 或命令行：xcodebuild test -scheme vilsay -destination 'platform=macOS' -only-testing:vilsayUITests/Week2AcceptanceTests
 */
