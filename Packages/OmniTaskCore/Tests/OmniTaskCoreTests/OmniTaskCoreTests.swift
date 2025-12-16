import XCTest
@testable import OmniTaskCore

final class OmniTaskCoreTests: XCTestCase {
    func testOmniTaskCreation() {
        let task = OmniTask(title: "Test Task")
        XCTAssertEqual(task.title, "Test Task")
        XCTAssertFalse(task.isCompleted)
        XCTAssertEqual(task.priority, .medium)
    }

    func testProjectCreation() {
        let project = Project(name: "Test Project", color: "#FF0000")
        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.color, "#FF0000")
        XCTAssertFalse(project.isArchived)
    }

    func testPriorityFromString() {
        XCTAssertEqual(Priority.from(string: "urgent"), .urgent)
        XCTAssertEqual(Priority.from(string: "high"), .high)
        XCTAssertEqual(Priority.from(string: "medium"), .medium)
        XCTAssertEqual(Priority.from(string: "low"), .low)
        XCTAssertEqual(Priority.from(string: "invalid"), .medium) // Default
    }

    func testRecurringPatternDaily() {
        let pattern = RecurringPattern.daily
        XCTAssertEqual(pattern.frequency, .daily)
        XCTAssertEqual(pattern.interval, 1)
    }

    func testRecurringPatternParsing() {
        let daily = RecurringPattern.parse(from: "daily")
        XCTAssertNotNil(daily)
        XCTAssertEqual(daily?.frequency, .daily)

        let weekly = RecurringPattern.parse(from: "every week")
        XCTAssertNotNil(weekly)
        XCTAssertEqual(weekly?.frequency, .weekly)

        let biweekly = RecurringPattern.parse(from: "every 2 weeks")
        XCTAssertNotNil(biweekly)
        XCTAssertEqual(biweekly?.interval, 2)
    }
}
