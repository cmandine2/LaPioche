import Fluent
import Vapor

struct GameController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let games = routes.grouped("games")
        games.get(use: index)
        games.post(use: create)
        games.get(":gameID", use: show)
        games.put(":gameID", use: update)
        games.delete(":gameID", use: delete)
    }

    @Sendable
    func index(req: Request) async throws -> [GameDTO] {
        let games = try await Game.query(on: req.db)
            .with(\.$loans)
            .all()
        return games.map { $0.toDTO() }
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
        //Vérifier et valider les données reçues
        try CreateGameDTO.validate(content: req)
        let dto = try req.content.decode(CreateGameDTO.self)
        try dto.ensureConsistentPlayerCount()
        //Récupérer le jeu existant
        let game = try await findGame(req)
        //Modifier les informations du jeu
        game.title = dto.title
        game.minPlayers = dto.minPlayers
        game.maxPlayers = dto.maxPlayers
        game.durationMinutes = dto.durationMinutes
        //Enregistrer les modifications dans la base de données
        try await game.save(on: req.db)
        //Retourner le jeu modifié
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
        //Récupérer le jeu existant
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
