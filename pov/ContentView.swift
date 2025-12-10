import SwiftUI

struct ContentView: View {
    @StateObject var arViewModel = ARViewModel()
    
    // Haptic generators - prepared for immediate response
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        ZStack {
            // Camera View
            ARViewContainer(arManager: arViewModel.arManager)
                .edgesIgnoringSafeArea(.all)
                .overlay(
                    // Floating Words Overlay
                    GeometryReader { geometry in
                        ZStack {
                            // Render Floating Words
                            ForEach(arViewModel.arManager.floatingWords) { word in
                                Text(word.text)
                                    .font(.system(size: 18, weight: .semibold, design: .serif))
                                    .foregroundColor(.white)
                                    .scaleEffect(word.scale)
                                    .opacity(word.opacity)
                                    .position(
                                        x: word.position.x * geometry.size.width,
                                        y: word.position.y * geometry.size.height
                                    )
                                    .animation(.linear(duration: 0.05), value: word.position)
                                    .onTapGesture {
                                        lightHaptic.impactOccurred()
                                        arViewModel.arManager.toggleWordSelection(word.id)
                                    }
                            }
                            
                            // Render Kept Words (Selected)
                            ForEach(arViewModel.arManager.keptWords) { word in
                                Text(word.text)
                                    .font(.system(size: 20, weight: .bold, design: .serif))
                                    .foregroundColor(.white)
                                    .position(
                                        x: word.position.x * geometry.size.width,
                                        y: word.position.y * geometry.size.height
                                    )
                                    .onTapGesture {
                                        lightHaptic.impactOccurred()
                                        arViewModel.arManager.toggleWordSelection(word.id)
                                    }
                            }
                        }
                    }
                )
            
            // UI Overlay (always visible; NOT in video because video is camera-based)
            VStack {
                // Top: Recording indicator
                HStack {
                    if arViewModel.recorderService.isRecording {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                            Text(formatDuration(arViewModel.recorderService.recordingDuration))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(16)
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
            
            // Toast: video saved (at 30% from top)
            if arViewModel.showSavedToast {
                GeometryReader { geo in
                    VStack {
                        Spacer().frame(height: geo.size.height * 0.3)
                        HStack {
                            Spacer()
                            Text("The video has been saved to your album")
                                .font(.system(size: 14, weight: .semibold))
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
        .statusBar(hidden: true)
        .onAppear {
            // Prepare haptic for immediate response
            lightHaptic.prepare()
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
