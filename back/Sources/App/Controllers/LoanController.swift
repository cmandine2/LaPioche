import Fluent
import Vapor

struct LoanController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let loans = routes.grouped("loans")
        loans.post(use: create)
        loans.post(":loanID", "return", use: returnLoan)
        loans.get("overdue", use: overdue)
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        let dto = try req.content.decode(CreateLoanDTO.self)

        guard let game = try await Game.find(dto.gameID, on: req.db) else {
            throw Abort(.notFound, reason: "Game not found")
        }
        guard let member = try await Member.find(dto.memberID, on: req.db) else {
            throw Abort(.notFound, reason: "Member not found")
        }
        let activeLoanExists = try await Loan.query(on: req.db)
            .filter(\.$game.$id == dto.gameID)
            .filter(\.$returnedAt == nil)
            .first() != nil

        guard !activeLoanExists else {
            throw Abort(.conflict, reason: "Game is already on loan")
        }
        let now = Date()
        let loan = Loan(
            gameID: try game.requireID(),
            memberID: try member.requireID(),
            borrowedAt: now,
            dueAt: try Loan.dueDate(from: now)
        )
        try await loan.save(on: req.db)
        return try await loan.toDTO().encodeResponse(status: .created, for: req)
    }
    @Sendable
    func returnLoan(req: Request) async throws -> LoanDTO {
        guard let loanID = req.parameters.get("loanID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid loan id")
        }
        guard let loan = try await Loan.find(loanID, on: req.db) else {
            throw Abort(.notFound, reason: "Loan not found")
        }
        //Vérifier que l'emprunt n'est pas déjà rendu
        guard loan.returnedAt == nil else {
            throw Abort(.conflict, reason: "Loan has already been returned")
        }
        //Enregistrer la date du retour
        loan.returnedAt = Date()
        try await loan.save(on: req.db)
        //Retourner l'emprunt modifié
        return loan.toDTO()
    }
    
    @Sendable
    func overdue(req: Request) async throws -> [LoanDTO] {
        // Récupérer la date actuelle
        let now = Date()
        // Chercher les emprunts non rendus dont la date limite est dépassée
        let loans = try await Loan.query(on: req.db)
            .filter(\.$returnedAt == nil)
            .filter(\.$dueAt < now)
            .all()
        // Retourner les emprunts sous forme de DTO
        return loans.map { $0.toDTO() }
    }

}
