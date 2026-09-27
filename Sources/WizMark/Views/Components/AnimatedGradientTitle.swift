import SwiftUI

struct AnimatedGradientTitle: View {

    @State private var offset: CGFloat = -200

    var body: some View {
        Text("WizMark")
            .font(.custom("BlackOpsOne-Regular", size: 22))
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.blue, .yellow, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 3)
                    .offset(x: offset)
                }
                .mask {
                    Text("WizMark")
                        .font(.custom("BlackOpsOne-Regular", size: 22))
                }
            }
            .onAppear {
                withAnimation(
                    .linear(duration: 2)
                    .repeatForever(autoreverses: true)
                ) {
                    offset = 0
                }
            }
    }
}
