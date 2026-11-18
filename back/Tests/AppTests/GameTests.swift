@testable import App
import XCTVapor
//("200 OK") is not equal to ("201 Created")
final class GameTests: XCTestCase {
    func testCreateGameReturnsCreated() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                let game = try res.content.decode(GameDTO.self)
                XCTAssertEqual(game.title, "Catan")
                XCTAssertTrue(game.isAvailable)
            })
        }
    }

    func testCreateGameWithEmptyTitleIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testCreateGameWithInvertedPlayerBoundsIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 5, maxPlayers: 2, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testListGames() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")

            try await app.test(.GET, "games", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode([GameDTO].self).count, 2)
            })
        }
    }

    func testShowGame() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode(GameDTO.self).id, id)
            })
        }
    }
//("500 Internal Server Error") is not equal to ("404 Not Found")

    func testShowUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testShowGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testPreflightRequestFromAnotherOriginIsAllowed() async throws {
        try await withApp { app in
            try await app.test(.OPTIONS, "games", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
                req.headers.replaceOrAdd(name: .accessControlRequestMethod, value: "POST")
                req.headers.replaceOrAdd(name: .accessControlRequestHeaders, value: "content-type")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
                XCTAssertTrue(res.headers[.accessControlAllowMethods].joined(separator: ",").contains("POST"))
            })
        }
    }

    func testErrorResponsesCarryTheCorsHeaders() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/not-a-uuid", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
            })
        }
    }
    func testUpdateGameReturnsUpdatedGame() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let gameID = try XCTUnwrap(game.id)

            try await app.test(.PUT, "games/\(gameID)", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan Updated",
                    minPlayers: 2,
                    maxPlayers: 5,
                    durationMinutes: 60
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let updatedGame = try res.content.decode(GameDTO.self)
                XCTAssertEqual(updatedGame.title, "Catan Updated")
                XCTAssertEqual(updatedGame.minPlayers, 2)
                XCTAssertEqual(updatedGame.maxPlayers, 5)
                XCTAssertEqual(updatedGame.durationMinutes, 60)
            })
        }
    }
    func testUpdateUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.PUT, "games/\(UUID())", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan",
                    minPlayers: 2,
                    maxPlayers: 4,
                    durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }
    func testDeleteGameReturnsNoContent() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let gameID = try XCTUnwrap(game.id)

            try await app.test(.DELETE, "games/\(gameID)") { res async throws in
                XCTAssertEqual(res.status, .noContent)
            }

            try await app.test(.GET, "games/\(gameID)") { res async throws in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }
    func testDeleteGameWithLoanHistoryReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)

            // Créer un emprunt directement
            let loan = Loan(
                gameID: gameID,
                memberID: try XCTUnwrap(member.id),
                borrowedAt: Date(),
                dueAt: try Loan.dueDate(from: Date())
            )

            try await loan.save(on: app.db)

            // Vérifier que la suppression est refusée
            try await app.test(.DELETE, "games/\(gameID)") { res async throws in
                XCTAssertEqual(res.status, .conflict)
            }
        }
    }
    
    func testSearchGamesByTitleIsCaseInsensitive() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")

            try await app.test(.GET, "games?q=cAtAn") { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)

                XCTAssertEqual(games.count, 1)
                XCTAssertEqual(games.first?.title, "Catan")
            }
        }
    }

    func testFilterGamesByPlayers() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")

            try await app.test(.GET, "games?players=4") { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)

                for game in games {
                    XCTAssertLessThanOrEqual(game.minPlayers, 4)
                    XCTAssertGreaterThanOrEqual(game.maxPlayers, 4)
                }
            }
        }
    }

    func testFilterGamesByMaxDuration() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")

            try await app.test(.GET, "games?maxDuration=60") { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)

                for game in games {
                    XCTAssertLessThanOrEqual(game.durationMinutes, 60)
                }
            }
        }
    }

    func testSearchGamesWithCombinedFilters() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")

            try await app.test(
                .GET,
                "games?q=cat&players=4&maxDuration=60"
            ) { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)

                for game in games {
                    XCTAssertTrue(game.title.localizedCaseInsensitiveContains("cat"))
                    XCTAssertLessThanOrEqual(game.minPlayers, 4)
                    XCTAssertGreaterThanOrEqual(game.maxPlayers, 4)
                    XCTAssertLessThanOrEqual(game.durationMinutes, 60)
                }
            }
        }
    }
    
    func testSearchGamesWithZeroPlayersReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games?players=0") { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }

    func testSearchGamesWithNegativePlayersReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games?players=-2") { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }


    func testSearchGamesWithInvalidPlayersReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games?players=abc") { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }

    func testSearchGamesWithZeroMaxDurationReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games?maxDuration=0") { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }

    func testSearchGamesWithNegativeMaxDurationReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games?maxDuration=-10") { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }
    func testFilterBorrowedGames() async throws {
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

            try await app.test(.GET, "games?available=false") { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)

                XCTAssertEqual(games.count, 1)
                XCTAssertFalse(games[0].isAvailable)
            }
        }
    }
    func testFilterAvailableGames() async throws {
        try await withApp { app in
            _ = try await createGame(app)

            try await app.test(.GET, "games?available=true") { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)

                XCTAssertEqual(games.count, 1)
                XCTAssertTrue(games[0].isAvailable)
            }
        }
    }
    func testFilterGamesWithInvalidAvailabilityReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games?available=maybe") { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            }
        }
    }
    func testSearchGamesWithAvailabilityFilter() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")

            try await app.test(
                .GET,
                "games?q=cat&players=4&maxDuration=60&available=true"
            ) { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)

                XCTAssertEqual(games.count, 1)
                XCTAssertTrue(games[0].title.localizedCaseInsensitiveContains("cat"))
                XCTAssertTrue(games[0].isAvailable)
            }
        }
    }
}
