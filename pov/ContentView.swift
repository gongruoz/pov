import SwiftUI

// MARK: - 0. Film Grain Overlay (Delicate & Visible)
// 全屏胶片噪点层：参数微调，增加一点点存在感
struct FilmGrainOverlay: View {
    // 修改 1：强度稍微提高 (0.035 -> 0.06)，让它更容易被察觉
    private let intensity: Double = 0.06
    
    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                // 保持高密度
                let particleCount = Int(min(size.width * size.height * 0.5, 150000))
                
                var whitePath = Path()
                var blackPath = Path()
                
                // 修改 2：尺寸稍微加大一点点 (0.35 -> 0.5)，保证在不同屏幕上的可见性
                let particleSize: CGFloat = 0.5
                
                for _ in 0..<particleCount {
                    let x = Double.random(in: 0...size.width)
                    let y = Double.random(in: 0...size.height)
                    let rect = CGRect(x: x, y: y, width: particleSize, height: particleSize)
                    
                    if Bool.random() {
                        whitePath.addRect(rect)
                    } else {
                        blackPath.addRect(rect)
                    }
                }
                
                context.fill(whitePath, with: .color(.white.opacity(intensity)))
                context.fill(blackPath, with: .color(.black.opacity(intensity)))
            }
        }
        // 保持 Overlay 混合模式
        .blendMode(.overlay)
        .allowsHitTesting(false)
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - 1. Independent Ambient Dust (Sparse, Tiny, Bright)
struct AmbientDustLayer: View {
    // 修改 3：数量减少 (45 -> 25)，让画面不拥挤
    private let particleCount = 25
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<particleCount, id: \.self) { _ in
                DustMote()
                    .position(
                        x: CGFloat.random(in: 0...geometry.size.width),
                        y: CGFloat.random(in: 0...geometry.size.height)
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

struct DustMote: View {
    @State private var opacity: Double = 0.0
    @State private var scale: CGFloat = Double.random(in: 0.2...0.5)
    @State private var offsetX: CGFloat = 0.0
    @State private var offsetY: CGFloat = 0.0
    
    // --- 随机化的生命周期参数 ---
    private let targetScale = CGFloat.random(in: 0.8...1.4)
    // 保持高亮度
    private let maxOpacity = Double.random(in: 0.8...1.0)
    private let duration = Double.random(in: 4.0...12.0)
    private let floatDuration = Double.random(in: 10.0...20.0)
    private let delay = Double.random(in: 0.0...10.0)
    
    // 修改 4：基础尺寸整体缩小 (1.5~3.0 -> 1.0~2.0)，变成细小的光点
    private let baseSize: CGFloat = CGFloat.random(in: 0.8...1.5)
    private let widthRatio: CGFloat = Double.random(in: 0.8...1.2)
    private let heightRatio: CGFloat = Double.random(in: 0.8...1.2)
    
    var body: some View {
        // 不规则矩形碎片
        Rectangle()
            .fill(Color.white)
            .frame(width: baseSize * widthRatio, height: baseSize * heightRatio)
            // 保持刺眼的光晕感
            .shadow(color: .white.opacity(1.0), radius: 1.5)
            .scaleEffect(scale)
            // 随机旋转
            .rotationEffect(Angle(degrees: Double.random(in: 0...360)))
            .opacity(opacity)
            // 随机漂浮位移
            .offset(x: offsetX, y: offsetY)
            .onAppear {
                // 1. 呼吸动画
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    opacity = maxOpacity
                    scale = targetScale
                }
                
                // 2. 漂浮动画
                withAnimation(
                    .easeInOut(duration: floatDuration)
                    .repeatForever(autoreverses: true)
                    .delay(Double.random(in: 0...5.0))
                ) {
                    offsetX = CGFloat.random(in: -70...70)
                    offsetY = CGFloat.random(in: -70...70)
                }
            }
    }
}

// MARK: - 2. Content View (Main)
struct ContentView: View {
    @StateObject var arViewModel = ARViewModel()
    
    var body: some View {
        ZStack {
            // Camera View
            ARViewContainer(arManager: arViewModel.arManager)
                .edgesIgnoringSafeArea(.all)
                .overlay(
                    ZStack {
                        // 1. 胶片噪点层 (最底层，细腻底纹)
                        FilmGrainOverlay()
                        
                        // 2. 环境尘埃 (稀疏、细小、明亮、漂浮)
                        AmbientDustLayer()
                        
                        // 3. 悬浮文字层
                        GeometryReader { geometry in
                            ZStack {
                                // Render Floating Words (candidates/unselected)
                                ForEach(arViewModel.arManager.floatingWords) { word in
                                    FloatingWordView(
                                        word: word,
                                        isSelected: false,
                                        geometry: geometry
                                    )
                                    .onTapGesture {
                                        arViewModel.arManager.triggerHaptic()
                                        arViewModel.arManager.toggleWordSelection(word.id)
                                    }
                                }
                                
                                // Render Kept Words (selected/anchors)
                                ForEach(arViewModel.arManager.keptWords) { word in
                                    FloatingWordView(
                                        word: word,
                                        isSelected: true,
                                        geometry: geometry
                                    )
                                    .onTapGesture {
                                        arViewModel.arManager.triggerHaptic()
                                        arViewModel.arManager.toggleWordSelection(word.id)
                                    }
                                }
                            }
                        }
                    }
                )
            
            // UI Overlay
            VStack {
                // Top: Recording indicator
                HStack {
                    if arViewModel.recorderService.isRecording {
                        RecordingIndicator(duration: arViewModel.recorderService.recordingDuration)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Spacer()
                
                // Bottom: Poetry Overlay
                PoetryOverlayView(viewModel: arViewModel.poetryViewModel)
                
                // Record Button
                HStack {
                    Spacer()
                    RecordButtonView(recorder: arViewModel.recorderService)
                    Spacer()
                }
                .padding(.bottom, 40)
            }
            
            // Toast
            if arViewModel.showSavedToast {
                SavedToast()
            }
        }
        .statusBar(hidden: true)
    }
}

// MARK: - 3. Floating Word View
struct FloatingWordView: View {
    let word: FloatingWord
    let isSelected: Bool
    let geometry: GeometryProxy
    
    // 文字光晕呼吸
    @State private var isTextGlowBreathing = false
    // 微弱浮动偏移量
    @State private var floatingOffset: CGFloat = 0.0
    
    var body: some View {
        let fontSize: CGFloat = isSelected ? 20 : 18
        let kerningValue = fontSize * 0.15
        
        Text(word.text)
            .font(.custom("Handjet-Light", size: fontSize))
            .kerning(kerningValue)
            .foregroundColor(.white)
            .padding(.horizontal, isSelected ? 12 : 8)
            .padding(.vertical, isSelected ? 6 : 4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            
            // --- 😇 天使圣光效果 (Angelic Holy Glow) ---
            
            // 层级 1：核心勾勒 (High Definition)
            // 保证文字本身在强光下依然清晰锐利
            .shadow(color: .white, radius: 1)
            
            // 层级 2：近处绒毛感 (Fuzzy/Furry)
            // 这一层制造“毛茸茸”的边缘，不透明度要高
            .shadow(color: .white.opacity(0.8), radius: 6)
            
            // 层级 3：中距离辉光 (Bloom)
            // 这一层制造光晕的主体，让文字看起来在发光
            .shadow(color: .white.opacity(0.6), radius: 15)
            
            // 层级 4：大气的呼吸光环 (Atmospheric Aura)
            // 半径极大，随呼吸闪烁，制造神圣感
            .shadow(
                // 呼吸时最亮可达 1.0 (纯白)，暗时也有 0.5
                color: Color.white.opacity(isTextGlowBreathing ? 1.0 : 0.5),
                // 半径拉得非常大 (30-50)，制造柔和的散射
                radius: isTextGlowBreathing ? 50 : 30
            )
            
            // --- 核心动画逻辑 (保持之前的 Linear & Subtle) ---
            
            .scaleEffect(word.scale)
            .opacity(word.opacity)
            .animation(.easeOut(duration: 0.2), value: word.opacity)
            .animation(.linear(duration: 0.2), value: word.scale)

            .offset(y: floatingOffset)
            
            .position(
                x: word.position.x * geometry.size.width,
                y: word.position.y * geometry.size.height
            )
            .animation(nil, value: word.position)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
            
            .onAppear {
                // 呼吸动画：稍微加快一点频率，配合圣光闪烁
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    isTextGlowBreathing.toggle()
                }
                
                let randomDelay = Double.random(in: 0...2.0)
                withAnimation(
                    .easeInOut(duration: Double.random(in: 4.0...6.0))
                    .repeatForever(autoreverses: true)
                    .delay(randomDelay)
                ) {
                    floatingOffset = CGFloat.random(in: -1.5...1.5)
                }
            }
    }
}

// MARK: - 4. Helper Views (Kerned)
struct RecordingIndicator: View {
    let duration: TimeInterval
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
            Text(formatDuration(duration))
                .font(.custom("Handjet-Regular", size: 14))
                // Kerning 15%
                .kerning(2.1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.4))
        .cornerRadius(16)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct SavedToast: View {
    var body: some View {
        GeometryReader { geo in
            VStack {
                Spacer().frame(height: geo.size.height * 0.15)
                HStack {
                    Spacer()
                    Text("saved :)")
                        .font(.custom("Handjet-Regular", size: 16))
                        // Kerning 15%
                        .kerning(2.4)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(14)
                    Spacer()
                }
                Spacer()
            }
            .transition(.opacity)
        }
    }
}
