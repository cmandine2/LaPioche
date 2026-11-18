@testable import App
import XCTVapor

final class LoanTests: XCTestCase {
    private func borrow(
        _ app: Application,
        gameID: UUID,
        memberID: UUID,
        afterResponse: (XCTHTTPResponse) async throws -> Void
    ) async throws {
        try await app.test(.POST, "loans", beforeRequest: { req in
            try req.content.encode(CreateLoanDTO(gameID: gameID, memberID: memberID))
        }, afterResponse: afterResponse)
    }

    func testBorrowGameReturnsCreated() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            try await borrow(
                app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id)
            ) { res in
                XCTAssertEqual(res.status, .created)
                let loan = try res.content.decode(LoanDTO.self)
                XCTAssertEqual(loan.gameID, game.id)
                XCTAssertEqual(loan.memberID, member.id)
                XCTAssertNil(loan.returnedAt)
            }
        }
    }
//"Optional(13)") is not equal to ("Optional(14)")

    func testDueDateIsFourteenDaysAfterBorrowDate() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            try await borrow(
                app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id)
            ) { res in
                let loan = try res.content.decode(LoanDTO.self)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let days = calendar.dateComponents([.day], from: loan.borrowedAt, to: loan.dueAt).day
                XCTAssertEqual(days, 14)
            }
        }
    }

    func testBorrowedGameIsNoLongerAvailable() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)

            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(member.id)) { _ in }

            try await app.test(.GET, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertFalse(try res.content.decode(GameDTO.self).isAvailable)
            })
        }
    }
//("201 Created") is not equal to ("409 Conflict")

    func testBorrowingAGameAlreadyOnLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let first = try await createMember(app, email: "first@example.com")
            let second = try await createMember(app, name: "Alex", email: "second@example.com")
            let gameID = try XCTUnwrap(game.id)

            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(first.id)) { _ in }
            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(second.id)) { res in
                XCTAssertEqual(res.status, .conflict)
            }
        }
    }

    func testBorrowUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            let member = try await createMember(app)

            try await borrow(app, gameID: UUID(), memberID: try XCTUnwrap(member.id)) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }

    func testBorrowWithUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            let game = try await createGame(app)

            try await borrow(app, gameID: try XCTUnwrap(game.id), memberID: UUID()) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }
    func testOverdueLoanIsReturnedByEndpoint() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let now = Date()
            let loan = Loan(
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now.addingTimeInterval(-20 * 24 * 60 * 60),
                dueAt: now.addingTimeInterval(-6 * 24 * 60 * 60)
            )

            try await loan.save(on: app.db)

            try await app.test(.GET, "loans/overdue") { res async throws in
                XCTAssertEqual(res.status, .ok)

                let loans = try res.content.decode([LoanDTO].self)

                XCTAssertEqual(loans.count, 1)
                XCTAssertEqual(loans.first?.id, loan.id)
                XCTAssertNil(loans.first?.returnedAt)
            }
        }
    }
    
    func testReturnedLoanIsNotIncludedInOverdueLoans() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let now = Date()
            let loan = Loan(
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now.addingTimeInterval(-20 * 24 * 60 * 60),
                dueAt: now.addingTimeInterval(-6 * 24 * 60 * 60)
            )

            loan.returnedAt = now
            try await loan.save(on: app.db)

            try await app.test(.GET, "loans/overdue") { res async throws in
                XCTAssertEqual(res.status, .ok)

                let loans = try res.content.decode([LoanDTO].self)

                XCTAssertTrue(loans.isEmpty)
            }
        }
    }
    
    
    func testReturnLoanReturnsUpdatedLoan() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            try await borrow(
                app,
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id)
            ) { res async throws in
                XCTAssertEqual(res.status, .created)

                let createdLoan = try res.content.decode(LoanDTO.self)
                let loanID = try XCTUnwrap(createdLoan.id)

                try await app.test(
                    .POST,
                    "loans/\(loanID)/return"
                ) { returnRes async throws in
                    XCTAssertEqual(returnRes.status, .ok)

                    let returnedLoan = try returnRes.content.decode(LoanDTO.self)

                    XCTAssertEqual(returnedLoan.id, loanID)
                    XCTAssertNotNil(returnedLoan.returnedAt)
                }
            }
        }
    }
    func testReturnAlreadyReturnedLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            try await borrow(
                app,
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id)
            ) { res async throws in
                let createdLoan = try res.content.decode(LoanDTO.self)
                let loanID = try XCTUnwrap(createdLoan.id)

                try await app.test(.POST, "loans/\(loanID)/return") { firstRes async throws in
                    XCTAssertEqual(firstRes.status, .ok)
                }

                try await app.test(.POST, "loans/\(loanID)/return") { secondRes async throws in
                    XCTAssertEqual(secondRes.status, .conflict)
                }
            }
        }
    }
    func testReturnUnknownLoanReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(
                .POST,
                "loans/\(UUID())/return"
            ) { res async throws in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }
    func testGameBecomesAvailableAfterLoanIsReturned() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let gameID = try XCTUnwrap(game.id)

            try await borrow(
                app,
                gameID: gameID,
                memberID: try XCTUnwrap(member.id)
            ) { res async throws in
                let createdLoan = try res.content.decode(LoanDTO.self)
                let loanID = try XCTUnwrap(createdLoan.id)

                try await app.test(.POST, "loans/\(loanID)/return") { returnRes async throws in
                    XCTAssertEqual(returnRes.status, .ok)
                }

                try await app.test(.GET, "games/\(gameID)") { gameRes async throws in
                    XCTAssertEqual(gameRes.status, .ok)

                    let updatedGame = try gameRes.content.decode(GameDTO.self)
                    XCTAssertTrue(updatedGame.isAvailable)
                }
            }
        }
    }
}
