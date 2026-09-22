import SwiftUI

/// The same shared geometry renders before and after the session is mounted.
struct OrbitalBootView: View {
    let establishment: ObservationEstablishment
    @AppStorage("grainEnabled") private var grainEnabled = true
    var body: some View {
        ObservationEstablishmentField(establishment: establishment,
            frame: ObservationSceneFrame(observation: Date(), observer: ObserverLocation.fallback,
                                         pointing: .initial, targets: []))
            .colorEffect(ShaderLibrary.grain(
                .float(Float(establishment.reducedMotion ? 0 : establishment.elapsed)),
                .float(grainEnabled ? Float(0.024 * ObservationSceneMath.ease(establishment.elapsed / 0.7)) : 0)))
            .ignoresSafeArea()
            .accessibilityLabel(L10n.text("boot.accessibility.preparing"))
    }
}
