import Fluent
import Vapor


struct GameSearchQuery: Content {
    let q: String?
    let players: Int?
    let maxDuration: Int?
    let available: String?
}

struct GameController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let games = routes.grouped("games")
        games.get(use: index)
        games.post(use: create)
        games.get(":gameID", use: show)
        games.put(":gameID", use: update)
        games.delete(":gameID", use: delete)
    }

//    @Sendable
//    func index(req: Request) async throws -> [GameDTO] {
//        let games = try await Game.query(on: req.db)
//            .with(\.$loans)
//            .all()
//        return games.map { $0.toDTO() }
//    }
    @Sendable
    func index(req: Request) async throws -> [GameDTO] {

        let filters = try req.query.decode(GameSearchQuery.self)

        // Vérifier que les nombres sont positifs
        if let players = filters.players, players <= 0 {
            throw Abort(.badRequest, reason: "Players must be a positive integer")
        }

        if let maxDuration = filters.maxDuration, maxDuration <= 0 {
            throw Abort(.badRequest, reason: "Max duration must be a positive integer")
        }
        let availability: Bool?

        if let value = filters.available {
            guard value == "true" || value == "false" else {
                throw Abort(.badRequest, reason: "Available must be true or false")
            }

            availability = value == "true"
        } else {
            availability = nil
        }
        // Construire la recherche
        let gamesQuery = Game.query(on: req.db)
            .with(\.$loans)

        if let players = filters.players {
            gamesQuery
                .filter(\.$minPlayers <= players)
                .filter(\.$maxPlayers >= players)
        }

        if let maxDuration = filters.maxDuration {
            gamesQuery.filter(\.$durationMinutes <= maxDuration)
        }

        let games = try await gamesQuery.all()

        let filteredGames = games.filter { game in

            let matchesTitle: Bool
            if let search = filters.q?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !search.isEmpty {
                matchesTitle = game.title.localizedCaseInsensitiveContains(search)
            } else {
                matchesTitle = true
            }

            let matchesAvailability: Bool
            if let availability {
                matchesAvailability = game.isAvailable == availability
            } else {
                matchesAvailability = true
            }

            return matchesTitle && matchesAvailability
        }

        return filteredGames.map { $0.toDTO() }
    }
    @Sendable
    func create(req: Request) async throws -> Response {
        try CreateGameDTO.validate(content: req)
        let dto = try req.content.decode(CreateGameDTO.self)
        try dto.ensureConsistentPlayerCount()

        let game = dto.toModel()
        try await game.save(on: req.db)
        let response =  try await game.toDTO().encodeResponse(for: req)
        response.status = .created
        return response
    }

    @Sendable
    func update(req: Request) async throws -> GameDTO {
        try CreateGameDTO.validate(content: req)
        let dto = try req.content.decode(CreateGameDTO.self)
        try dto.ensureConsistentPlayerCount()
        let game = try await findGame(req)
        
        //Modifier les informations du jeu
        game.title = dto.title
        game.minPlayers = dto.minPlayers
        game.maxPlayers = dto.maxPlayers
        game.durationMinutes = dto.durationMinutes
        try await game.save(on: req.db)
        return try await findGame(req).toDTO()
    }

    
    @Sendable
    func show(req: Request) async throws -> GameDTO {
        try await findGame(req).toDTO()
    }

    private func findGame(_ req: Request) async throws -> Game {
        guard let gameID = req.parameters.get("gameID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid game id")
        }
        guard let game = try await Game.query(on: req.db)
            .filter(\.$id == gameID)
            .with(\.$loans)
            .first()
        else {
            throw Abort(.notFound, reason: "Game not found")
        }
        return game
    }
    
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let game = try await findGame(req)
        //Vérifier si le jeu possède des emprunts
        let loans = try await Loan.query(on: req.db)
            .filter(\.$game.$id == game.requireID())
            .all()
        //Refuser la suppression si un emprunt existe
        guard loans.isEmpty else {
            throw Abort(.conflict, reason: "Cannot delete a game with loan history")
        }
        try await game.delete(on: req.db)
        return .noContent
    }
    
}
