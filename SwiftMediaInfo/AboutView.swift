import SwiftUI

struct AboutView: View {
    
    @State private var easterEggCounter = 0
    
    let githubURL = "https://github.com/Undisclosed0369/SwiftMediaInfo"
    let easterEggURL = "https://www.youtube.com/watch?v=4NJYWgb6dQM"
    
    var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "Version \(v) \(b)"
    }
    
    var body: some View {
        
        ZStack {
            
            Rectangle()
                .fill(.ultraThinMaterial)
            
            VStack(spacing: 20) {
                
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 128, height: 128)
                    .shadow(radius: 6)
                    .onTapGesture {
                        easterEggCounter += 1
                        
                        if easterEggCounter >= 4 {
                            if let url = URL(string: easterEggURL) {
                                NSWorkspace.shared.open(url)
                            }
                            easterEggCounter = 0
                        }
                    }
                
                VStack(spacing: 6) {
                    
                    Text("SwiftMediaInfo")
                        .font(.system(size: 28, weight: .semibold))
                    
                    Text(version)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                }
                
                Divider()
                    .padding(.vertical, 6)
                
                VStack(spacing: 8) {
                    
                    Text("Made with ❤️ by")
                        .font(.subheadline)
                    
                    Text("Undisclosed / Data Lass")
                        .font(.headline)
                    
                }
                
                VStack(spacing: 6) {
                    
                    Text("Credits")
                        .font(.headline)
                    
                    Text("ChatGPT, Google Gemini & Claude")
                        .foregroundStyle(.secondary)
                    
                    Text("I have not typed a single line of code for this app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    
                }
                
                Divider()
                    .padding(.vertical, 6)
                
                VStack(spacing: 8) {
                    
                    Text("View this project on GitHub")
                    
                    Button {
                        if let url = URL(string: githubURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Open GitHub Page", systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent)
                    
                }
                
                Divider()
                    .padding(.vertical, 6)
                
                Text("License: ??? idk lol")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
            }
            .padding(40)
            
        }
        .frame(width: 420, height: 520)
    }
}
