//
//  Project.swift
//  TextlinkEditor
//
//  프로젝트 모델
//

import Foundation

/// Creation-only template choices. Existing projects keep their on-disk folders.
struct ProjectCreationOptions {
    var includesDefaultFolders = true

    var orderedSections: [ProjectSection] {
        includesDefaultFolders ? ProjectSection.allCases : []
    }
}

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var lastOpenedAt: Date
    var path: URL?

    init(id: UUID = UUID(), name: String, path: URL? = nil) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.lastOpenedAt = Date()
        self.path = path
    }
}
