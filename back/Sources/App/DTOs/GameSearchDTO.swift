//
//  GameSearchDTO.swift
//  LaPioche
//
//  Created by Awatef on 16/11/2026.
//


import Vapor

struct GameSearchDTO: Content {
    let q: String?
    let players: Int?
    let maxDuration: Int?
}
