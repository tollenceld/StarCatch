import SwiftUI

struct PointingReadoutSample {
    private(set) var azimuth: Int
    private(set) var elevation: Int
    private(set) var azimuthIncreasing = true
    private(set) var elevationIncreasing = true
    private(set) var lastSampleTime: TimeInterval = -.infinity

    static let minimumInterval: TimeInterval = 1.0 / 6.0

    init(azimuth: String, elevation: String) {
        self.azimuth = Self.parse(azimuth, wrapping: true)
        self.elevation = Self.parse(elevation, wrapping: false)
    }

    static func parse(_ value: String, wrapping: Bool) -> Int {
        let number = Int(value.filter { $0.isNumber || $0 == "-" || $0 == "+" }) ?? 0
        return wrapping ? (number % 360 + 360) % 360 : number
    }

    static func delta(from old: Int, to new: Int, wrapping: Bool) -> Int {
        let difference = new - old
        guard wrapping else { return difference }
        if difference > 180 { return difference - 360 }
        if difference < -180 { return difference + 360 }
        return difference
    }

    @discardableResult
    mutating func update(azimuth: String, elevation: String, at time: TimeInterval) -> Bool {
        guard time - lastSampleTime >= Self.minimumInterval - 0.000_001 else { return false }
        let az = Self.parse(azimuth, wrapping: true)
        let el = Self.parse(elevation, wrapping: false)
        guard az != self.azimuth || el != self.elevation else { return false }
        azimuthIncreasing = Self.delta(from: self.azimuth, to: az, wrapping: true) >= 0
        elevationIncreasing = el >= self.elevation
        self.azimuth = az
        self.elevation = el
        lastSampleTime = time
        return true
    }
}

/// Integer-only presentation samples are independent of the high precision pointing pipeline.
struct PointingCoordinateReadout: View {
    let azimuth: String
    let elevation: String
    let sampleDate: Date
    let reducedMotion: Bool
    @State private var sample: PointingReadoutSample

    init(azimuth: String, elevation: String, sampleDate: Date, reducedMotion: Bool) {
        self.azimuth = azimuth
        self.elevation = elevation
        self.sampleDate = sampleDate
        self.reducedMotion = reducedMotion
        _sample = State(initialValue: PointingReadoutSample(azimuth: azimuth, elevation: elevation))
    }

    var body: some View {
        HStack(spacing: 4) {
            coordinate(prefix: "AZ", number: String(format: "%03d", sample.azimuth), increasing: sample.azimuthIncreasing)
            Rectangle().fill(Palette.inkFaint.opacity(0.3)).frame(width: 0.5, height: 10)
            coordinate(prefix: "EL", number: String(format: "%+03d", sample.elevation), increasing: sample.elevationIncreasing)
        }
        .onChange(of: sampleDate) { _, date in
            var next = sample
            if next.update(azimuth: azimuth, elevation: elevation, at: date.timeIntervalSinceReferenceDate) {
                withAnimation(reducedMotion ? nil : .easeOut(duration: 0.18)) { sample = next }
            }
        }
    }

    private func coordinate(prefix: String, number: String, increasing: Bool) -> some View {
        HStack(spacing: 2) {
            Text(prefix)
            ZStack {
                Text(number)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(reducedMotion ? .identity : .numericText(countsDown: !increasing))
            }
            .frame(width: 18, height: 12)
            .clipped()
            Text("°")
        }
    }
}
