import SwiftUI

struct AboutView: View {
    
    @State private var easterEggCounter = 0
    
    let githubURL = "https://github.com/Undisclosed0369/SwiftMediaInfo"
    
    // Replaced the single URL with your full array
    let easterEggURLs = [
        "https://www.youtube.com/watch?v=IAYhEkVtNuQ",
        "https://www.youtube.com/watch?v=figEzfMTwQQ",
        "https://www.youtube.com/watch?v=4NJYWgb6dQM",
        "https://www.youtube.com/watch?v=oNXzMBA9VU4",
        "https://www.youtube.com/watch?v=kPa7bsKwL-c",
        "https://www.youtube.com/watch?v=hOT2XC9nmSU",
        "https://www.youtube.com/watch?v=qA8n3SF_Ths",
        "https://www.youtube.com/watch?v=QCIGciNcCbU",
        "https://www.youtube.com/watch?v=V09yWF2TPRM",
        "https://www.youtube.com/watch?v=f1-eY31Bw7A",
        "https://www.youtube.com/watch?v=89zwKGlc7Yw",
        "https://www.youtube.com/watch?v=m7Bc3pLyij0",
        "https://www.youtube.com/watch?v=gK8J1EDk0iA",
        "https://www.youtube.com/watch?v=_tkb95pZCeA",
        "https://www.youtube.com/watch?v=1RKqOmSkGgM",
        "https://www.youtube.com/watch?v=QMssNXBCCl0",
        "https://www.youtube.com/watch?v=WSJQcgBAyys",
        "https://www.youtube.com/watch?v=5LGUgChapj4",
        "https://www.youtube.com/watch?v=SnXkhkEvNIM",
        "https://www.youtube.com/watch?v=vu-Pf-wxqVk",
        "https://www.youtube.com/watch?v=6PcAb_8ahZE",
        "https://www.youtube.com/watch?v=mp8qmRnyF6w",
        "https://www.youtube.com/watch?v=9wNKEBWD378",
        "https://www.youtube.com/watch?v=m70w-33z6AM",
        "https://www.youtube.com/watch?v=eh31zcCFKaE",
        "https://www.youtube.com/watch?v=0aDIjhtfZqs"
    ]
    
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
                            // Pick a random URL from the array
                            if let randomURLString = easterEggURLs.randomElement(),
                               let url = URL(string: randomURLString) {
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
