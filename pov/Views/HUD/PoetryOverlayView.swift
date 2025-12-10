import SwiftUI

struct PoetryOverlayView: View {
    @ObservedObject var viewModel: PoetryViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            // Historical lines (at the top, oldest first)
            ForEach(Array(viewModel.poemLines.enumerated()), id: \.element.id) { index, line in
                // Calculate opacity: older lines fade out more
                let isLast = index == viewModel.poemLines.count - 1
                let opacity = isLast ? 0.9 : 0.6
                
                Text(line.text)
                    .font(.custom("PingFangSC-Light", size: 16))
                    .foregroundColor(.white.opacity(opacity))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            
            // Current typing line (at the bottom, most prominent)
            if !viewModel.currentTypingText.isEmpty || viewModel.isTyping {
                HStack(spacing: 0) {
                    Text(viewModel.currentTypingText)
                        .font(.custom("PingFangSC-Regular", size: 18))
                        .foregroundColor(.white)
                    
                    // Blinking cursor
                    if viewModel.isTyping {
                        Text("|")
                            .font(.custom("PingFangSC-Regular", size: 18))
                            .foregroundColor(.white)
                            .opacity(cursorOpacity)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorOpacity)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            // Subtle gradient background
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.4), Color.black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .animation(.easeInOut(duration: 0.3), value: viewModel.poemLines.count)
        .animation(.easeInOut(duration: 0.1), value: viewModel.currentTypingText)
    }
    
    @State private var cursorOpacity: Double = 1.0
}

// Preview
struct PoetryOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                PoetryOverlayView(viewModel: {
                    let vm = PoetryViewModel()
                    vm.poemLines = [
                        PoemLine(text: "光影在沉默中流淌", timestamp: Date()),
                        PoemLine(text: "记忆如尘埃般轻盈", timestamp: Date())
                    ]
                    vm.currentTypingText = "时间在指尖消逝"
                    vm.isTyping = true
                    return vm
                }())
                .padding(.bottom, 100)
            }
        }
    }
}

