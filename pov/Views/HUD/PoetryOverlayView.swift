import SwiftUI

struct PoetryOverlayView: View {
    @ObservedObject var viewModel: PoetryViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            // --- Historical lines ---
            ForEach(Array(viewModel.poemLines.enumerated()), id: \.element.id) { index, line in
                let isLast = index == viewModel.poemLines.count - 1
                let opacity = isLast ? 0.9 : 0.7
                // 历史诗句字号
                let fontSize: CGFloat = 16
                
                Text(line.text)
                    .font(.custom("Handjet-ExtraLight", size: fontSize))
                    // 修改点 1：添加字间距
                    .kerning(fontSize * 0.12)
                    .foregroundColor(.white.opacity(opacity))
                    // 阴影保证可读性
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            
            // --- Current typing line ---
            if !viewModel.currentTypingText.isEmpty || viewModel.isTyping {
                HStack(spacing: 0) {
                    // 当前打字诗句字号
                    let typingFontSize: CGFloat = 20
                    
                    Text(viewModel.currentTypingText)
                        .font(.custom("Handjet-Light", size: typingFontSize))
                        // 修改点 2：添加 8% 的字间距
                        .kerning(typingFontSize * 0.12)
                        .foregroundColor(.white)
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
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        // 整体动画
        .animation(.easeInOut(duration: 0.3), value: viewModel.poemLines.count)
        .animation(.easeInOut(duration: 0.1), value: viewModel.currentTypingText)
    }
    
    @State private var cursorOpacity: Double = 1.0
}

// Preview (保持不变，用于预览效果)
struct PoetryOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.edgesIgnoringSafeArea(.all)
            VStack {
                Spacer()
                PoetryOverlayView(viewModel: {
                    let vm = PoetryViewModel()
                    vm.poemLines = [
                        PoemLine(text: "the universe is a verse", timestamp: Date()),
                        PoemLine(text: "memories, light as dusts", timestamp: Date())
                    ]
                    vm.currentTypingText = "flowing away in a flick"
                    vm.isTyping = true
                    return vm
                }())
                .padding(.bottom, 100)
            }
        }
    }
}
