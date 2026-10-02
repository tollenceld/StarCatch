import SwiftUI

/// A deliberately cheap launch surface: no Canvas, shader, orbit projection,
/// repeating animation, or resource-dependent visual geometry.
struct OrbitalBootView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    @State private var revealed = false

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()

            VStack(spacing: 19) {
                Text("StarCatch")
                    .font(.system(.largeTitle, design: .default, weight: .light))
                    .tracking(2.2)
                    .foregroundStyle(Palette.inkHigh)

                Rectangle()
                    .fill(Palette.signal.opacity(0.56))
                    .frame(width: 34, height: 1)
                    .scaleEffect(x: revealed ? 1 : 0.2)

                Text(L10n.text("boot.accessibility.preparing"))
                    .font(Typography.statusTag)
                    .tracking(Typography.statusTagTracking)
                    .foregroundStyle(Palette.inkMid)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
            .opacity(revealed ? 1 : 0)
            .offset(y: suppressMotion || revealed ? 0 : 7)
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.easeOut(duration: suppressMotion ? 0.14 : 0.4)) {
                revealed = true
            }
        }
    }
}
