//
//  ContentView.swift
//  Loreweave
//

import SwiftUI

struct ContentView: View {
    @State private var projectManager = ProjectManager.shared

    var body: some View {
        if projectManager.currentProject != nil {
            MainEditorView(projectManager: projectManager)
        } else {
            WelcomeView(projectManager: projectManager)
        }
    }
}

#Preview {
    ContentView()
}
