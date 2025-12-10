import SwiftUI

@main
struct PoeticRecorderApp: App {
    
    init() {
        print("🟢 [APP] PoeticRecorderApp init started")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    print("🟢 [APP] ContentView appeared")
                }
        }
    }
}

