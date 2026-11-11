import Foundation
import Testing
@testable import ForgeCore

private func seeded() throws -> Forge {
    let f = try Forge.inMemory()
    try f.perform([.putExercise(Exercise(id: "a", name: "A")), .putExercise(Exercise(id: "b", name: "B")), .putExercise(Exercise(id: "c", name: "C"))], author: .me)
    return f
}

private func exerciseCount(_ f: Forge) throws -> Int { try f.exercises().count }

@Suite struct ReadOnlySQLTests {
    @Test func selectReturnsOrderedColumnsAndRows() throws {
        let f = try seeded()
        let result = try f.query(sql: "select id, name from exercises order by name")
        #expect(result.columns == ["id", "name"])
        #expect(result.rows == [[.text("a"), .text("A")], [.text("b"), .text("B")], [.text("c"), .text("C")]])
    }

    @Test func valuesKeepTheirTypes() throws {
        let f = try Forge.inMemory()
        #expect(try f.query(sql: "select 1 as a, 2.5 as b, null as c, 'x' as d").rows == [[.int(1), .double(2.5), .null, .text("x")]])
    }

    @Test func insertRejectedAndTableUnchanged() throws {
        let f = try seeded()
        #expect(throws: ForgeError.self) { try f.query(sql: "insert into bodyweight (date, kg) values ('2026-01-01', 80)") }
        #expect(try f.db.read { try Int.fetchOne($0, sql: "select count(*) from bodyweight") } == 0)
    }

    @Test func deleteRejected() throws {
        let f = try seeded()
        #expect(throws: ForgeError.self) { try f.query(sql: "delete from exercises") }
        #expect(try exerciseCount(f) == 3)
    }

    @Test func cteWrappedDeleteRejected() throws {
        let f = try seeded()
        #expect(throws: ForgeError.self) { try f.query(sql: "with x as (select 1) delete from exercises") }
        #expect(try exerciseCount(f) == 3)
    }

    @Test func pragmaWriteRejected() throws {
        let f = try seeded()
        #expect(throws: ForgeError.self) { try f.query(sql: "pragma user_version = 7") }
        #expect(try f.db.read { try Int.fetchOne($0, sql: "pragma user_version") } == 0)
    }

    @Test func multiStatementRejected() throws {
        let f = try seeded()
        #expect(throws: ForgeError.self) { try f.query(sql: "select 1; delete from exercises") }
        #expect(try exerciseCount(f) == 3)
    }

    @Test func limitCapsRows() throws {
        let f = try seeded()
        #expect(try f.query(sql: "select id from exercises", limit: 2).rows.count == 2)
    }
}
