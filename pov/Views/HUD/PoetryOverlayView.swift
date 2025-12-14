import SwiftUI

struct PoetryOverlayView: View {
    @ObservedObject var viewModel: PoetryViewModel
    @State private var glowIntensity: Double = 0.5
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // --- Historical lines (all except the most recent if it's showing as justCompleted) ---
            let historyLines = viewModel.justCompletedText.isEmpty 
                ? viewModel.poemLines 
                : viewModel.poemLines.dropLast()
            
            ForEach(Array(historyLines.enumerated()), id: \.element.id) { index, line in
                let isLast = index == historyLines.count - 1
                let opacity = isLast ? 0.7 : 0.5
                let fontSize: CGFloat = 16
                
                Text(line.text)
                    .font(.custom("Handjet-Light", size: fontSize))
                    .kerning(fontSize * 0.08)
                    .foregroundColor(.white.opacity(opacity))
                    .shadow(color: .white.opacity(0.2 * glowIntensity), radius: 4)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    .multilineTextAlignment(.leading)
                    .id(line.id)
            }
            
            // --- Just completed line (stays visible until next line starts) ---
            if !viewModel.justCompletedText.isEmpty && !viewModel.isTyping {
                let fontSize: CGFloat = viewModel.currentTypingText.isEmpty ? 18 : 16
                let opacity: Double = viewModel.currentTypingText.isEmpty ? 0.95 : 0.7
                
                Text(viewModel.justCompletedText)
                    .font(.custom("Handjet-Light", size: fontSize))
                    .kerning(fontSize * 0.08)
                    .foregroundColor(.white.opacity(opacity))
                    .shadow(color: .white.opacity(0.4 * glowIntensity), radius: 5)
                    .shadow(color: .white.opacity(0.2 * glowIntensity), radius: 10)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    .multilineTextAlignment(.leading)
                    .id("just-completed")
                    .transition(.opacity)
            }
            
            // --- Current typing line ---
            if !viewModel.currentTypingText.isEmpty || viewModel.isTyping {
                HStack(spacing: 0) {
                    let typingFontSize: CGFloat = 20
                    
                    Text(viewModel.currentTypingText)
                        .font(.custom("Handjet-Light", size: typingFontSize))
                        .kerning(typingFontSize * 0.08)
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.5 * glowIntensity), radius: 6)
                        .shadow(color: .white.opacity(0.3 * glowIntensity), radius: 12)
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    
                    // Blinking cursor
                    if viewModel.isTyping {
                        Text("|")
                            .font(.custom("Handjet-Light", size: typingFontSize))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                            .opacity(cursorOpacity)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorOpacity)
                    }
                }
                .id("typing-line")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        // Smooth linear transitions
        .animation(.linear(duration: 0.5), value: viewModel.poemLines.count)
        .animation(.linear(duration: 0.3), value: viewModel.justCompletedText)
        .animation(.easeInOut(duration: 0.05), value: viewModel.currentTypingText)
        .onAppear {
            withAnimation {
                cursorOpacity = 0.0
            }
            withAnimation(
                .easeInOut(duration: 2.5)
                .repeatForever(autoreverses: true)
            ) {
                glowIntensity = 1.0
            }
        }
    }
    
    @State private var cursorOpacity: Double = 1.0
}
