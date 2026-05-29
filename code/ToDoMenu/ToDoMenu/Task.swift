//
//  Task.swift
//  ToDoMenu
//
//  Created by Sreekar Nimmagadda on 5/28/26.
//

import Foundation

struct Task: Identifiable, Codable, Hashable {
    var id = UUID()
    let text: String
}
