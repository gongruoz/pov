import SwiftUI

struct RecordButtonView: View {
    @ObservedObject var recorder: RecorderService
    
    var body: some View {
        VStack(spacing: 8) {
            // Record button
            Button(action: {
                if recorder.isRecording {
                    recorder.stopRecording()
                } else {
                    recorder.startRecording()
                }
            }) {
                ZStack {
                    // 1. 外圈 (保持不变)
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1.6)
                        .frame(width: 64, height: 64)
                    
                    // 2. 内部图标 (Start 和 Stop 都用 view 图标)
                    Image("view")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        // 可选：录制时稍微缩小一点点，增加一种"按下/工作中"的视觉反馈
                        // 如果你希望完全纹丝不动，可以删掉下面这行 .scaleEffect
                        .scaleEffect(recorder.isRecording ? 0.95 : 1.0)
                }
            }
            // 按钮整体的动画效果
            .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
        }
    }
    
}

struct RecordButtonView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            RecordButtonView(recorder: RecorderService())
        }
    }
}
