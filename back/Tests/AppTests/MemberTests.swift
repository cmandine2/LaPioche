@testable import App
import XCTVapor

final class MemberTests: XCTestCase {
    func testCreateMemberReturnsCreated() async throws {
        try await withApp { app in
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                XCTAssertEqual(try res.content.decode(MemberDTO.self).name, "Camille")
            })
        }
    }

    func testCreateMemberWithInvalidEmailIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "not-an-email"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testCreateMemberWithDuplicateEmailReturnsConflict() async throws {
        try await withApp { app in
            _ = try await createMember(app)

            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Autre", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testShowUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "members/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    func testUpdateMemberReturnsUpdatedMember() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let memberID = try XCTUnwrap(member.id)

            try await app.test(.PUT, "members/\(memberID)", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(
                    name: "Camille Updated",
                    email: "camille.updated@example.com"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let updatedMember = try res.content.decode(MemberDTO.self)
                XCTAssertEqual(updatedMember.name, "Camille Updated")
                XCTAssertEqual(updatedMember.email, "camille.updated@example.com")
            })
        }
    }
    func testUpdateUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.PUT, "members/\(UUID())", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(
                    name: "Camille",
                    email: "camille@example.com"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    func testUpdateMemberWithDuplicateEmailReturnsConflict() async throws {
        try await withApp { app in
            _ = try await createMember(
                app,
                name: "Camille",
                email: "camille@example.com"
            )

            let second = try await createMember(
                app,
                name: "Alex",
                email: "alex@example.com"
            )

            let secondID = try XCTUnwrap(second.id)

            try await app.test(.PUT, "members/\(secondID)", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(
                    name: "Alex Updated",
                    email: "camille@example.com"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }
    func testDeleteMemberReturnsNoContent() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let memberID = try XCTUnwrap(member.id)

            try await app.test(.DELETE, "members/\(memberID)") { res async throws in
                XCTAssertEqual(res.status, .noContent)
            }

            try await app.test(.GET, "members/\(memberID)") { res async throws in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }
    func testDeleteMemberWithLoanHistoryReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let loan = Loan(
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: Date(),
                dueAt: try Loan.dueDate(from: Date())
            )

            try await loan.save(on: app.db)

            let memberID = try XCTUnwrap(member.id)

            try await app.test(.DELETE, "members/\(memberID)") { res async throws in
                XCTAssertEqual(res.status, .conflict)
            }
        }
    }
    func testGetMemberLoansReturnsLoans() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let loan = Loan(
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: Date(),
                dueAt: try Loan.dueDate(from: Date())
            )

            try await loan.save(on: app.db)

            let memberID = try XCTUnwrap(member.id)

            try await app.test(.GET, "members/\(memberID)/loans") { res async throws in
                XCTAssertEqual(res.status, .ok)

                let loans = try res.content.decode([LoanDTO].self)

                XCTAssertEqual(loans.count, 1)
                XCTAssertEqual(loans.first?.gameID, game.id)
                XCTAssertEqual(loans.first?.memberID, member.id)
            }
        }
    }
    func testGetMemberLoansReturnsEmptyList() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let memberID = try XCTUnwrap(member.id)

            try await app.test(.GET, "members/\(memberID)/loans") { res async throws in
                XCTAssertEqual(res.status, .ok)

                let loans = try res.content.decode([LoanDTO].self)

                XCTAssertTrue(loans.isEmpty)
            }
        }
    }
    func testGetLoansForUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "members/\(UUID())/loans") { res async throws in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }
}
