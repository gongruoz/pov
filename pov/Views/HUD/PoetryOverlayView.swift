import SwiftUI

struct PoetryOverlayView: View {
    @ObservedObject var viewModel: PoetryViewModel
    @State private var glowIntensity: Double = 0.5
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // --- Historical lines (excluding the just-completed one) ---
            let historyLines = getHistoryLines()
            
            ForEach(Array(historyLines.enumerated()), id: \.element.id) { index, line in
                let recency = Double(historyLines.count - index) / Double(max(historyLines.count, 1))
                let opacity = 0.4 + (recency * 0.3) // Older = dimmer (0.4-0.7)
                
                Text(line.text)
                    .font(.custom("Handjet-Light", size: 16))
                    .kerning(16 * 0.08)
                    .foregroundColor(.white.opacity(opacity))
                    // White halo like floating words (subtle for history)
                    .shadow(color: .white.opacity(0.3), radius: 2)
                    .shadow(color: .white.opacity(0.15 * glowIntensity), radius: 8)
                    .shadow(color: .white.opacity(0.1 * glowIntensity), radius: 15)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    .multilineTextAlignment(.leading)
                    .id(line.id)
            }
            
            // --- Just completed line (stays prominent until next line starts) ---
            if !viewModel.justCompletedText.isEmpty {
                Text(viewModel.justCompletedText)
                    .font(.custom("Handjet-Light", size: 18))
                    .kerning(18 * 0.08)
                    .foregroundColor(.white.opacity(0.95))
                    // White halo like floating words (bright for just completed)
                    .shadow(color: .white, radius: 1)
                    .shadow(color: .white.opacity(0.7), radius: 6)
                    .shadow(color: .white.opacity(0.5 * glowIntensity), radius: 15)
                    .shadow(color: .white.opacity(0.3 * glowIntensity), radius: 25)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    .multilineTextAlignment(.leading)
                    .id("just-completed-\(viewModel.justCompletedText)")
            }
            
            // --- Current typing line ---
            if viewModel.isTyping || !viewModel.currentTypingText.isEmpty {
                HStack(spacing: 0) {
                    Text(viewModel.currentTypingText)
                        .font(.custom("Handjet-Light", size: 20))
                        .kerning(20 * 0.08)
                        .foregroundColor(.white)
                        // White halo like floating words (brightest for typing)
                        .shadow(color: .white, radius: 1)
                        .shadow(color: .white.opacity(0.9), radius: 8)
                        .shadow(color: .white.opacity(0.6 * glowIntensity), radius: 20)
                        .shadow(color: .white.opacity(0.4 * glowIntensity), radius: 35)
                        .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    
                    if viewModel.isTyping {
                        Text("|")
                            .font(.custom("Handjet-Light", size: 20))
                            .foregroundColor(.white)
                            .shadow(color: .white.opacity(0.8), radius: 4)
                            .opacity(cursorOpacity)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorOpacity)
                    }
                }
                .id("typing-line")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .animation(.linear(duration: 0.8), value: viewModel.justCompletedText)
        .animation(.linear(duration: 0.6), value: viewModel.poemLines.count)
        .animation(nil, value: viewModel.currentTypingText) // No animation for typing (instant)
        .onAppear {
            withAnimation { cursorOpacity = 0.0 }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowIntensity = 1.0
            }
        }
    }
    
    private func getHistoryLines() -> [PoemLine] {
        // If we have a justCompleted line showing, exclude the last poemLine (it's the same)
        if !viewModel.justCompletedText.isEmpty && !viewModel.poemLines.isEmpty {
            return Array(viewModel.poemLines.dropLast())
        }
        return viewModel.poemLines
    }
    
    @State private var cursorOpacity: Double = 1.0
}


