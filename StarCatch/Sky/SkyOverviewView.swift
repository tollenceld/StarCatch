import SatelliteKit
import SwiftUI
import simd

/// 沉浸式三维地球与轨道场。所有点位来自与主视野相同的 ECI 传播帧；
/// 地球、观察者、地表可见区域和轨道目标共享同一套旋转与缩放。
struct SkyOverviewView: View {
    nonisolated private static let earthDisplayRadius: Double = 0.54
    nonisolated private static let maximumOrbitDisplayRadius: Double = 0.86
    /// Natural Earth 1:110m 海岸线经过约 2° 视觉简化后的坐标。
    /// 每条数组按 `[纬度, 经度, …]` 存储，避免运行时解析地图资源。
    nonisolated private static let coastlineSamples: [[Float]] = [
        [-78.60, -163.71, -79.50, -159.21, -78.60, -163.71],
        [53.87, -6.20, 51.82, -9.98, 53.87, -6.20],
        [-2.60, 141.00, -10.58, 150.69, -8.41, 137.61, -5.39, 137.93, -0.94, 130.52, -2.60, 141.00],
        [4.53, 114.20, 5.41, 119.18, -4.01, 116.15, -0.46, 109.09, 4.53, 114.20],
        [74.98, -93.61, 74.93, -96.82, 74.98, -93.61],
        [77.52, -93.84, 77.83, -96.44, 77.52, -93.84],
        [78.77, -96.75, 78.77, -96.75],
        [74.39, -88.15, 76.75, -97.12, 74.92, -79.83, 74.39, -88.15],
        [78.15, -111.26, 77.73, -113.53, 78.15, -111.26],
        [78.80, -110.96, 78.80, -110.96],
        [18.51, -66.28, 18.51, -66.28],
        [18.49, -77.57, 18.49, -77.57],
        [23.19, -82.27, 20.28, -74.18, 21.90, -84.97, 23.19, -82.27],
        [51.32, -55.60, 46.66, -53.07, 47.60, -59.27, 51.32, -55.60],
        [65.11, -83.88, 63.73, -80.10, 63.54, -87.22, 65.11, -83.88],
        [72.35, -78.77, 66.86, -61.85, 66.26, -68.02, 63.39, -64.67, 62.33, -68.88, 64.57, -78.56, 68.07, -73.31, 72.24, -90.21, 72.35, -78.77],
        [74.13, -94.50, 73.86, -90.51, 72.06, -95.41, 74.13, -94.50],
        [72.71, -100.44, 72.56, -96.54, 72.48, -102.48, 72.71, -100.44],
        [75.85, -107.82, 75.48, -105.70, 75.22, -117.71, 75.85, -107.82],
        [76.12, -122.85, 77.65, -116.20, 76.12, -122.85],
        [74.45, -121.54, 73.48, -115.51, 71.87, -125.93, 74.45, -121.54],
        [60.38, -166.47, 60.38, -166.47],
        [57.97, -153.23, 57.97, -153.23],
        [54.04, -132.71, 52.18, -131.18, 54.04, -132.71],
        [49.95, -125.42, 48.51, -123.51, 50.54, -128.44, 49.95, -125.42],
        [63.78, -171.73, 63.30, -168.69, 63.78, -171.73],
        [79.30, -105.49, 77.91, -99.67, 79.30, -105.49],
        [35.39, 32.95, 35.39, 32.95],
        [35.30, 26.29, 35.28, 23.51, 35.30, 26.29],
        [-12.47, 49.54, -25.60, 45.41, -17.41, 43.96, -12.47, 49.54],
        [-15.89, 167.22, -15.89, 167.22],
        [-15.67, 166.79, -15.67, 166.79],
        [-6.90, 134.21, -6.90, 134.21],
        [-78.05, -48.66, -80.03, -43.33, -80.63, -54.16, -78.05, -48.66],
        [-80.26, -66.29, -80.04, -59.57, -80.26, -66.29],
        [-71.27, -73.92, -68.88, -70.25, -71.41, -68.33, -71.27, -73.92],
        [-71.89, -102.33, -72.52, -96.20, -71.89, -102.33],
        [-73.66, -122.62, -73.48, -118.72, -73.66, -122.62],
        [-73.46, -127.28, -73.87, -124.03, -73.46, -127.28],
        [-21.08, 165.78, -20.11, 164.03, -21.08, 165.78],
        [-3.66, 152.64, -2.74, 150.66, -3.66, 152.64],
        [-5.84, 151.30, -5.75, 148.32, -5.84, 151.30],
        [-10.48, 162.12, -10.48, 162.12],
        [-9.60, 161.68, -9.60, 161.68],
        [-9.87, 160.85, -9.87, 160.85],
        [-8.02, 159.64, -8.02, 159.64],
        [-7.02, 157.14, -7.02, 157.14],
        [-5.34, 154.76, -5.34, 154.76],
        [-40.07, 176.89, -41.28, 174.65, -34.53, 172.64, -37.70, 178.52, -40.07, 176.89],
        [-43.56, 169.67, -41.35, 174.25, -46.22, 166.68, -43.56, 169.67],
        [-40.81, 147.69, -43.55, 146.05, -40.70, 144.74, -40.81, 147.69],
        [-32.22, 126.15, -34.20, 115.03, -22.48, 113.74, -11.13, 132.36, -11.86, 136.49, -15.00, 135.50, -17.71, 140.22, -10.67, 142.52, -28.11, 153.57, -37.43, 150.00, -39.04, 146.32, -38.02, 140.64, -35.26, 136.83, -32.90, 137.81, -34.89, 135.99, -31.50, 131.33, -32.22, 126.15],
        [7.52, 81.79, 5.97, 80.35, 9.82, 80.15, 7.52, 81.79],
        [-2.80, 129.37, -2.80, 129.37],
        [-3.79, 126.87, -3.79, 126.87],
        [2.17, 127.93, -0.90, 128.10, 2.17, 127.93],
        [0.88, 122.93, 1.42, 125.24, -0.52, 120.04, -0.62, 123.34, -5.34, 123.16, -2.63, 120.97, -5.67, 119.80, 0.15, 119.83, 0.88, 122.93],
        [-10.26, 120.30, -10.26, 120.30],
        [-8.54, 121.34, -8.54, 121.34],
        [-8.36, 118.26, -8.36, 118.26],
        [-6.42, 108.49, -8.37, 115.71, -6.85, 105.37, -6.42, 108.49],
        [-1.08, 104.37, -5.85, 105.82, 5.48, 95.29, -1.08, 104.37],
        [12.70, 120.83, 12.70, 120.83],
        [9.98, 122.59, 9.98, 122.59],
        [8.41, 126.38, 5.58, 125.40, 7.19, 121.92, 8.41, 126.38],
        [18.20, 109.48, 20.08, 110.79, 18.20, 109.48],
        [24.39, 121.78, 21.97, 120.75, 24.39, 121.78],
        [39.18, 141.88, 35.14, 140.25, 33.89, 130.99, 31.42, 130.20, 41.20, 140.31, 39.18, 141.88],
        [43.96, 144.61, 41.57, 139.96, 45.55, 141.97, 43.96, 144.61],
        [40.90, 8.71, 40.90, 8.71],
        [42.63, 8.75, 42.63, 8.75],
        [56.11, 12.37, 56.11, 12.37],
        [58.55, -4.21, 51.29, 1.45, 50.16, -5.78, 51.43, -3.41, 56.79, -6.15, 58.55, -4.21],
        [66.46, -14.51, 63.50, -18.66, 65.61, -24.33, 66.46, -14.51],
        [53.70, 142.91, 48.98, 144.65, 45.97, 142.09, 53.70, 142.91],
        [9.32, 118.50, 11.37, 119.51, 9.32, 118.50],
        [18.22, 122.34, 12.54, 124.08, 15.41, 119.92, 18.22, 122.34],
        [11.42, 122.04, 11.42, 122.04],
        [12.16, 125.50, 10.13, 124.80, 12.16, 125.50],
        [8.67, -77.35, 12.44, -71.75, 9.07, -71.70, 12.16, -69.94, 10.72, -61.88, 4.12, -51.30, -0.08, -50.39, -7.34, -34.73, -21.94, -40.94, -24.89, -47.65, -34.40, -53.81, -33.91, -58.43, -38.18, -57.75, -41.06, -65.12, -52.35, -68.15, -52.26, -74.95],
        [7.22, -77.88, -6.14, -81.25, -19.76, -70.16, -52.26, -74.95],
        [-52.84, -74.66, -54.70, -65.05, -52.84, -74.66],
        [80.59, 44.85, 80.70, 51.52, 80.59, 44.85],
        [73.75, 53.51, 76.54, 68.85, 74.31, 58.48, 72.37, 55.42, 70.72, 57.54, 71.47, 51.60, 73.75, 53.51],
        [80.06, 27.41, 80.32, 17.37, 80.06, 27.41],
        [77.85, 24.72, 77.68, 20.73, 77.85, 24.72],
        [79.67, 15.14, 78.96, 21.54, 76.77, 15.91, 79.65, 10.44, 79.67, 15.14],
        [7.22, -77.88, 18.29, -103.50, 31.80, -114.78, 23.19, -109.43, 24.74, -112.18, 40.31, -124.40, 49.00, -122.84, 58.12, -134.08, 59.16, -151.72, 61.28, -150.62, 54.40, -164.79, 58.92, -157.04, 60.51, -165.35, 64.79, -160.78, 65.67, -168.11, 66.12, -161.68, 68.36, -166.76, 71.36, -156.58, 67.38, -108.88, 67.29, -96.13, 71.92, -95.21, 67.20, -87.35, 69.66, -82.62, 67.11, -81.39, 58.95, -94.68, 55.15, -82.27, 51.21, -79.91, 56.53, -76.54, 62.32, -78.11, 58.21, -67.65, 60.34, -64.58, 52.15, -55.68, 46.82, -71.10, 49.23, -65.06, 46.24, -64.47, 45.92, -59.80, 45.14, -67.14, 39.15, -76.35, 35.55, -75.73, 31.44, -81.34, 25.21, -80.38, 30.40, -86.40, 27.38, -97.37, 18.83, -95.90, 21.54, -87.05, 15.89, -88.93, 15.27, -83.41, 9.57, -82.55],
        [9.57, -82.55, 8.67, -77.35],
        [19.71, -71.71, 18.61, -68.32, 18.34, -74.46, 19.71, -71.71],
        [38.14, 14.76, 37.61, 12.43, 38.14, 14.76],
        [44.66, 37.54, 43.43, 39.96],
        [33.46, 132.37, 33.81, 134.77, 33.46, 132.37],
        [19.10, -16.26, 26.25, -14.44, 35.76, -5.93, 37.35, 9.51, 33.79, 10.34, 30.27, 19.09, 32.84, 21.54, 30.97, 33.77, 36.65, 36.16, 36.66, 27.64, 39.46, 26.17, 41.54, 41.55, 45.24, 36.68, 47.26, 39.12, 44.36, 33.88, 46.58, 30.75, 41.05, 28.81, 40.26, 22.63, 36.41, 22.49, 45.74, 13.14, 40.17, 18.48, 37.99, 16.10, 44.37, 8.89, 43.08, 3.10, 36.67, -2.15, 36.87, -8.90, 43.03, -9.39, 44.02, -1.38, 48.68, -4.59, 53.53, 8.12, 57.11, 8.54, 54.01, 10.94, 54.43, 19.66, 59.19, 23.34, 60.03, 29.12, 60.72, 21.32, 66.01, 23.90, 62.75, 17.85, 56.10, 15.88, 58.59, 5.67, 61.97, 4.99, 69.82, 19.18, 71.19, 28.17, 67.46, 41.06, 66.63, 33.18, 63.85, 37.01, 66.07, 43.95, 68.57, 43.45, 68.09, 68.51, 71.03, 66.69, 73.04, 69.94, 72.22, 72.80, 66.17, 72.42, 72.83, 74.66, 71.75, 81.50, 73.65, 80.51, 77.70, 104.35, 75.85, 114.13, 74.18, 109.40, 73.57, 126.98, 70.79, 131.29, 72.85, 140.47, 68.96, 180.00],
        [64.98, 180.00, 64.61, 177.41, 62.30, 179.23, 59.87, 163.54, 51.01, 156.79, 56.77, 155.91, 62.55, 164.47, 59.04, 142.20, 54.73, 135.13, 52.24, 141.38, 46.31, 138.22, 39.76, 127.53, 35.08, 129.09, 34.39, 126.49, 39.55, 125.32, 38.90, 121.05, 40.95, 121.64, 39.20, 118.04, 37.45, 122.36, 34.91, 119.15, 28.23, 121.68, 22.78, 115.89, 19.75, 105.88, 13.43, 109.34, 8.60, 105.16, 13.41, 100.10, 9.24, 99.22, 1.29, 104.23, 22.77, 91.42, 15.90, 80.32, 7.97, 77.54, 21.36, 72.63, 25.43, 66.37, 29.98, 47.97, 24.02, 51.79, 26.40, 56.36, 22.31, 59.81, 17.23, 55.27, 12.64, 43.48, 29.85, 32.42, 11.74, 42.72, 10.64, 51.05, -4.68, 39.20, -16.10, 40.09, -33.94, 25.78, -34.14, 18.38, -27.09, 15.21, 3.73, 9.40, 6.27, 4.33, 4.83, -9.00, 12.17, -16.61, 19.10, -16.26],
        [68.20, -177.55, 68.96, -180.00],
        [-16.07, -180.00, -16.56, -180.00],
        [-8.43, 125.95, -10.24, 123.46, -8.43, 125.95],
        [-84.71, -180.00, -85.04, -143.11, -83.69, -153.59, -81.10, -156.84, -80.34, -146.42, -76.89, -158.37, -75.20, -144.91, -73.01, -68.94, -66.88, -67.25, -63.27, -57.81, -67.95, -65.67, -73.70, -60.83, -76.71, -77.24, -77.91, -73.66, -79.18, -78.02, -83.22, -58.22, -80.34, -28.55, -78.34, -35.78, -70.93, -6.87, -69.78, 38.65, -65.82, 54.53, -67.93, 68.89, -72.26, 69.87, -66.21, 87.99, -65.31, 135.07, -71.70, 171.21, -76.24, 163.57, -78.75, 167.00, -80.95, 159.79, -84.71, 180.00],
        [68.96, -180.00, 65.98, -169.90, 64.98, -180.00],
        [71.52, -180.00, 71.27, -177.58, 70.83, -180.00],
        [70.83, 180.00, 71.52, 180.00],
        [-16.56, 180.00, -16.07, 180.00],
        [-51.85, -61.20, -51.55, -57.75, -51.85, -61.20],
        [-48.62, 68.94, -48.62, 68.94],
        [-17.50, 178.13, -17.50, 178.13],
        [10.76, -61.68, 10.76, -61.68],
        [20.08, -155.40, 20.08, -155.40],
        [20.76, -156.00, 20.76, -156.00],
        [21.18, -156.76, 21.18, -156.76],
        [21.72, -158.03, 21.72, -158.03],
        [22.21, -159.37, 22.21, -159.37],
        [25.21, -78.19, 25.21, -78.19],
        [26.79, -78.98, 26.79, -78.98],
        [27.04, -77.79, 27.04, -77.79],
        [47.04, -64.01, 46.44, -62.01, 47.04, -64.01],
        [44.61, 46.68, 46.85, 53.04, 44.61, 50.31, 40.95, 54.74, 36.97, 53.83, 37.58, 49.20, 40.26, 50.39, 44.61, 46.68],
        [49.87, -64.52, 49.11, -61.81, 49.87, -64.52],
        [62.09, -80.32, 62.09, -80.32],
        [62.45, -83.99, 62.90, -81.88, 62.45, -83.99],
        [67.44, -75.22, 67.59, -77.24, 67.44, -75.22],
        [69.68, -96.56, 69.40, -99.80, 69.68, -96.56],
        [73.08, -106.52, 69.58, -101.09, 68.54, -113.31, 69.96, -117.34, 70.37, -112.42, 71.56, -119.40, 73.08, -106.52],
        [72.80, -79.78, 72.83, -76.25, 72.80, -79.78],
        [73.37, 139.86, 73.21, 143.60, 73.37, 139.86],
        [75.35, 148.22, 75.08, 150.73, 75.17, 146.12, 75.35, 148.22],
        [76.14, 138.83, 75.56, 145.09, 75.26, 136.97, 76.14, 138.83],
        [76.59, -98.58, 75.56, -102.50, 76.59, -98.58],
        [79.28, 102.84, 78.71, 105.37, 77.92, 99.44, 79.28, 102.84],
        [81.02, 93.78, 79.78, 100.19, 80.34, 91.18, 81.02, 93.78],
        [80.60, -96.02, 79.34, -85.81, 80.60, -96.02],
        [81.89, -91.59, 82.63, -61.85, 76.18, -80.56, 76.47, -89.49, 77.54, -84.98, 80.25, -86.93, 80.46, -81.85, 81.89, -91.59],
        [82.63, -46.76, 81.29, -12.21, 80.18, -20.05, 80.13, -17.73, 76.63, -21.68, 74.30, -19.37, 70.23, -26.36, 70.13, -22.35, 65.46, -39.81, 60.10, -43.38, 63.63, -51.63, 67.19, -53.97, 69.93, -50.87, 69.61, -54.68, 70.57, -51.39, 75.52, -58.59, 78.04, -73.30, 81.77, -62.65, 81.66, -44.52, 82.63, -46.76],
        [73.60, -106.60, 73.42, -104.50, 73.60, -106.60],
    ]

    @ObservedObject var session: SkySession
    @ObservedObject var clock: SkyClock

    let observation: Date
    let frameTime: TimeInterval
    let motionTime: TimeInterval
    let trails: TrailStore
    let focusedObjectId: String?
    @Binding var scaleModified: Bool
    let resetRequest: Int
    let transitionProgress: Double
    let entryPointing: Pointing?
    let transitionMotionEnabled: Bool
    let interactive: Bool
    var onScaleReturnChanged: (Double) -> Void = { _ in }
    var onScaleReturnEnded: (Bool) -> Void = { _ in }

    @State private var yaw: Double = -0.42
    @State private var settledYaw: Double = -0.42
    @State private var pitch: Double = 0.28
    @State private var settledPitch: Double = 0.28
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var scaleGestureActive = false
    @State private var scaleReturnProgress: Double = 0
    @State private var orbitGestureActive = false
    @State private var spatialInertiaActive = false
    @State private var spatialMotionEvent = 0
    @State private var scaleGestureSample: CGFloat = 1
    @State private var scaleGestureSampleDate = Date.distantPast
    @State private var scaleLogarithmicVelocity: Double = 0
    @State private var renderDetailsSettled = true
    @State private var renderRecoveryEvent = 0
    @State private var observerLabelEmphasized = false
    @State private var observerLabelEvent = 0
    @State private var transientGestureHintVisible = true
    @AppStorage("overviewGestureHintsSeen") private var gestureHintsSeen = false

    private struct RenderSample {
        let object: CatalogObject
        let ephemeris: Ephemeris
        let projected: Projected3D
    }

    struct Projected3D {
        let point: CGPoint
        /// 大于零表示朝向观察者。
        let depth: Double
    }

    private var controlHandoff: Double {
        ObservationScale.eased((transitionProgress - 0.18) / 0.72)
    }

    private var surfaceDetailPresence: Double {
        ObservationScale.eased((transitionProgress - 0.36) / 0.5)
    }

    /// 转场初段仍会对设备姿态产生很轻的响应；接近全局尺度后固定到进入时的
    /// 观察方向，并把控制权完整交给触摸旋转。
    private var renderedYaw: Double {
        guard let entryPointing else { return yaw }
        let delta = Self.shortestAngle(
            from: entryPointing.azimuth,
            to: session.pointing.azimuth
        )
        return yaw - delta * 0.34 * (1 - controlHandoff)
    }

    private var renderedPitch: Double {
        guard let entryPointing else { return pitch }
        let delta = session.pointing.elevation - entryPointing.elevation
        return Self.clampedPitch(pitch + delta * 0.28 * (1 - controlHandoff))
    }

    private var renderingSimplified: Bool {
        orbitGestureActive
            || scaleGestureActive
            || spatialInertiaActive
            || !renderDetailsSettled
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas(
                opaque: true,
                colorMode: .linear,
                rendersAsynchronously: false
            ) { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Palette.voidBlack)
                )

                let baseGeometry = Self.globeGeometry(in: size)
                let p = min(1, max(0, transitionProgress))
                let geometry = renderedGeometry(in: size)
                drawAmbientSpace(context, geometry: geometry)

                let focusedObject = focusedObjectId.flatMap { session.catalog.objectsByID[$0] }
                let focusedFamily = focusedObject?.family
                let live = clock.isLive
                let sampleDivisor = session.overviewObjects.count < 1_400
                    ? 1
                    : Self.renderSampleDivisor(
                        zoom: zoom,
                        interactionActive: renderingSimplified
                    )

                var samples: [RenderSample] = []
                samples.reserveCapacity(session.overviewObjects.count / sampleDivisor + 1)
                @MainActor func appendSample(_ object: CatalogObject) {
                    guard let ephemeris = session.ephemeris.cachedEphemeris(
                        object.id,
                        at: observation,
                        live: live
                    ), let projected = Self.project(
                        orbitalPosition: ephemeris.orbitalPosition,
                        center: geometry.center,
                        radius: geometry.radius,
                        yaw: renderedYaw,
                        pitch: renderedPitch,
                        zoom: zoom
                    ) else { return }
                    samples.append(RenderSample(
                        object: object,
                        ephemeris: ephemeris,
                        projected: projected
                    ))
                }
                for object in session.overviewObjects {
                    guard object.id == focusedObjectId
                            || object.noradId.isMultiple(of: sampleDivisor)
                    else { continue }
                    appendSample(object)
                }
                if let focusedObject,
                   !session.overviewObjects.contains(where: { $0.id == focusedObject.id }) {
                    appendSample(focusedObject)
                }

                context.drawLayer { field in
                    if !renderingSimplified {
                        drawOrbitGuides(field, geometry: geometry)
                    }
                    drawSpatialTrails(
                        field,
                        geometry: geometry,
                        front: false,
                        simplified: renderingSimplified
                    )
                    drawField(
                        field,
                        samples: samples,
                        front: false,
                        focusedFamily: focusedFamily,
                        simplified: renderingSimplified
                    )
                    drawEarth(
                        field,
                        geometry: geometry,
                        simplified: renderingSimplified
                    )
                    drawSpatialTrails(
                        field,
                        geometry: geometry,
                        front: true,
                        simplified: renderingSimplified
                    )
                    drawField(
                        field,
                        samples: samples,
                        front: true,
                        focusedFamily: focusedFamily,
                        simplified: renderingSimplified
                    )
                    drawFocusedObject(field, samples: samples)
                    drawObserver(
                        field,
                        geometry: geometry,
                        simplified: renderingSimplified
                    )
                }

                drawLegend(
                    context,
                    geometry: baseGeometry,
                    displayed: samples.count,
                    total: session.visibleObjects.count,
                    presence: ObservationScale.eased((p - 0.66) / 0.28),
                    showGestureHint: interactive
                        && !gestureHintsSeen
                        && transientGestureHintVisible
                        && !renderingSimplified
                )
            }
            .contentShape(Rectangle())
            .gesture(orbitGesture)
            .simultaneousGesture(magnificationGesture)
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        revealObserverLabelIfNeeded(
                            at: value.location,
                            in: proxy.size
                        )
                    }
            )
            .onTapGesture(count: 2) {
                markGestureHintsSeen()
                resetView()
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--previewOverviewTransform") {
                    yaw = 0.72
                    settledYaw = yaw
                    pitch = -0.36
                    settledPitch = pitch
                    zoom = 1.26
                    settledZoom = zoom
                }
                #endif
                scaleModified = abs(zoom - 1) > 0.015
            }
            .task(id: gestureHintsSeen) {
                guard !gestureHintsSeen else {
                    transientGestureHintVisible = false
                    return
                }
                transientGestureHintVisible = true
                try? await Task.sleep(for: .seconds(3.4))
                guard !Task.isCancelled, !gestureHintsSeen else { return }
                withAnimation(.easeOut(duration: 0.42)) {
                    transientGestureHintVisible = false
                }
            }
            .onChange(of: resetRequest) { _, _ in resetView() }
            .onDisappear {
                cancelSpatialInertia()
                scaleModified = false
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("交互式三维地球轨道星图，显示观察者位置、卫星与实时轨迹")
        .accessibilityHint(interactive ? "单指上下左右旋转，双指缩放，双击复位" : "拖动时间轴查看轨道变化")
        .accessibilityAction(named: "复位星图") { resetView() }
    }

    // MARK: - 交互

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard interactive, !scaleGestureActive else { return }
                if !orbitGestureActive {
                    cancelSpatialInertia()
                    orbitGestureActive = true
                    beginRenderInteraction()
                    cancelObserverLabelEmphasis()
                    markGestureHintsSeen()
                }
                yaw = settledYaw + Double(value.translation.width) * 0.0072
                pitch = Self.clampedPitch(
                    settledPitch - Double(value.translation.height) * 0.0062
                )
            }
            .onEnded { value in
                guard interactive, !scaleGestureActive else { return }
                orbitGestureActive = false
                startOrbitInertia(
                    yawVelocity: SpatialMotion.limitedAngularVelocity(
                        pointsPerSecond: value.velocity.width,
                        sensitivity: 0.0019
                    ),
                    pitchVelocity: SpatialMotion.limitedAngularVelocity(
                        pointsPerSecond: -value.velocity.height,
                        sensitivity: 0.00165
                    )
                )
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard interactive else { return }
                if !scaleGestureActive {
                    cancelSpatialInertia()
                    beginRenderInteraction()
                    cancelObserverLabelEmphasis()
                    markGestureHintsSeen()
                    scaleGestureSample = value
                    scaleGestureSampleDate = Date()
                    scaleLogarithmicVelocity = 0
                } else {
                    let now = Date()
                    let deltaTime = now.timeIntervalSince(scaleGestureSampleDate)
                    if deltaTime > 0.008,
                       scaleGestureSample > 0,
                       value > 0 {
                        let instantaneous = log(
                            Double(value / scaleGestureSample)
                        ) / deltaTime
                        scaleLogarithmicVelocity =
                            scaleLogarithmicVelocity * 0.62
                            + instantaneous * 0.38
                        scaleGestureSample = value
                        scaleGestureSampleDate = now
                    }
                }
                scaleGestureActive = true
                let rawZoom = settledZoom * value
                zoom = min(
                    ObservationScale.maximumOverviewZoom,
                    max(0.78, rawZoom)
                )
                scaleModified = abs(zoom - 1) > 0.015
                scaleReturnProgress = ObservationScale.overviewReturnProgress(
                    rawZoom: rawZoom
                )
                onScaleReturnChanged(scaleReturnProgress)
            }
            .onEnded { _ in
                guard interactive else { return }
                scaleGestureActive = false
                let shouldReturn = ObservationScale.shouldCommit(scaleReturnProgress)
                onScaleReturnEnded(shouldReturn)
                scaleReturnProgress = 0
                onScaleReturnChanged(0)
                if shouldReturn {
                    settledZoom = zoom
                    recoverRenderDetails(after: transitionMotionEnabled ? 0.22 : 0.08)
                } else {
                    startScaleInertia(
                        logarithmicVelocity: scaleLogarithmicVelocity
                    )
                }
            }
    }

    private func resetView() {
        guard interactive else { return }
        cancelSpatialInertia()
        settledYaw = -0.42
        settledPitch = 0.28
        settledZoom = 1
        scaleModified = false
        beginRenderInteraction()
        withAnimation(Motion.fieldReset) {
            yaw = settledYaw
            pitch = settledPitch
            zoom = settledZoom
        }
        recoverRenderDetails(after: transitionMotionEnabled ? 0.48 : 0.08)
    }

    private func startOrbitInertia(
        yawVelocity: Double,
        pitchVelocity: Double
    ) {
        let initialSpeed = hypot(yawVelocity, pitchVelocity)
        guard transitionMotionEnabled,
              initialSpeed > SpatialMotion.minimumAngularVelocity
        else {
            settledYaw = yaw
            settledPitch = pitch
            recoverRenderDetails(after: 0.08)
            emphasizeObserverLabel()
            return
        }

        spatialMotionEvent &+= 1
        let event = spatialMotionEvent
        spatialInertiaActive = true
        beginRenderInteraction()

        Task { @MainActor in
            var horizontalVelocity = yawVelocity
            var verticalVelocity = pitchVelocity
            var previousDate = Date()

            while hypot(horizontalVelocity, verticalVelocity)
                    > SpatialMotion.minimumAngularVelocity {
                try? await Task.sleep(for: .seconds(SpatialMotion.frameInterval))
                guard event == spatialMotionEvent,
                      !orbitGestureActive,
                      !scaleGestureActive
                else { return }

                let now = Date()
                let deltaTime = min(
                    0.05,
                    max(0.008, now.timeIntervalSince(previousDate))
                )
                previousDate = now

                let pitchResistance = SpatialMotion.boundaryVelocityScale(
                    value: pitch,
                    velocity: verticalVelocity,
                    lowerBound: -1.28,
                    upperBound: 1.28,
                    slowZone: 0.24
                )
                horizontalVelocity *= SpatialMotion.decayFactor(
                    rate: SpatialMotion.rotationDecay,
                    deltaTime: deltaTime
                )
                verticalVelocity *= SpatialMotion.decayFactor(
                    rate: SpatialMotion.rotationDecay,
                    deltaTime: deltaTime
                ) * pitchResistance

                yaw += horizontalVelocity * deltaTime
                pitch = Self.clampedPitch(
                    pitch + verticalVelocity * deltaTime
                )
            }

            guard event == spatialMotionEvent else { return }
            settledYaw = yaw
            settledPitch = pitch
            spatialInertiaActive = false
            recoverRenderDetails(after: 0.1)
            emphasizeObserverLabel(after: 0.08)
        }
    }

    private func startScaleInertia(logarithmicVelocity: Double) {
        guard transitionMotionEnabled,
              abs(logarithmicVelocity) > SpatialMotion.minimumScaleVelocity
        else {
            settledZoom = zoom
            recoverRenderDetails(after: 0.08)
            return
        }

        spatialMotionEvent &+= 1
        let event = spatialMotionEvent
        spatialInertiaActive = true
        beginRenderInteraction()

        Task { @MainActor in
            var velocity = min(1.4, max(-1.4, logarithmicVelocity))
            var previousDate = Date()

            while abs(velocity) > SpatialMotion.minimumScaleVelocity {
                try? await Task.sleep(for: .seconds(SpatialMotion.frameInterval))
                guard event == spatialMotionEvent,
                      !orbitGestureActive,
                      !scaleGestureActive
                else { return }

                let now = Date()
                let deltaTime = min(
                    0.05,
                    max(0.008, now.timeIntervalSince(previousDate))
                )
                previousDate = now
                velocity *= SpatialMotion.boundaryVelocityScale(
                    value: Double(zoom),
                    velocity: velocity,
                    lowerBound: 0.78,
                    upperBound: Double(ObservationScale.maximumOverviewZoom),
                    slowZone: 0.16
                )
                velocity *= SpatialMotion.decayFactor(
                    rate: SpatialMotion.scaleDecay,
                    deltaTime: deltaTime
                )
                zoom = min(
                    ObservationScale.maximumOverviewZoom,
                    max(
                        0.78,
                        zoom * CGFloat(exp(velocity * deltaTime))
                    )
                )
                scaleModified = abs(zoom - 1) > 0.015
            }

            guard event == spatialMotionEvent else { return }
            settledZoom = zoom
            spatialInertiaActive = false
            recoverRenderDetails(after: 0.1)
        }
    }

    private func cancelSpatialInertia() {
        spatialMotionEvent &+= 1
        spatialInertiaActive = false
        settledYaw = yaw
        settledPitch = pitch
        settledZoom = zoom
    }

    private func markGestureHintsSeen() {
        guard !gestureHintsSeen else { return }
        withAnimation(.easeOut(duration: 0.28)) {
            gestureHintsSeen = true
        }
    }

    private func beginRenderInteraction() {
        renderRecoveryEvent &+= 1
        renderDetailsSettled = false
    }

    private func recoverRenderDetails(after delay: TimeInterval) {
        renderRecoveryEvent &+= 1
        let event = renderRecoveryEvent
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard event == renderRecoveryEvent,
                  !orbitGestureActive,
                  !scaleGestureActive,
                  !spatialInertiaActive
            else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                renderDetailsSettled = true
            }
        }
    }

    private func cancelObserverLabelEmphasis() {
        observerLabelEvent &+= 1
        withAnimation(.easeOut(duration: 0.12)) {
            observerLabelEmphasized = false
        }
    }

    private func emphasizeObserverLabel(after delay: TimeInterval = 0) {
        observerLabelEvent &+= 1
        let event = observerLabelEvent
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard event == observerLabelEvent else { return }
            withAnimation(.easeOut(duration: transitionMotionEnabled ? 0.18 : 0.08)) {
                observerLabelEmphasized = true
            }
            try? await Task.sleep(for: .seconds(1.4))
            guard event == observerLabelEvent else { return }
            withAnimation(.easeOut(duration: transitionMotionEnabled ? 0.34 : 0.1)) {
                observerLabelEmphasized = false
            }
        }
    }

    private func revealObserverLabelIfNeeded(at location: CGPoint, in size: CGSize) {
        guard interactive else { return }
        let geometry = renderedGeometry(in: size)
        guard let observer = observerProjection(geometry: geometry),
              observer.depth >= 0,
              hypot(location.x - observer.point.x, location.y - observer.point.y) <= 28
        else { return }
        emphasizeObserverLabel()
    }

    nonisolated private static func clampedPitch(_ value: Double) -> Double {
        min(1.28, max(-1.28, value))
    }

    nonisolated private static func shortestAngle(from start: Double, to end: Double) -> Double {
        var delta = (end - start).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return delta
    }

    /// 交互时稳定降采样；停止后按缩放级别恢复细节。NORAD 取模由调用方执行，
    /// 同一目标在连续帧中始终处于相同档位，不会因随机抽样产生闪烁。
    nonisolated static func renderSampleDivisor(
        zoom: CGFloat,
        interactionActive: Bool
    ) -> Int {
        if interactionActive { return 4 }
        if zoom < 0.92 { return 3 }
        if zoom < 1.14 { return 2 }
        return 1
    }

    // MARK: - 三维投影

    struct GlobeGeometry {
        let center: CGPoint
        let radius: CGFloat

        var rect: CGRect {
            CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        }
    }

    nonisolated static func globeGeometry(in size: CGSize) -> GlobeGeometry {
        let horizontalRadius = (size.width - 16) / CGFloat(2 * maximumOrbitDisplayRadius)
        let verticalRadius = (size.height - 214) / CGFloat(2 * maximumOrbitDisplayRadius)
        let radius = max(148, min(horizontalRadius, verticalRadius))
        let orbitalExtent = radius * CGFloat(maximumOrbitDisplayRadius)
        let preferredCenterY = size.height * 0.42
        let centerY = min(
            size.height - 174 - orbitalExtent,
            max(78 + orbitalExtent, preferredCenterY)
        )
        return GlobeGeometry(
            center: CGPoint(x: size.width / 2, y: centerY),
            radius: radius
        )
    }

    private func renderedGeometry(in size: CGSize) -> GlobeGeometry {
        let base = Self.globeGeometry(in: size)
        let progress = min(1, max(0, transitionProgress))
        let scale: CGFloat = transitionMotionEnabled
            ? 1 + 2.55 * CGFloat(pow(1 - progress, 1.28))
            : 1
        let offset: CGFloat = transitionMotionEnabled
            ? size.height * 0.24 * CGFloat(pow(1 - progress, 1.15))
            : 0
        return GlobeGeometry(
            center: CGPoint(x: base.center.x, y: base.center.y + offset),
            radius: base.radius * scale
        )
    }

    /// 将真实 ECI 半径压缩到可读的视觉壳层。对数映射同时保留 LEO 的层次，
    /// 又不会让 GEO 把地球压成一个几乎不可见的小点。
    nonisolated static func project(
        orbitalPosition: SIMD3<Double>,
        center: CGPoint,
        radius: CGFloat,
        yaw: Double,
        pitch: Double,
        zoom: CGFloat
    ) -> Projected3D? {
        let magnitude = Self.magnitude(of: orbitalPosition)
        guard magnitude > 1 else { return nil }
        let altitude = max(0, magnitude - 6378.137)
        let normalizedAltitude = min(
            1,
            log1p(altitude / 350) / log1p(36_000 / 350)
        )
        let displayRadius = earthDisplayRadius
            + (maximumOrbitDisplayRadius - earthDisplayRadius)
                * pow(normalizedAltitude, 0.68)
        return projectDirection(
            orbitalPosition / magnitude,
            displayRadius: displayRadius,
            center: center,
            radius: radius,
            yaw: yaw,
            pitch: pitch,
            zoom: zoom
        )
    }

    nonisolated private static func projectDirection(
        _ direction: SIMD3<Double>,
        displayRadius: Double,
        center: CGPoint,
        radius: CGFloat,
        yaw: Double,
        pitch: Double,
        zoom: CGFloat
    ) -> Projected3D {
        let cy = cos(yaw)
        let sy = sin(yaw)
        let cp = cos(pitch)
        let sp = sin(pitch)
        let x = direction.x * cy + direction.z * sy
        let firstDepth = -direction.x * sy + direction.z * cy
        let y = direction.y * cp - firstDepth * sp
        let depth = direction.y * sp + firstDepth * cp
        let scale = Double(radius * zoom) * displayRadius
        return Projected3D(
            point: CGPoint(
                x: center.x + CGFloat(x * scale),
                y: center.y - CGFloat(y * scale)
            ),
            depth: depth * displayRadius
        )
    }

    nonisolated private static func magnitude(of value: SIMD3<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }

    // MARK: - 绘制

    private func drawAmbientSpace(
        _ context: GraphicsContext,
        geometry: GlobeGeometry
    ) {
        let earthRadius = geometry.radius * zoom * CGFloat(Self.earthDisplayRadius)
        let auraRect = CGRect(
            x: geometry.center.x - earthRadius * 1.28,
            y: geometry.center.y - earthRadius * 1.28,
            width: earthRadius * 2.56,
            height: earthRadius * 2.56
        )
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 26))
            glow.fill(
                Path(ellipseIn: auraRect),
                with: .color(Palette.signal.opacity(0.018))
            )
        }
    }

    /// 轨道参考只用不闭合的倾斜弧线表达空间方向，不再形成包裹页面的外圈。
    private func drawOrbitGuides(
        _ context: GraphicsContext,
        geometry: GlobeGeometry
    ) {
        drawOrbitGuide(
            context,
            geometry: geometry,
            displayRadius: 0.66,
            inclination: 0.90,
            ascendingNode: -0.48,
            start: -2.45,
            end: 1.28,
            opacity: 0.11
        )
        drawOrbitGuide(
            context,
            geometry: geometry,
            displayRadius: 0.79,
            inclination: 1.32,
            ascendingNode: 0.72,
            start: -1.16,
            end: 2.34,
            opacity: 0.075
        )
    }

    private func drawOrbitGuide(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        displayRadius: Double,
        inclination: Double,
        ascendingNode: Double,
        start: Double,
        end: Double,
        opacity: Double
    ) {
        let ci = cos(inclination)
        let si = sin(inclination)
        let cn = cos(ascendingNode)
        let sn = sin(ascendingNode)
        let step = (end - start) / 54
        let points = stride(from: start, through: end, by: step).map { angle in
            let orbital = SIMD3(
                cos(angle),
                sin(angle) * ci,
                sin(angle) * si
            )
            let rotated = SIMD3(
                orbital.x * cn - orbital.y * sn,
                orbital.x * sn + orbital.y * cn,
                orbital.z
            )
            return Self.projectDirection(
                rotated,
                displayRadius: displayRadius,
                center: geometry.center,
                radius: geometry.radius,
                yaw: renderedYaw,
                pitch: renderedPitch,
                zoom: zoom
            )
        }
        strokeSegments(
            context,
            projected: points,
            front: false,
            color: Palette.inkLow.opacity(opacity * 0.24),
            style: StrokeStyle(lineWidth: 0.38, dash: [1, 5.5])
        )
        strokeSegments(
            context,
            projected: points,
            front: true,
            color: Palette.inkLow.opacity(opacity),
            style: StrokeStyle(lineWidth: 0.52, lineCap: .round, dash: [1, 5.5])
        )
    }

    private func drawField(
        _ context: GraphicsContext,
        samples: [RenderSample],
        front: Bool,
        focusedFamily: CatalogFamily?,
        simplified: Bool
    ) {
        var exploration: [CGPoint] = []
        var observation: [CGPoint] = []
        var network: [CGPoint] = []
        var legacy: [CGPoint] = []
        var explorationNear: [CGPoint] = []
        var observationNear: [CGPoint] = []
        var networkNear: [CGPoint] = []
        var legacyNear: [CGPoint] = []
        var familyFields: [CatalogFamily: [CGPoint]] = [:]
        var familyNearFields: [CatalogFamily: [CGPoint]] = [:]
        exploration.reserveCapacity(samples.count / 8)
        observation.reserveCapacity(samples.count / 6)
        network.reserveCapacity(samples.count / 5)
        legacy.reserveCapacity(64)
        familyFields.reserveCapacity(CatalogFamily.allCases.count)

        for sample in samples where sample.object.id != focusedObjectId {
            guard (sample.projected.depth >= 0) == front else { continue }
            let isNear = front && sample.projected.depth > 0.24
            if let family = sample.object.family {
                if isNear {
                    familyNearFields[family, default: []].append(sample.projected.point)
                } else {
                    familyFields[family, default: []].append(sample.projected.point)
                }
            } else {
                switch sample.object.category {
                case .exploration:
                    if isNear {
                        explorationNear.append(sample.projected.point)
                    } else {
                        exploration.append(sample.projected.point)
                    }
                case .observation:
                    if isNear {
                        observationNear.append(sample.projected.point)
                    } else {
                        observation.append(sample.projected.point)
                    }
                case .network:
                    if isNear {
                        networkNear.append(sample.projected.point)
                    } else {
                        network.append(sample.projected.point)
                    }
                case .legacy:
                    if isNear {
                        legacyNear.append(sample.projected.point)
                    } else {
                        legacy.append(sample.projected.point)
                    }
                }
            }
        }

        let sideOpacity = front ? 1.0 : 0.19
        let detailOpacity = simplified ? 0.68 : 1.0
        let ordinaryHalo = simplified ? 0 : (front ? 0.016 : 0)
        SkyRenderer.drawTargetField(
            context,
            points: exploration,
            tint: Palette.explorationTint,
            opacity: 0.43 * sideOpacity * detailOpacity,
            coreRadius: front ? (simplified ? 0.52 : 0.62) : 0.45,
            haloStrength: ordinaryHalo
        )
        SkyRenderer.drawTargetField(
            context,
            points: observation,
            tint: Palette.observationTint,
            opacity: 0.42 * sideOpacity * detailOpacity,
            coreRadius: front ? (simplified ? 0.51 : 0.60) : 0.44,
            haloStrength: ordinaryHalo
        )
        SkyRenderer.drawTargetField(
            context,
            points: network,
            tint: Palette.networkTint,
            opacity: 0.4 * sideOpacity * detailOpacity,
            coreRadius: front ? (simplified ? 0.5 : 0.59) : 0.43,
            haloStrength: ordinaryHalo
        )
        SkyRenderer.drawTargetField(
            context,
            points: legacy,
            tint: Palette.legacyTint,
            opacity: 0.36 * sideOpacity * detailOpacity,
            coreRadius: front ? (simplified ? 0.48 : 0.57) : 0.42,
            haloStrength: simplified ? 0 : (front ? 0.012 : 0)
        )
        if front, !simplified {
            SkyRenderer.drawTargetField(
                context, points: explorationNear, tint: Palette.explorationTint,
                opacity: 0.72, coreRadius: 0.92, haloStrength: 0.045
            )
            SkyRenderer.drawTargetField(
                context, points: observationNear, tint: Palette.observationTint,
                opacity: 0.69, coreRadius: 0.88, haloStrength: 0.042
            )
            SkyRenderer.drawTargetField(
                context, points: networkNear, tint: Palette.networkTint,
                opacity: 0.66, coreRadius: 0.86, haloStrength: 0.038
            )
            SkyRenderer.drawTargetField(
                context, points: legacyNear, tint: Palette.legacyTint,
                opacity: 0.58, coreRadius: 0.82, haloStrength: 0.032
            )
        }
        for family in CatalogFamily.allCases {
            let emphasized = family == focusedFamily
            SkyRenderer.drawTargetField(
                context,
                points: familyFields[family, default: []],
                tint: family.tint,
                opacity: (emphasized ? 0.64 : 0.28) * sideOpacity * detailOpacity,
                coreRadius: emphasized
                    ? (front ? (simplified ? 0.7 : 0.86) : 0.54)
                    : (front ? (simplified ? 0.48 : 0.56) : 0.38),
                haloStrength: simplified
                    ? 0
                    : (front ? (emphasized ? 0.1 : 0.026) : 0)
            )
            if front, !simplified {
                SkyRenderer.drawTargetField(
                    context,
                    points: familyNearFields[family, default: []],
                    tint: family.tint,
                    opacity: emphasized ? 0.88 : 0.5,
                    coreRadius: emphasized ? 1.08 : 0.8,
                    haloStrength: emphasized ? 0.15 : 0.045
                )
            }
        }
    }

    private func drawFocusedObject(_ context: GraphicsContext, samples: [RenderSample]) {
        guard let sample = samples.first(where: { $0.object.id == focusedObjectId }) else { return }
        let point = sample.projected.point
        let tint = sample.object.identityTint
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 5))
            glow.fill(
                Path(ellipseIn: CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)),
                with: .color(tint.opacity(0.3))
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 1.7, y: point.y - 1.7, width: 3.4, height: 3.4)),
            with: .color(Palette.inkHigh.opacity(0.98))
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)),
            with: .color(tint.opacity(0.94)),
            style: StrokeStyle(lineWidth: 0.9, dash: [2, 2.4])
        )
    }

    private func drawSpatialTrails(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        front: Bool,
        simplified: Bool
    ) {
        for object in session.visibleTrailObjects {
            if simplified, object.id != focusedObjectId { continue }
            guard let spatialPoints = trails.spatialTrails[object.id], spatialPoints.count > 1 else {
                continue
            }
            let pointStride = simplified ? max(1, spatialPoints.count / 18) : 1
            let projected = spatialPoints.enumerated().compactMap {
                index, point -> (Projected3D, TimeInterval)? in
                guard index.isMultiple(of: pointStride)
                        || index == spatialPoints.count - 1
                else { return nil }
                guard let projection = Self.project(
                    orbitalPosition: point.position,
                    center: geometry.center,
                    radius: geometry.radius,
                    yaw: renderedYaw,
                    pitch: renderedPitch,
                    zoom: zoom
                ) else { return nil }
                return (projection, point.at)
            }
            let tint = object.identityTint
            let focused = object.id == focusedObjectId
            var segment: [TrailStore.TrailPoint] = []
            for item in projected {
                if (item.0.depth >= 0) == front {
                    segment.append(TrailStore.TrailPoint(point: item.0.point, at: item.1))
                } else {
                    drawTrailSegment(
                        context,
                        points: segment,
                        tint: tint,
                        front: front,
                        focused: focused
                    )
                    segment.removeAll(keepingCapacity: true)
                }
            }
            drawTrailSegment(
                context,
                points: segment,
                tint: tint,
                front: front,
                focused: focused
            )
        }
    }

    private func drawTrailSegment(
        _ context: GraphicsContext,
        points: [TrailStore.TrailPoint],
        tint: Color,
        front: Bool,
        focused: Bool
    ) {
        guard points.count > 1 else { return }
        SkyRenderer.drawTrail(
            context,
            points: points,
            frameTime: frameTime,
            tint: tint,
            intensity: focused
                ? (front ? 1.0 : 0.3)
                : (front ? 0.62 : 0.12),
            lifetime: trails.trailLifetime
        )
    }

    private func drawEarth(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        simplified: Bool
    ) {
        let earthRadius = geometry.radius * zoom * Self.earthDisplayRadius
        let earthRect = CGRect(
            x: geometry.center.x - earthRadius,
            y: geometry.center.y - earthRadius,
            width: earthRadius * 2,
            height: earthRadius * 2
        )
        let earth = Path(ellipseIn: earthRect)
        context.drawLayer { atmosphere in
            atmosphere.addFilter(.blur(radius: 9))
            atmosphere.stroke(
                Path(ellipseIn: earthRect.insetBy(dx: -2.5, dy: -2.5)),
                with: .color(Palette.observationTint.opacity(0.11)),
                style: StrokeStyle(lineWidth: 3.2)
            )
        }
        context.fill(
            earth,
            with: .radialGradient(
                Gradient(stops: [
                    .init(
                        color: Palette.observationTint.opacity(0.12),
                        location: 0
                    ),
                    .init(
                        color: Palette.dust.opacity(0.48),
                        location: 0.38
                    ),
                    .init(
                        color: Palette.voidBlack.opacity(0.92),
                        location: 1
                    ),
                ]),
                center: CGPoint(
                    x: geometry.center.x - earthRadius * 0.34,
                    y: geometry.center.y - earthRadius * 0.28
                ),
                startRadius: 0,
                endRadius: earthRadius * 1.42
            )
        )

        drawObserverVisibilityRegion(
            context,
            geometry: geometry,
            earthPath: earth,
            simplified: simplified,
            presence: surfaceDetailPresence
        )
        drawEarthCoastlines(context, geometry: geometry, simplified: simplified)
        drawEarthGrid(context, geometry: geometry, simplified: simplified)
        context.stroke(
            earth,
            with: .color(Palette.inkMid.opacity(0.54)),
            style: StrokeStyle(lineWidth: 0.82)
        )
    }

    private func drawEarthGrid(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        simplified: Bool
    ) {
        let tint = Palette.inkLow.opacity(
            (simplified ? 0.075 : 0.13) * surfaceDetailPresence
        )
        let latitudeStep = simplified ? 45.0 : 30.0
        let longitudeStep = simplified ? Double.pi / 4 : Double.pi / 6
        let sampleStep = simplified ? Double.pi / 20 : Double.pi / 36

        for latitude in stride(
            from: -60.0,
            through: 60.0,
            by: latitudeStep
        ) {
            let lat = latitude * .pi / 180
            let points = stride(
                from: 0.0,
                through: Double.pi * 2,
                by: sampleStep
            ).map { longitude in
                Self.projectDirection(
                    SIMD3(cos(lat) * cos(longitude), cos(lat) * sin(longitude), sin(lat)),
                    displayRadius: Self.earthDisplayRadius,
                    center: geometry.center,
                    radius: geometry.radius,
                    yaw: renderedYaw,
                    pitch: renderedPitch,
                    zoom: zoom
                )
            }
            strokeSegments(context, projected: points, front: true, color: tint)
        }
        for longitude in stride(
            from: 0.0,
            to: Double.pi * 2,
            by: longitudeStep
        ) {
            let points = stride(
                from: -Double.pi / 2,
                through: Double.pi / 2,
                by: sampleStep
            ).map { latitude in
                Self.projectDirection(
                    SIMD3(cos(latitude) * cos(longitude), cos(latitude) * sin(longitude), sin(latitude)),
                    displayRadius: Self.earthDisplayRadius,
                    center: geometry.center,
                    radius: geometry.radius,
                    yaw: renderedYaw,
                    pitch: renderedPitch,
                    zoom: zoom
                )
            }
            strokeSegments(context, projected: points, front: true, color: tint)
        }
    }

    private func drawEarthCoastlines(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        simplified: Bool
    ) {
        let coordinateStride = simplified ? 4 : 2
        let siderealRadians = zeroMeanSiderealTime(
            julianDate: observation.julianDate
        ) * .pi / 180
        for coastline in Self.coastlineSamples {
            let projected = stride(
                from: 0,
                to: coastline.count - 1,
                by: coordinateStride
            ).map { index in
                let direction = Self.sphericalSurfaceDirection(
                    latitude: Double(coastline[index]),
                    longitude: Double(coastline[index + 1]),
                    siderealRadians: siderealRadians
                )
                return Self.projectDirection(
                    direction,
                    displayRadius: Self.earthDisplayRadius,
                    center: geometry.center,
                    radius: geometry.radius,
                    yaw: renderedYaw,
                    pitch: renderedPitch,
                    zoom: zoom
                )
            }
            strokeSegments(
                context,
                projected: projected,
                front: true,
                color: Palette.observationTint.opacity(
                    (simplified ? 0.14 : 0.24) * surfaceDetailPresence
                ),
                style: StrokeStyle(
                    lineWidth: simplified ? 0.38 : 0.48,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    /// 默认可见区域是一块真正贴在球面的球冠，而不是屏幕坐标中的平面圆。
    private func drawObserverVisibilityRegion(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        earthPath: Path,
        simplified: Bool,
        presence: Double
    ) {
        guard presence > 0.01,
              let up = observerSurfaceDirection()
        else { return }
        let centerProjection = Self.projectDirection(
            up,
            displayRadius: Self.earthDisplayRadius,
            center: geometry.center,
            radius: geometry.radius,
            yaw: renderedYaw,
            pitch: renderedPitch,
            zoom: zoom
        )
        guard centerProjection.depth > -0.02 else { return }

        var tangent = simd_cross(SIMD3<Double>(0, 0, 1), up)
        if simd_length(tangent) < 1e-6 {
            tangent = SIMD3(1, 0, 0)
        } else {
            tangent = simd_normalize(tangent)
        }
        let bitangent = simd_normalize(simd_cross(up, tangent))
        let angularRadius = 28.0 * Double.pi / 180
        let sampleCount = simplified ? 28 : 56
        let ring = (0 ... sampleCount).map { index in
            let angle = Double(index) / Double(sampleCount) * 2 * Double.pi
            let surfaceDirection = up * cos(angularRadius)
                + (
                    tangent * cos(angle)
                        + bitangent * sin(angle)
                ) * sin(angularRadius)
            return Self.projectDirection(
                surfaceDirection,
                displayRadius: Self.earthDisplayRadius,
                center: geometry.center,
                radius: geometry.radius,
                yaw: renderedYaw,
                pitch: renderedPitch,
                zoom: zoom
            )
        }

        if ring.allSatisfy({ $0.depth >= 0 }) {
            var fillPath = Path()
            if let first = ring.first {
                fillPath.move(to: first.point)
                for point in ring.dropFirst() {
                    fillPath.addLine(to: point.point)
                }
                fillPath.closeSubpath()
            }
            context.drawLayer { field in
                field.clip(to: earthPath)
                if !simplified {
                    field.addFilter(.blur(radius: 2.2))
                }
                field.fill(
                    fillPath,
                    with: .color(
                        Palette.signal.opacity(
                            (simplified ? 0.055 : 0.09) * presence
                        )
                    )
                )
            }
        }

        strokeSegments(
            context,
            projected: ring,
            front: true,
            color: Palette.signal.opacity(
                (simplified ? 0.24 : 0.46) * presence
            ),
            style: StrokeStyle(
                lineWidth: simplified ? 0.52 : 0.68,
                lineCap: .round,
                dash: [1.4, 2.6]
            )
        )

        if !simplified,
           presence > 0.78,
           centerProjection.depth > 0.12,
           let labelAnchor = ring.first,
           labelAnchor.depth >= 0 {
            context.draw(
                Text("默认视域")
                    .font(Typography.statusTag)
                    .tracking(0.55)
                    .foregroundStyle(Palette.signal.opacity(0.62)),
                at: CGPoint(
                    x: labelAnchor.point.x + 5,
                    y: labelAnchor.point.y - 4
                ),
                anchor: .leading
            )
        }
    }

    /// 观察者标记在真实地表位置：断续定位环、菱形核心和外向刻度组成仪器符号，
    /// 静止时显示“当前位置”，交互时弱化以优先保证球体旋转的连续性。
    private func drawObserver(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        simplified: Bool
    ) {
        guard let projected = observerProjection(geometry: geometry),
              projected.depth >= 0
        else { return }
        let point = projected.point
        let alpha = (simplified ? 0.72 : 1.0) * surfaceDetailPresence
        guard alpha > 0.01 else { return }
        let pulse = simplified
            ? 1
            : 1 + CGFloat(sin(motionTime * 1.25)) * 0.055
        let ringRadius: CGFloat = 7.2 * pulse

        if !simplified {
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 4))
                glow.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - 7,
                        y: point.y - 7,
                        width: 14,
                        height: 14
                    )),
                    with: .color(Palette.signal.opacity(0.18 * alpha))
                )
            }
        }
        context.stroke(
            Path(ellipseIn: CGRect(
                x: point.x - ringRadius,
                y: point.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )),
            with: .color(Palette.signal.opacity(0.82 * alpha)),
            style: StrokeStyle(
                lineWidth: 0.7,
                dash: [1.2, 2.2],
                dashPhase: CGFloat(motionTime * 1.6)
            )
        )
        var diamond = Path()
        diamond.move(to: CGPoint(x: point.x, y: point.y - 3.4))
        diamond.addLine(to: CGPoint(x: point.x + 3.4, y: point.y))
        diamond.addLine(to: CGPoint(x: point.x, y: point.y + 3.4))
        diamond.addLine(to: CGPoint(x: point.x - 3.4, y: point.y))
        diamond.closeSubpath()
        context.fill(diamond, with: .color(Palette.signal.opacity(0.2 * alpha)))
        context.stroke(
            diamond,
            with: .color(Palette.inkHigh.opacity(0.9 * alpha)),
            style: StrokeStyle(lineWidth: 0.72)
        )
        let labelTint = observerLabelEmphasized ? Palette.signal : Palette.inkMid
        let baseLabelOpacity = observerLabelEmphasized
            ? 0.9
            : (simplified ? 0.26 : 0.62)
        let labelOpacity = baseLabelOpacity * surfaceDetailPresence
        context.draw(
            Text("当前位置")
                .font(Typography.statusTag)
                .tracking(0.55)
                .foregroundStyle(labelTint.opacity(labelOpacity)),
            at: CGPoint(x: point.x + 12, y: point.y - 8),
            anchor: .leading
        )
    }

    private func observerProjection(geometry: GlobeGeometry) -> Projected3D? {
        guard let direction = observerSurfaceDirection() else { return nil }
        return Self.projectDirection(
            direction,
            displayRadius: Self.earthDisplayRadius,
            center: geometry.center,
            radius: geometry.radius,
            yaw: renderedYaw,
            pitch: renderedPitch,
            zoom: zoom
        )
    }

    private func observerSurfaceDirection() -> SIMD3<Double>? {
        let coordinates = session.observer.coordinates
        return earthSurfaceDirection(
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            altitudeMeters: coordinates.altitudeMeters
        )
    }

    private func earthSurfaceDirection(
        latitude: Double,
        longitude: Double,
        altitudeMeters: Double = 0
    ) -> SIMD3<Double>? {
        let eci = geo2eci(
            julianDays: observation.julianDate,
            geodetic: LatLonAlt(
                latitude,
                longitude,
                altitudeMeters / 1000
            )
        )
        let vector = SIMD3(eci.x, eci.y, eci.z)
        let magnitude = Self.magnitude(of: vector)
        guard magnitude > 0 else { return nil }
        return vector / magnitude
    }

    nonisolated static func sphericalSurfaceDirection(
        latitude: Double,
        longitude: Double,
        siderealRadians: Double
    ) -> SIMD3<Double> {
        let latitudeRadians = latitude * .pi / 180
        let longitudeRadians = longitude * .pi / 180 + siderealRadians
        let latitudeScale = cos(latitudeRadians)
        return SIMD3(
            latitudeScale * cos(longitudeRadians),
            latitudeScale * sin(longitudeRadians),
            sin(latitudeRadians)
        )
    }

    private func strokeSegments(
        _ context: GraphicsContext,
        projected: [Projected3D],
        front: Bool,
        color: Color,
        style: StrokeStyle = StrokeStyle(lineWidth: 0.42)
    ) {
        var path = Path()
        var drawing = false
        for point in projected {
            let matches = (point.depth >= 0) == front
            if matches {
                if drawing {
                    path.addLine(to: point.point)
                } else {
                    path.move(to: point.point)
                    drawing = true
                }
            } else {
                drawing = false
            }
        }
        context.stroke(path, with: .color(color), style: style)
    }

    private func drawLegend(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        displayed: Int,
        total: Int,
        presence: Double,
        showGestureHint: Bool
    ) {
        guard presence > 0.01 else { return }
        context.draw(
            Text("DISPLAY  \(displayed)  /  CATALOG  \(total)")
                .font(Typography.statusTag)
                .tracking(Typography.statusTagTracking)
                .foregroundStyle(
                    Palette.inkLow.opacity(Palette.Level.readableSecondary * presence)
                ),
            at: CGPoint(
                x: geometry.center.x,
                y: geometry.rect.maxY + 28
            ),
            anchor: .center
        )
        if showGestureHint {
            context.draw(
                Text("DRAG  ↕↔  ·  PINCH  ±  ·  DOUBLE TAP  RESET")
                    .font(Typography.statusTag)
                    .tracking(0.7)
                    .foregroundStyle(Palette.inkLow.opacity(0.68 * presence)),
                at: CGPoint(
                    x: geometry.center.x,
                    y: geometry.rect.maxY + 47
                ),
                anchor: .center
            )
        }
    }
}
