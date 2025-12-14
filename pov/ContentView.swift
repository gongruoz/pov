import SwiftUI

// MARK: - 0. Film Grain Overlay (Static Image - High Performance)
struct FilmGrainOverlay: View {
    @State private var grainImage: UIImage?
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = grainImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blendMode(.overlay)
                        .allowsHitTesting(false)
                } else {
                    Color.clear
                }
            }
            .onAppear {
                if grainImage == nil {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let generated = generateStaticGrain(size: proxy.size)
                        DispatchQueue.main.async {
                            self.grainImage = generated
                        }
                    }
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
    
    private func generateStaticGrain(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cgContext = context.cgContext
            let intensity: Double = 0.12
            let particleCount = Int(min(size.width * size.height * 0.2, 80000))
            let particleSize: CGFloat = 0.5
            
            let whiteColor = UIColor.white.withAlphaComponent(intensity).cgColor
            let blackColor = UIColor.black.withAlphaComponent(intensity).cgColor
            
            for _ in 0..<particleCount {
                let x = Double.random(in: 0...size.width)
                let y = Double.random(in: 0...size.height)
                let rect = CGRect(x: x, y: y, width: particleSize, height: particleSize)
                
                cgContext.setFillColor(Bool.random() ? whiteColor : blackColor)
                cgContext.fill(rect)
            }
        }
    }
}

// MARK: - 1. Ambient Dust Layer
struct AmbientDustLayer: View {
    private let particleCount = 35
    
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
    @State private var scale: CGFloat = 0.3
    @State private var offsetX: CGFloat = 0.0
    @State private var offsetY: CGFloat = 0.0
    
    // Slow down movement and fade
    private let targetScale = CGFloat.random(in: 0.8...1.4)
    private let maxOpacity = Double.random(in: 0.8...1.0)
    private let duration = Double.random(in: 4.0...7.0) // Slower fade in/out
    private let floatDuration = Double.random(in: 8.0...14.0) // Slower movement
    private let delay = Double.random(in: 0.0...3.0) // Shorter delay
    
    private let baseSize: CGFloat = CGFloat.random(in: 0.5...0.8)
    private let widthRatio: CGFloat = Double.random(in: 0.8...1.2)
    private let heightRatio: CGFloat = Double.random(in: 0.8...1.2)
    
    var body: some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: baseSize * widthRatio, height: baseSize * heightRatio)
            .shadow(color: .white.opacity(1.0), radius: 1.5)
            .scaleEffect(scale)
            .rotationEffect(Angle(degrees: Double.random(in: 0...360)))
            .opacity(opacity)
            .offset(x: offsetX, y: offsetY)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(delay)) {
                    opacity = maxOpacity
                    scale = targetScale
                }
                withAnimation(.easeInOut(duration: floatDuration).repeatForever(autoreverses: true).delay(Double.random(in: 0...2.0))) {
                    offsetX = CGFloat.random(in: -50...50) // Reduced movement range slightly for slower feel
                    offsetY = CGFloat.random(in: -50...50)
                }
            }
    }
}

// MARK: - 2. Content View (Main)
struct ContentView: View {
    @StateObject var arViewModel = ARViewModel()
    @State private var showTapToast = false
    @State private var hasShownTapToast = false
    
    var body: some View {
        ZStack {
            // Camera Layer
            ARViewContainer(arManager: arViewModel.arManager)
                .edgesIgnoringSafeArea(.all)
                .overlay(
                    ZStack {
                        // 1. Texture Layers
                        FilmGrainOverlay()
                        AmbientDustLayer()
                        
                        // 2. Floating Words Layer
                        GeometryReader { geometry in
                            ZStack {
                                ForEach(arViewModel.arManager.floatingWords) { word in
                                    FloatingWordView(
                                        word: word,
                                        geometry: geometry
                                    )
                                    .onTapGesture {
                                        let isNowSelected = arViewModel.arManager.toggleWordSelection(word.id)
                                        // Only capture word when selecting, not deselecting
                                        if isNowSelected {
                                            arViewModel.poetryViewModel.captureWord(word.text)
                                        }
                                    }
                                }
                            }
                        }
                    }
                )
            
            // UI Overlay (HUD)
            VStack {
                // Top: Unified Status Indicator (Recording / Saved) + Tap Toast
                ZStack {
                    HStack {
                        if arViewModel.recorderService.isRecording {
                            StatusIndicator(state: .recording(arViewModel.recorderService.recordingDuration))
                        } else if arViewModel.showSavedToast {
                            StatusIndicator(state: .saved)
                                .transition(.opacity)
                        }
                        Spacer()
                    }
                    
                    // Tap Toast (Centered) - Shows once when first words appear
                    if showTapToast {
                        Text("tap tap :)")
                            .font(.custom("Handjet-Regular", size: 12))
                            .kerning(2.1)
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(16)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .animation(.easeInOut, value: arViewModel.recorderService.isRecording)
                .animation(.easeInOut, value: arViewModel.showSavedToast)
                
                Spacer()
                
                // Bottom: Poetry & Controls
                VStack(spacing: 20) {
                    PoetryOverlayView(viewModel: arViewModel.poetryViewModel)
                    
                    HStack {
                        Spacer()
                        RecordButtonView(recorder: arViewModel.recorderService)
                        Spacer()
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            // Show toast once when first floating words appear
            arViewModel.arManager.onFirstWordsAppeared = {
                guard !hasShownTapToast else { return }
                hasShownTapToast = true
                withAnimation(.easeIn(duration: 0.3)) {
                    showTapToast = true
                }
                // Auto hide after 5s
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showTapToast = false
                    }
                }
            }
        }
    }
}

// MARK: - 3. Floating Word View
struct FloatingWordView: View {
    let word: FloatingWord
    let geometry: GeometryProxy
    
    @State private var glowIntensity: Double = 0.5
    @State private var floatingOffset: CGFloat = 0.0
    
    var body: some View {
        // Highlighting Logic - use Handjet-Regular for selected words
        let fontSize: CGFloat = 18
        let fontName = word.isSelected ? "Handjet-Regular" : "Handjet-ExtraLight"
        let kerningValue = fontSize * 0.15
        
        Text(word.text)
            .font(.custom(fontName, size: fontSize))
            .kerning(kerningValue)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            
            // Holy Glow with breathing animation
            .shadow(color: .white, radius: 1)
            .shadow(color: .white.opacity(0.9), radius: word.isSelected ? 10 : 6)
            .shadow(color: .white.opacity(0.7), radius: word.isSelected ? 25 : 15)
            .shadow(
                color: Color.white.opacity(glowIntensity),
                radius: glowIntensity * (word.isSelected ? 70 : 55)
            )
            
            // Animations
            .scaleEffect(word.scale)
            // Opacity: selected = 1, fading out = use word.opacity with linear, normal = word.opacity
            .opacity(word.isSelected ? 1.0 : word.opacity)
            .offset(y: floatingOffset)
            .position(
                x: word.position.x * geometry.size.width,
                y: word.position.y * geometry.size.height
            )
            // Smooth transition for selection
            .animation(.easeInOut(duration: 0.3), value: word.isSelected)
            // No animation for position update to prevent lag
            .animation(nil, value: word.position)
            // Linear fade for opacity (especially important for fading out words)
            .animation(.linear(duration: 0.1), value: word.opacity)
            // Linear fade when becoming unselected (fading out)
            .animation(.linear(duration: 1.5), value: word.isFadingOut)
            
            .onAppear {
                // Breathing glow animation - continuous subtle pulse
                withAnimation(
                    .easeInOut(duration: 2.5)
                    .repeatForever(autoreverses: true)
                ) {
                    glowIntensity = 1.0
                }
                let randomDelay = Double.random(in: 0...2.0)
                withAnimation(.easeInOut(duration: Double.random(in: 4.0...6.0)).repeatForever(autoreverses: true).delay(randomDelay)) {
                    floatingOffset = CGFloat.random(in: -1.5...1.5)
                }
            }
    }
}

// MARK: - 4. Unified Status Indicator
enum StatusState {
    case recording(TimeInterval)
    case saved
}

struct StatusIndicator: View {
    let state: StatusState
    
    var body: some View {
        HStack(spacing: 6) {
            if case .recording = state {
                // Recording Dot (Cutout)
                Circle()
                    .fill(Color.black)
                    .frame(width: 10, height: 10)
                    .blendMode(.destinationOut)
            }
            
            // Text (Cutout)
            Text(statusText)
                .font(.custom("Handjet-Regular", size: 12))
                .kerning(2.1)
                .foregroundColor(.black)
                .blendMode(.destinationOut)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.7))
        .compositingGroup() // Ensures cutout applies to the white background
        .cornerRadius(16)
    }
    
    private var statusText: String {
        switch state {
        case .recording(let duration):
            return formatDuration(duration)
        case .saved:
            return "saved :)"
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
