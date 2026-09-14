import SatelliteKit
import SwiftUI
import simd

/// 空闲展示旋转的纯值时基。它只保存相位和锚点，SwiftUI 的 30fps 时间线负责取样；
/// 暂停与恢复不会改写用户手动姿态，因此交互前后角度连续。
struct OverviewShowcaseRotation: Equatable {
    nonisolated static let revolutionDuration: TimeInterval = 180
    nonisolated static let resumeDelay: TimeInterval = 2

    private(set) var phase: Double = 0
    private(set) var anchorTime: TimeInterval = 0
    private(set) var isPaused = true

    nonisolated mutating func reset(
        at time: TimeInterval,
        motionEnabled: Bool
    ) {
        phase = 0
        anchorTime = time
        isPaused = !motionEnabled
    }

    nonisolated mutating func pause(at time: TimeInterval) {
        guard !isPaused else { return }
        phase = angle(at: time, motionEnabled: true)
        anchorTime = time
        isPaused = true
    }

    nonisolated mutating func resume(
        at time: TimeInterval,
        motionEnabled: Bool
    ) {
        guard motionEnabled else {
            pause(at: time)
            return
        }
        guard isPaused else { return }
        anchorTime = time
        isPaused = false
    }

    nonisolated func angle(
        at time: TimeInterval,
        motionEnabled: Bool
    ) -> Double {
        guard motionEnabled, !isPaused else { return phase }
        let elapsed = max(0, time - anchorTime)
        let angle = phase + elapsed * 2 * .pi / Self.revolutionDuration
        return angle.truncatingRemainder(dividingBy: 2 * .pi)
    }
}

/// 沉浸式三维地球与轨道场。所有点位来自与主视野相同的 ECI 传播帧；
/// 地球、观察者、地表可见区域和轨道目标共享同一套旋转与缩放。
struct SkyOverviewView: View {
    /// 启动电影与全局地球共享同一套视觉半径，避免两处镜头比例逐渐漂移。
    nonisolated static let earthDisplayRadius: Double = 0.57
    nonisolated static let maximumOrbitDisplayRadius: Double = 0.88
    /// Natural Earth 1:110m 海岸线经过约 2° 视觉简化后的坐标。
    /// 每条数组按 `[纬度, 经度, …]` 存储，避免运行时解析地图资源。
    nonisolated static let coastlineSamples: [[Float]] = [
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
    @ObservedObject private var coastlineStore = EarthCoastlineStore.shared
    @ObservedObject private var brightStarStore = BrightStarStore.shared

    let observation: Date
    let frameTime: TimeInterval
    let motionTime: TimeInterval
    let trails: TrailStore
    let ambientTrails: TrailStore
    let ambientTrailsVisible: Bool
    let focusedObjectId: String?
    let transitionProgress: Double
    let entryPointing: Pointing?
    let celestialFrame: CelestialViewFrame?
    let transitionMotionEnabled: Bool
    let interactive: Bool
    let onInteractionStateChanged: (Bool) -> Void

    /// 地球姿态使用单一四元数，不再拆成带俯仰边界的 yaw / pitch / roll。
    /// 单指拖动因此是无死角的 Arcball，连续越过两极也不会碰到人为限位。
    @State private var orientation = Self.identityOrientation
    @State private var settledOrientation = Self.identityOrientation
    @State private var orbitGestureStartOrientation = Self.identityOrientation
    @State private var rotationGestureStartOrientation = Self.identityOrientation
    @State private var hasEstablishedDefaultOrientation = false
    @State private var zoom = ObservationScale.defaultOverviewZoom
    @State private var settledZoom = ObservationScale.defaultOverviewZoom
    @State private var scaleGestureActive = false
    @State private var orbitGestureActive = false
    @State private var rotationGestureActive = false
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
    @State private var projectedBrightStars: [ProjectedBrightStar] = []
    @State private var showcaseRotation = OverviewShowcaseRotation()
    @State private var showcaseResumeEvent = 0
    @AppStorage("overviewGestureHintsSeen") private var gestureHintsSeen = false

    private struct RenderSample {
        let object: CatalogObject
        let projected: Projected3D
    }

    struct Projected3D {
        let point: CGPoint
        /// 大于零表示朝向观察者。
        let depth: Double
        /// 经过高度压缩后的轨道壳层半径，用于把同一片点云分成远景、壳层与近景。
        let displayRadius: Double
    }

    private var transitionVisuals: ObservationScale.TransitionVisuals {
        ObservationScale.transitionVisuals(progress: transitionProgress)
    }

    private var controlHandoff: Double {
        transitionVisuals.cameraRetreat
    }

    private var surfaceDetailPresence: Double {
        transitionVisuals.surfaceDetailPresence
    }

    /// 默认镜头把观察者经度置于中央经线，并让赤道和纬线保持屏幕水平。默认
    /// 观察者为上海；获得真实定位后，复位会改为对准真实位置所在经度。
    private var defaultPresentationOrientation: simd_quatd {
        let coordinates = session.observer.coordinates
        let siderealRadians = zeroMeanSiderealTime(
            julianDate: observation.julianDate
        ) * .pi / 180
        return Self.presentationOrientation(
            latitude: 0,
            longitude: coordinates.longitude,
            siderealRadians: siderealRadians
        )
    }

    private var establishedOrientation: simd_quatd {
        hasEstablishedDefaultOrientation ? orientation : defaultPresentationOrientation
    }

    /// 转场初段仍会对设备姿态产生很轻的响应；接近全局尺度后固定到进入时的
    /// 观察方向，并把控制权完整交给触摸旋转。
    private var manuallyControlledOrientation: simd_quatd {
        let baseOrientation = establishedOrientation
        guard let entryPointing else { return baseOrientation }
        let azimuthDelta = Self.shortestAngle(
            from: entryPointing.azimuth,
            to: session.pointing.azimuth
        )
        let elevationDelta = session.pointing.elevation - entryPointing.elevation
        let handoff = 1 - controlHandoff
        let pointingAdjustment = Self.orientation(
            yaw: -azimuthDelta * 0.34 * handoff,
            pitch: elevationDelta * 0.28 * handoff,
            roll: 0
        )
        return simd_normalize(pointingAdjustment * baseOrientation)
    }

    /// 展示相位沿地球局部极轴组合到统一空间四元数。大陆、经纬网、观察者和
    /// 全部轨道对象因此同步转动；背景恒星不经过这个姿态，保持惯性静止。
    private func renderedOrientation(at time: TimeInterval) -> simd_quatd {
        let showcase = simd_quatd(
            angle: showcaseRotation.angle(
                at: time,
                motionEnabled: transitionMotionEnabled
            ),
            axis: SIMD3(0, 0, 1)
        )
        return simd_normalize(manuallyControlledOrientation * showcase)
    }

    private var renderingSimplified: Bool {
        orbitGestureActive
            || scaleGestureActive
            || rotationGestureActive
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
                let geometry = renderedGeometry(
                    in: size,
                    at: ProcessInfo.processInfo.systemUptime
                )
                context.drawLayer { starField in
                    starField.opacity = transitionVisuals.orbitalPresence
                    drawBrightStarField(starField)
                }
                Self.drawGlobeAmbient(
                    context,
                    geometry: geometry,
                    zoom: zoom,
                    simplified: renderingSimplified
                )

                let focusedObject = focusedObjectId.flatMap { session.catalog.objectsByID[$0] }
                let live = clock.isLive
                // 全局点云使用会话级稳定样本。交互前后集合完全一致；完整目录
                // 数量只用于图例，不再在 30fps Canvas 中逐颗投影。
                let renderObjects = session.overviewObjects

                var samples: [RenderSample] = []
                samples.reserveCapacity(renderObjects.count + 1)
                @MainActor func appendSample(_ object: CatalogObject) {
                    guard let ephemeris = session.ephemeris.cachedEphemeris(
                        object.id,
                        at: observation,
                        live: live
                    ), let projected = Self.project(
                        orbitalPosition: ephemeris.orbitalPosition,
                        center: geometry.center,
                        radius: geometry.radius,
                        orientation: geometry.orientation,
                        zoom: zoom
                    ) else { return }
                    samples.append(RenderSample(
                        object: object,
                        projected: projected
                    ))
                }
                for object in renderObjects {
                    appendSample(object)
                }
                if let focusedObject,
                   !renderObjects.contains(where: { $0.id == focusedObject.id }) {
                    appendSample(focusedObject)
                }

                context.drawLayer { backField in
                    backField.opacity = transitionVisuals.orbitalPresence
                    if !renderingSimplified {
                        drawOrbitGuides(backField, geometry: geometry)
                    }
                    drawAmbientSpatialTrails(
                        backField,
                        geometry: geometry,
                        front: false
                    )
                    drawSpatialTrails(
                        backField,
                        geometry: geometry,
                        front: false,
                        simplified: renderingSimplified
                    )
                    drawField(
                        backField,
                        samples: samples,
                        geometry: geometry,
                        front: false,
                        simplified: renderingSimplified
                    )
                }
                context.drawLayer { earthLayer in
                    drawEarth(
                        earthLayer,
                        geometry: geometry,
                        simplified: renderingSimplified
                    )
                }
                context.drawLayer { frontField in
                    frontField.opacity = transitionVisuals.orbitalPresence
                    drawAmbientSpatialTrails(
                        frontField,
                        geometry: geometry,
                        front: true
                    )
                    drawSpatialTrails(
                        frontField,
                        geometry: geometry,
                        front: true,
                        simplified: renderingSimplified
                    )
                    drawField(
                        frontField,
                        samples: samples,
                        geometry: geometry,
                        front: true,
                        simplified: renderingSimplified
                    )
                    drawFocusedObject(frontField, samples: samples)
                }
                context.drawLayer { surfaceOverlay in
                    Self.drawGlobeForegroundRim(
                        surfaceOverlay,
                        geometry: geometry,
                        zoom: zoom,
                        presence: surfaceDetailPresence
                    )
                    drawObserverVisibilityOverlay(
                        surfaceOverlay,
                        geometry: geometry,
                        simplified: renderingSimplified
                    )
                    drawObserver(
                        surfaceOverlay,
                        geometry: geometry,
                        simplified: renderingSimplified
                    )
                }

                drawGestureHint(
                    context,
                    geometry: baseGeometry,
                    presence: transitionVisuals.chromePresence,
                    showGestureHint: interactive
                        && !gestureHintsSeen
                        && transientGestureHintVisible
                        && !renderingSimplified
                )
            }
            .contentShape(Rectangle())
            .gesture(orbitGesture(in: proxy.size))
            .simultaneousGesture(magnificationGesture)
            .simultaneousGesture(rotationGesture)
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
                coastlineStore.prepare()
                brightStarStore.prepare()
                establishDefaultOrientationIfNeeded()
                showcaseRotation.reset(
                    at: ProcessInfo.processInfo.systemUptime,
                    motionEnabled: transitionMotionEnabled
                        && !clock.isTimeInteractionActive
                )
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--previewOverviewMaxZoom") {
                    zoom = ObservationScale.maximumOverviewZoom
                    settledZoom = zoom
                } else if arguments.contains("--previewOverviewTransform") {
                    orientation = Self.orientation(yaw: 0.72, pitch: -0.36, roll: 0.18)
                    settledOrientation = orientation
                    zoom = 1.26
                    settledZoom = zoom
                }
                if arguments.contains("--previewOverviewInteraction") {
                    renderDetailsSettled = false
                }
                #endif
            }
            .task(id: celestialProjectionKey(size: proxy.size)) {
                await updateBrightStarProjection(size: proxy.size)
            }
            .onChange(of: renderingSimplified) { _, active in
                onInteractionStateChanged(active)
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
            .onChange(of: clock.isTimeInteractionActive) { _, active in
                if active {
                    pauseShowcaseRotation()
                } else {
                    scheduleShowcaseRotationResume()
                }
            }
            .onChange(of: transitionMotionEnabled) { _, enabled in
                if enabled {
                    scheduleShowcaseRotationResume()
                } else {
                    pauseShowcaseRotation()
                }
            }
            .onDisappear {
                showcaseResumeEvent &+= 1
                cancelSpatialInertia()
                onInteractionStateChanged(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("overview.accessibility"))
        .accessibilityHint(interactive ? "单指上下左右旋转，双指缩放或旋转倾角，双击复位" : "拖动时间轴查看轨道变化")
        .accessibilityAction(named: "复位星图") { resetView() }
    }

    // MARK: - 交互

    private func orbitGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard interactive,
                      !scaleGestureActive,
                      !rotationGestureActive
                else { return }
                if !orbitGestureActive {
                    cancelSpatialInertia()
                    pauseShowcaseRotation()
                    orbitGestureActive = true
                    orbitGestureStartOrientation = orientation
                    beginRenderInteraction()
                    cancelObserverLabelEmphasis()
                    markGestureHintsSeen()
                }
                let geometry = renderedGeometry(in: size)
                let radius = Self.arcballRadius(in: size, geometry: geometry)
                let currentLocation = CGPoint(
                    x: value.startLocation.x + value.translation.width,
                    y: value.startLocation.y + value.translation.height
                )
                let delta = Self.arcballRotation(
                    from: value.startLocation,
                    to: currentLocation,
                    center: geometry.center,
                    radius: radius
                )
                orientation = simd_normalize(delta * orbitGestureStartOrientation)
            }
            .onEnded { value in
                guard interactive,
                      !scaleGestureActive,
                      !rotationGestureActive
                else { return }
                orbitGestureActive = false
                startOrbitInertia(
                    angularVelocity: SIMD3(
                        SpatialMotion.limitedAngularVelocity(
                            pointsPerSecond: value.velocity.height,
                            sensitivity: SpatialMotion.dragPitchSensitivity
                        ),
                        SpatialMotion.limitedAngularVelocity(
                            pointsPerSecond: value.velocity.width,
                            sensitivity: SpatialMotion.dragYawSensitivity
                        ),
                        0
                    )
                )
            }
    }

    /// 与系统地图一致的双指旋转：两指围绕中心扭转时，球体沿屏幕视轴倾斜。
    /// 它与 MagnificationGesture 同时识别，因此同一手势可以连续缩放并校正角度。
    private var rotationGesture: some Gesture {
        RotateGesture(minimumAngleDelta: .degrees(0.8))
            .onChanged { value in
                guard interactive else { return }
                if !rotationGestureActive {
                    cancelSpatialInertia()
                    pauseShowcaseRotation()
                    orbitGestureActive = false
                    rotationGestureActive = true
                    rotationGestureStartOrientation = orientation
                    beginRenderInteraction()
                    cancelObserverLabelEmphasis()
                    markGestureHintsSeen()
                }
                let delta = simd_quatd(
                    angle: -value.rotation.radians,
                    axis: SIMD3(0, 0, 1)
                )
                orientation = simd_normalize(delta * rotationGestureStartOrientation)
            }
            .onEnded { value in
                guard interactive else { return }
                rotationGestureActive = false
                if scaleGestureActive {
                    settledOrientation = orientation
                } else {
                    startOrientationInertia(
                        angularVelocity: SIMD3(0, 0, -value.velocity.radians),
                        maximumSpeed: 3.2
                    )
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard interactive else { return }
                if !scaleGestureActive {
                    cancelSpatialInertia()
                    pauseShowcaseRotation()
                    orbitGestureActive = false
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
                    max(ObservationScale.minimumOverviewZoom, rawZoom)
                )
            }
            .onEnded { _ in
                guard interactive else { return }
                scaleGestureActive = false
                if rotationGestureActive {
                    settledZoom = zoom
                } else {
                    startScaleInertia(
                        logarithmicVelocity: scaleLogarithmicVelocity
                    )
                }
            }
    }

    private func establishDefaultOrientationIfNeeded() {
        guard !hasEstablishedDefaultOrientation else { return }
        let defaultOrientation = defaultPresentationOrientation
        orientation = defaultOrientation
        settledOrientation = defaultOrientation
        orbitGestureStartOrientation = defaultOrientation
        rotationGestureStartOrientation = defaultOrientation
        hasEstablishedDefaultOrientation = true
    }

    private func resetView() {
        guard interactive else { return }
        cancelSpatialInertia()
        showcaseRotation.reset(
            at: ProcessInfo.processInfo.systemUptime,
            motionEnabled: false
        )
        let startingOrientation = establishedOrientation
        let targetOrientation = defaultPresentationOrientation
        hasEstablishedDefaultOrientation = true
        settledOrientation = targetOrientation
        settledZoom = ObservationScale.defaultOverviewZoom
        beginRenderInteraction()
        withAnimation(Motion.fieldReset) {
            zoom = settledZoom
        }
        guard transitionMotionEnabled else {
            orientation = settledOrientation
            recoverRenderDetails(after: 0.08)
            return
        }

        spatialMotionEvent &+= 1
        let event = spatialMotionEvent
        spatialInertiaActive = true
        Task { @MainActor in
            let start = Date()
            let duration = 0.46
            while true {
                guard event == spatialMotionEvent,
                      !orbitGestureActive,
                      !scaleGestureActive,
                      !rotationGestureActive
                else { return }
                let elapsed = Date().timeIntervalSince(start)
                let linear = min(1, max(0, elapsed / duration))
                let eased = linear * linear * (3 - 2 * linear)
                orientation = simd_slerp(
                    startingOrientation,
                    targetOrientation,
                    eased
                )
                if linear >= 1 { break }
                try? await Task.sleep(for: .seconds(SpatialMotion.frameInterval))
            }
            guard event == spatialMotionEvent else { return }
            orientation = targetOrientation
            settledOrientation = orientation
            spatialInertiaActive = false
            recoverRenderDetails(after: 0.08)
            scheduleShowcaseRotationResume()
        }
    }

    private func startOrbitInertia(angularVelocity: SIMD3<Double>) {
        startOrientationInertia(angularVelocity: angularVelocity, maximumSpeed: 4.2)
    }

    private func startOrientationInertia(
        angularVelocity: SIMD3<Double>,
        maximumSpeed: Double
    ) {
        let rawSpeed = simd_length(angularVelocity)
        let initialSpeed = min(maximumSpeed, rawSpeed)
        guard transitionMotionEnabled,
              initialSpeed > SpatialMotion.minimumAngularVelocity
        else {
            settledOrientation = orientation
            recoverRenderDetails(after: 0.08)
            emphasizeObserverLabel()
            scheduleShowcaseRotationResume()
            return
        }

        spatialMotionEvent &+= 1
        let event = spatialMotionEvent
        spatialInertiaActive = true
        beginRenderInteraction()

        Task { @MainActor in
            var velocity = angularVelocity * (initialSpeed / max(rawSpeed, 0.000_001))
            var previousDate = Date()

            while simd_length(velocity) > SpatialMotion.minimumAngularVelocity {
                try? await Task.sleep(for: .seconds(SpatialMotion.frameInterval))
                guard event == spatialMotionEvent,
                      !orbitGestureActive,
                      !scaleGestureActive,
                      !rotationGestureActive
                else { return }

                let now = Date()
                let deltaTime = min(
                    0.05,
                    max(0.008, now.timeIntervalSince(previousDate))
                )
                previousDate = now
                velocity *= SpatialMotion.decayFactor(
                    rate: SpatialMotion.rotationDecay,
                    deltaTime: deltaTime
                )
                let speed = simd_length(velocity)
                guard speed > 0 else { break }
                let delta = simd_quatd(
                    angle: speed * deltaTime,
                    axis: velocity / speed
                )
                orientation = simd_normalize(delta * orientation)
            }

            guard event == spatialMotionEvent else { return }
            settledOrientation = orientation
            spatialInertiaActive = false
            recoverRenderDetails(after: 0.1)
            emphasizeObserverLabel(after: 0.08)
            scheduleShowcaseRotationResume()
        }
    }

    private func startScaleInertia(logarithmicVelocity: Double) {
        guard transitionMotionEnabled,
              abs(logarithmicVelocity) > SpatialMotion.minimumScaleVelocity
        else {
            settledZoom = zoom
            recoverRenderDetails(after: 0.08)
            scheduleShowcaseRotationResume()
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
                      !scaleGestureActive,
                      !rotationGestureActive
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
                    lowerBound: Double(ObservationScale.minimumOverviewZoom),
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
                        ObservationScale.minimumOverviewZoom,
                        zoom * CGFloat(exp(velocity * deltaTime))
                    )
                )
            }

            guard event == spatialMotionEvent else { return }
            settledZoom = zoom
            spatialInertiaActive = false
            recoverRenderDetails(after: 0.1)
            scheduleShowcaseRotationResume()
        }
    }

    private func cancelSpatialInertia() {
        spatialMotionEvent &+= 1
        spatialInertiaActive = false
        settledOrientation = orientation
        settledZoom = zoom
    }

    private func pauseShowcaseRotation() {
        showcaseResumeEvent &+= 1
        showcaseRotation.pause(at: ProcessInfo.processInfo.systemUptime)
    }

    private func scheduleShowcaseRotationResume() {
        showcaseResumeEvent &+= 1
        let event = showcaseResumeEvent
        guard transitionMotionEnabled else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(OverviewShowcaseRotation.resumeDelay))
            guard event == showcaseResumeEvent,
                  !orbitGestureActive,
                  !scaleGestureActive,
                  !rotationGestureActive,
                  !spatialInertiaActive,
                  !clock.isTimeInteractionActive,
                  transitionMotionEnabled
            else { return }
            showcaseRotation.resume(
                at: ProcessInfo.processInfo.systemUptime,
                motionEnabled: true
            )
        }
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
                  !rotationGestureActive,
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

    nonisolated private static let identityOrientation = simd_quatd(
        angle: 0,
        axis: SIMD3(0, 0, 1)
    )

    /// 标准地球仪镜头：目标经纬度朝向观察者，当地东向映射为屏幕右侧，北向
    /// 映射为屏幕上方。全球页传入零纬度，使地轴完全位于屏幕竖直方向；绕极轴
    /// 旋转因此只会沿水平纬线展开，不会产生俯视转盘式的屏幕平面旋转。
    nonisolated static func presentationOrientation(
        latitude: Double,
        longitude: Double,
        siderealRadians: Double
    ) -> simd_quatd {
        let latitudeRadians = latitude * .pi / 180
        let longitudeRadians = longitude * .pi / 180 + siderealRadians
        let longitudeAlignment = simd_quatd(
            angle: -longitudeRadians,
            axis: SIMD3(0, 0, 1)
        )
        let latitudeAlignment = simd_quatd(
            angle: latitudeRadians - .pi / 2,
            axis: SIMD3(0, 1, 0)
        )
        let horizonAlignment = simd_quatd(
            angle: -.pi / 2,
            axis: SIMD3(0, 0, 1)
        )
        return simd_normalize(
            horizonAlignment * latitudeAlignment * longitudeAlignment
        )
    }

    /// 与旧投影次序一致：先经度、再俯仰、最后沿屏幕视轴滚转。
    nonisolated static func orientation(
        yaw: Double,
        pitch: Double,
        roll: Double
    ) -> simd_quatd {
        let yawRotation = simd_quatd(angle: yaw, axis: SIMD3(0, 1, 0))
        let pitchRotation = simd_quatd(angle: pitch, axis: SIMD3(1, 0, 0))
        let rollRotation = simd_quatd(angle: -roll, axis: SIMD3(0, 0, 1))
        return simd_normalize(rollRotation * pitchRotation * yawRotation)
    }

    /// Shoemake Arcball：把手指位置映射到虚拟球面，再由两条球面向量生成
    /// 唯一旋转四元数。越过极点时继续转动，不存在纬度夹紧或万向节死角。
    nonisolated static func arcballRotation(
        from start: CGPoint,
        to end: CGPoint,
        center: CGPoint,
        radius: CGFloat
    ) -> simd_quatd {
        let from = arcballVector(at: start, center: center, radius: radius)
        let to = arcballVector(at: end, center: center, radius: radius)
        let dot = min(1, max(-1, simd_dot(from, to)))
        let cross = simd_cross(from, to)
        let crossLength = simd_length(cross)
        guard crossLength > 0.000_001 else {
            if dot > 0 { return simd_quatd(angle: 0, axis: SIMD3(0, 0, 1)) }
            let fallback = abs(from.x) < 0.8
                ? simd_cross(from, SIMD3(1, 0, 0))
                : simd_cross(from, SIMD3(0, 1, 0))
            return simd_quatd(angle: .pi, axis: simd_normalize(fallback))
        }
        return simd_quatd(
            angle: acos(dot),
            axis: cross / crossLength
        )
    }

    nonisolated private static func arcballVector(
        at point: CGPoint,
        center: CGPoint,
        radius: CGFloat
    ) -> SIMD3<Double> {
        let safeRadius = max(1, Double(radius))
        let x = Double(point.x - center.x) / safeRadius
        let y = Double(center.y - point.y) / safeRadius
        let lengthSquared = x * x + y * y
        if lengthSquared <= 1 {
            return SIMD3(x, y, sqrt(max(0, 1 - lengthSquared)))
        }
        let scale = 1 / sqrt(lengthSquared)
        return SIMD3(x * scale, y * scale, 0)
    }

    nonisolated private static func arcballRadius(
        in size: CGSize,
        geometry: GlobeGeometry
    ) -> CGFloat {
        min(
            min(size.width, size.height) * 0.46,
            max(140, geometry.radius * CGFloat(maximumOrbitDisplayRadius))
        )
    }

    /// 方向回归测试仍使用屏幕位移语义；实际交互由 Arcball 四元数承担。
    nonisolated static func dragRotationDelta(
        translation: CGSize
    ) -> (yaw: Double, pitch: Double) {
        (
            yaw: Double(translation.width) * SpatialMotion.dragYawSensitivity,
            pitch: Double(translation.height) * SpatialMotion.dragPitchSensitivity
        )
    }

    nonisolated private static func shortestAngle(from start: Double, to end: Double) -> Double {
        var delta = (end - start).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return delta
    }

    /// 轨道点在静止、拖动、惯性和缩放阶段保持同一集合。交互期只收敛海岸线、
    /// 轨迹和光晕，不抽走卫星，避免点云在手指落下时产生跳变。
    nonisolated static func renderSampleDivisor(
        zoom _: CGFloat,
        interactionActive _: Bool
    ) -> Int {
        return 1
    }

    /// 微型卫星结构必须保持稀疏且稳定。策展对象始终保留；普通目录只在地球
    /// 外缘之外按 NORAD ID 确定性抽样，避免每帧随机闪烁或把大陆重新淹没。
    nonisolated static func showsSatelliteSignature(
        isCurated: Bool,
        noradId: Int,
        distanceSquared: CGFloat,
        earthRadiusSquared: CGFloat
    ) -> Bool {
        isCurated || (
            noradId.isMultiple(of: 89)
                && distanceSquared > earthRadiusSquared * 0.9216
        )
    }

    // MARK: - 三维投影

    struct GlobeGeometry {
        let center: CGPoint
        let radius: CGFloat
        let orientation: simd_quatd

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
        // 顶部模式栏与底部控制台之间以视觉中心而非屏幕数学中心排布。
        // 稍微下沉后，放大状态仍能给顶部留出呼吸，同时收掉下方无意义的空场。
        let preferredCenterY = size.height * 0.445
        let centerY = min(
            size.height - 174 - orbitalExtent,
            max(78 + orbitalExtent, preferredCenterY)
        )
        return GlobeGeometry(
            center: CGPoint(x: size.width / 2, y: centerY),
            radius: radius,
            orientation: simd_quatd(angle: 0, axis: SIMD3(0, 0, 1))
        )
    }

    private func renderedGeometry(
        in size: CGSize,
        at time: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> GlobeGeometry {
        let base = Self.globeGeometry(in: size)
        let scale = transitionMotionEnabled ? transitionVisuals.globeScale : 1
        let offset = transitionMotionEnabled
            ? size.height * transitionVisuals.globeVerticalOffset
            : 0
        return GlobeGeometry(
            center: CGPoint(x: base.center.x, y: base.center.y + offset),
            radius: base.radius * scale,
            orientation: renderedOrientation(at: time)
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
        roll: Double = 0,
        zoom: CGFloat
    ) -> Projected3D? {
        project(
            orbitalPosition: orbitalPosition,
            center: center,
            radius: radius,
            orientation: orientation(yaw: yaw, pitch: pitch, roll: roll),
            zoom: zoom
        )
    }

    nonisolated static func project(
        orbitalPosition: SIMD3<Double>,
        center: CGPoint,
        radius: CGFloat,
        orientation: simd_quatd,
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
            orientation: orientation,
            zoom: zoom
        )
    }

    /// 共享的单位方向投影；启动电影与全局页必须使用同一深度和屏幕坐标约定。
    nonisolated static func projectDirection(
        _ direction: SIMD3<Double>,
        displayRadius: Double,
        center: CGPoint,
        radius: CGFloat,
        orientation: simd_quatd,
        zoom: CGFloat
    ) -> Projected3D {
        let transformed = orientation.act(direction)
        let scale = Double(radius * zoom) * displayRadius
        return Projected3D(
            point: CGPoint(
                x: center.x + CGFloat(transformed.x * scale),
                y: center.y - CGFloat(transformed.y * scale)
            ),
            depth: transformed.z * displayRadius,
            displayRadius: displayRadius
        )
    }

    nonisolated private static func magnitude(of value: SIMD3<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }

    private func celestialProjectionKey(size: CGSize) -> BrightStarProjectionKey? {
        guard let celestialFrame, !brightStarStore.stars.isEmpty else { return nil }
        return BrightStarProjectionKey(
            frame: celestialFrame,
            size: size,
            catalogCount: brightStarStore.stars.count
        )
    }

    @MainActor
    private func updateBrightStarProjection(size: CGSize) async {
        guard let celestialFrame, !brightStarStore.stars.isEmpty else {
            projectedBrightStars = []
            return
        }
        let stars = brightStarStore.stars
        let projection = await Task.detached(priority: .userInitiated) {
            BrightStarProjector.project(
                stars: stars,
                frame: celestialFrame,
                size: size
            )
        }.value
        guard !Task.isCancelled else { return }
        projectedBrightStars = projection
    }

    // MARK: - 绘制

    /// Fixed inertial star field. All J2000 projection work is cached outside Canvas;
    /// this function only batches already projected ellipses by luminance and tint.
    private func drawBrightStarField(_ context: GraphicsContext) {
        guard !projectedBrightStars.isEmpty else { return }
        var faint = Path()
        var cool = Path()
        var neutral = Path()
        var warm = Path()
        var halo = Path()
        var glints = Path()

        for star in projectedBrightStars {
            let diameter = star.radius * 2
            let rect = CGRect(
                x: star.point.x - star.radius,
                y: star.point.y - star.radius,
                width: diameter,
                height: diameter
            )
            if star.opacity < 0.48 {
                faint.addEllipse(in: rect)
            } else if star.temperature > 0.22 {
                cool.addEllipse(in: rect)
            } else if star.temperature < -0.22 {
                warm.addEllipse(in: rect)
            } else {
                neutral.addEllipse(in: rect)
            }
            if star.radius > 1.05 {
                halo.addEllipse(in: rect.insetBy(dx: -2.2, dy: -2.2))
                let span = 2.1 + star.radius * 1.25
                glints.move(to: CGPoint(x: star.point.x - span, y: star.point.y))
                glints.addLine(to: CGPoint(x: star.point.x + span, y: star.point.y))
                glints.move(to: CGPoint(x: star.point.x, y: star.point.y - span * 0.62))
                glints.addLine(to: CGPoint(x: star.point.x, y: star.point.y + span * 0.62))
            }
        }

        context.fill(faint, with: .color(Palette.inkHigh.opacity(0.18)))
        context.fill(cool, with: .color(Color(red: 0.76, green: 0.86, blue: 1).opacity(0.62)))
        context.fill(neutral, with: .color(Palette.inkHigh.opacity(0.62)))
        context.fill(warm, with: .color(Color(red: 0.94, green: 0.86, blue: 0.7).opacity(0.6)))
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 2.4))
            glow.fill(halo, with: .color(Palette.inkHigh.opacity(0.08)))
        }
        context.stroke(
            glints,
            with: .color(Palette.inkHigh.opacity(0.26)),
            style: StrokeStyle(lineWidth: 0.38, lineCap: .round)
        )
    }

    /// 启动电影与全局页共用的球体环境光。调用方只提供几何和当前细节档位，
    /// 不读取会话、目录或任何可变业务状态。
    static func drawGlobeAmbient(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        zoom: CGFloat,
        simplified: Bool
    ) {
        let earthRadius = geometry.radius * zoom * CGFloat(Self.earthDisplayRadius)
        let shadowRect = CGRect(
            x: geometry.center.x - earthRadius * 0.72,
            y: geometry.center.y - earthRadius * 0.56,
            width: earthRadius * 1.72,
            height: earthRadius * 1.72
        )
        let auraRect = CGRect(
            x: geometry.center.x - earthRadius * 1.28,
            y: geometry.center.y - earthRadius * 1.28,
            width: earthRadius * 2.56,
            height: earthRadius * 2.56
        )
        context.drawLayer { shadow in
            shadow.addFilter(.blur(radius: simplified ? 16 : 28))
            shadow.fill(
                Path(ellipseIn: shadowRect),
                with: .color(Palette.voidEdge.opacity(0.7))
            )
        }
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: simplified ? 15 : 25))
            glow.fill(
                Path(ellipseIn: auraRect),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Palette.observationTint.opacity(0.045), location: 0.42),
                        .init(color: Palette.signal.opacity(0.012), location: 0.72),
                        .init(color: .clear, location: 1),
                    ]),
                    center: CGPoint(
                        x: geometry.center.x - earthRadius * 0.22,
                        y: geometry.center.y - earthRadius * 0.2
                    ),
                    startRadius: earthRadius * 0.45,
                    endRadius: earthRadius * 1.28
                )
            )
        }

        // 只在受光侧保留两段极细大气辉光，不用完整外圈包住地球。
        var corona = Path()
        corona.addArc(
            center: geometry.center,
            radius: earthRadius + 2.2,
            startAngle: .degrees(138),
            endAngle: .degrees(305),
            clockwise: false
        )
        context.stroke(
            corona,
            with: .color(Palette.observationTint.opacity(0.18)),
            style: StrokeStyle(lineWidth: 0.78, lineCap: .round)
        )
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
                orientation: geometry.orientation,
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
        geometry: GlobeGeometry,
        front: Bool,
        simplified: Bool
    ) {
        Self.drawGlobeSatelliteField(
            context,
            projected: samples.lazy
                .filter { $0.object.id != focusedObjectId }
                .map(\.projected),
            geometry: geometry,
            zoom: zoom,
            front: front,
            simplified: simplified
        )
        guard front else { return }
        drawSatelliteSignatures(
            context,
            samples: samples,
            geometry: geometry,
            simplified: simplified
        )
    }

    /// 纯投影点云的共同分层规则。全局页传入真实 ECI 投影，启动电影传入
    /// 确定性解析轨道投影；两处由同一份代码决定遮挡、亮度和前后景层次。
    static func drawGlobeSatelliteField<S: Sequence>(
        _ context: GraphicsContext,
        projected: S,
        geometry: GlobeGeometry,
        zoom: CGFloat,
        front: Bool,
        simplified: Bool,
        tint: Color = Palette.networkTint,
        emphasis: Double = 1
    ) where S.Element == Projected3D {
        var rearShell: [CGPoint] = []
        var globeCrossing: [CGPoint] = []
        var orbitalShell: [CGPoint] = []
        var foreground: [CGPoint] = []
        let estimatedCount = projected.underestimatedCount
        rearShell.reserveCapacity(estimatedCount / 2)
        globeCrossing.reserveCapacity(estimatedCount / 5)
        orbitalShell.reserveCapacity(estimatedCount / 3)
        foreground.reserveCapacity(estimatedCount / 8)

        let earthRadius = geometry.radius * zoom * CGFloat(Self.earthDisplayRadius)
        let earthRadiusSquared = earthRadius * earthRadius

        for sample in projected {
            guard (sample.depth >= 0) == front else { continue }
            guard front else {
                rearShell.append(sample.point)
                continue
            }

            let dx = sample.point.x - geometry.center.x
            let dy = sample.point.y - geometry.center.y
            let distanceSquared = dx * dx + dy * dy
            let crossesGlobe = distanceSquared < earthRadiusSquared * 0.970_225
            let normalizedDepth = sample.depth / max(0.001, sample.displayRadius)
            if crossesGlobe {
                globeCrossing.append(sample.point)
            } else if normalizedDepth > 0.52 {
                foreground.append(sample.point)
            } else {
                orbitalShell.append(sample.point)
            }
        }

        if !front {
            SkyRenderer.drawTargetField(
                context,
                points: rearShell,
                tint: tint,
                opacity: 0.095 * emphasis,
                coreRadius: 0.3,
                haloStrength: 0
            )
            return
        }

        // 穿过地球盘面的前景卫星仍然保留真实位置，但退成极细的测量点，
        // 不再与大陆点阵争夺主层级。
        SkyRenderer.drawTargetField(
            context,
            points: globeCrossing,
            tint: tint,
            opacity: 0.16 * emphasis,
            coreRadius: 0.31,
            haloStrength: 0
        )
        SkyRenderer.drawTargetField(
            context,
            points: orbitalShell,
            tint: tint,
            opacity: 0.3 * emphasis,
            coreRadius: 0.43,
            haloStrength: 0
        )
        SkyRenderer.drawTargetField(
            context,
            points: foreground,
            tint: Palette.inkHigh,
            opacity: 0.5 * emphasis,
            coreRadius: 0.62,
            haloStrength: simplified ? 0 : 0.018
        )
    }

    /// 在数千颗真实星核之上只为稳定子集增加 3–5pt 人造结构。轮廓按任务语义
    /// 批量合并为固定数量的 Path，不为每颗卫星创建 SwiftUI 图层。
    private func drawSatelliteSignatures(
        _ context: GraphicsContext,
        samples: [RenderSample],
        geometry: GlobeGeometry,
        simplified: Bool
    ) {
        guard !simplified else { return }
        var network = Path()
        var navigation = Path()
        var observation = Path()
        var science = Path()
        var legacy = Path()

        var cores = Path()
        var coreClearance = Path()
        let earthRadius = geometry.radius * zoom * CGFloat(Self.earthDisplayRadius)
        let earthRadiusSquared = earthRadius * earthRadius

        for sample in samples where sample.projected.depth > 0.08 {
            let object = sample.object
            // 许多普通节点也能生成通用档案，不能因此全部升级成重点符号。
            // 只有人工策展任务与稀疏确定性样本获得完整微型轮廓。
            let isLandmark = object.isCurated
            let screenDX = sample.projected.point.x - geometry.center.x
            let screenDY = sample.projected.point.y - geometry.center.y
            let distanceSquared = screenDX * screenDX + screenDY * screenDY
            guard Self.showsSatelliteSignature(
                isCurated: isLandmark,
                noradId: object.noradId,
                distanceSquared: distanceSquared,
                earthRadiusSquared: earthRadiusSquared
            )
            else { continue }

            let point = sample.projected.point
            var radial = CGVector(
                dx: point.x - geometry.center.x,
                dy: point.y - geometry.center.y
            )
            let radialLength = max(0.001, sqrt(distanceSquared))
            radial.dx /= radialLength
            radial.dy /= radialLength
            let tangent = CGVector(dx: -radial.dy, dy: radial.dx)
            let extent: CGFloat = isLandmark ? 4.7 : 3.8

            func offset(_ vector: CGVector, by amount: CGFloat) -> CGPoint {
                CGPoint(
                    x: point.x + vector.dx * amount,
                    y: point.y + vector.dy * amount
                )
            }

            func addPanels(to path: inout Path, extent: CGFloat) {
                path.move(to: offset(tangent, by: 1.45))
                path.addLine(to: offset(tangent, by: extent))
                path.move(to: offset(tangent, by: -1.45))
                path.addLine(to: offset(tangent, by: -extent))
            }

            let coreRect = CGRect(
                x: point.x - 0.86,
                y: point.y - 0.86,
                width: 1.72,
                height: 1.72
            )
            cores.addEllipse(in: coreRect)
            coreClearance.addEllipse(in: coreRect.insetBy(dx: -1.15, dy: -1.15))

            switch SkyRenderer.satelliteSignature(for: object) {
            case .network:
                addPanels(to: &network, extent: extent)
            case .navigation:
                addPanels(to: &navigation, extent: extent * 0.8)
                navigation.move(to: offset(radial, by: 1.45))
                navigation.addLine(to: offset(radial, by: 3.35))
            case .observation:
                addPanels(to: &observation, extent: extent * 0.72)
                observation.move(to: offset(radial, by: -1.4))
                observation.addLine(to: offset(radial, by: -3.1))
            case .science:
                addPanels(to: &science, extent: extent * 0.84)
                science.move(to: offset(radial, by: -2.5))
                science.addLine(to: offset(radial, by: 2.5))
            case .legacy:
                legacy.move(to: offset(tangent, by: 1.5))
                legacy.addLine(to: offset(tangent, by: extent * 0.68))
            }
        }

        let clearanceStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        let style = StrokeStyle(lineWidth: 0.62, lineCap: .round, lineJoin: .round)
        for path in [network, navigation, observation, science, legacy] {
            context.stroke(
                path,
                with: .color(Palette.voidBlack.opacity(0.72)),
                style: clearanceStyle
            )
        }
        context.fill(coreClearance, with: .color(Palette.voidBlack.opacity(0.74)))
        context.fill(cores, with: .color(Palette.inkHigh.opacity(0.9)))
        context.stroke(network, with: .color(Palette.networkTint.opacity(0.68)), style: style)
        context.stroke(navigation, with: .color(Palette.signal.opacity(0.7)), style: style)
        context.stroke(observation, with: .color(Palette.observationTint.opacity(0.72)), style: style)
        context.stroke(science, with: .color(Palette.explorationTint.opacity(0.7)), style: style)
        context.stroke(legacy, with: .color(Palette.legacyTint.opacity(0.52)), style: style)
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

    private func drawAmbientSpatialTrails(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        front: Bool
    ) {
        guard ambientTrailsVisible, !renderingSimplified else { return }

        for object in session.overviewTrailObjects where object.id != focusedObjectId {
            guard let spatialPoints = ambientTrails.spatialTrails[object.id],
                  spatialPoints.count > 1
            else { continue }
            let projected = spatialPoints.compactMap { point -> (Projected3D, TimeInterval)? in
                guard let projection = Self.project(
                    orbitalPosition: point.position,
                    center: geometry.center,
                    radius: geometry.radius,
                    orientation: geometry.orientation,
                    zoom: zoom
                ) else { return nil }
                return (projection, point.at)
            }
            let amplified = OverviewAmbientTrailPolicy.amplifiedScreenPoints(
                projected.map { $0.0.point }
            )
            guard amplified.count == projected.count else { continue }

            var segment: [TrailStore.TrailPoint] = []
            for index in projected.indices {
                if (projected[index].0.depth >= 0) == front {
                    segment.append(
                        TrailStore.TrailPoint(
                            point: amplified[index],
                            at: projected[index].1
                        )
                    )
                } else {
                    drawAmbientTrailSegment(
                        context,
                        points: segment,
                        tint: object.identityTint,
                        front: front
                    )
                    segment.removeAll(keepingCapacity: true)
                }
            }
            drawAmbientTrailSegment(
                context,
                points: segment,
                tint: object.identityTint,
                front: front
            )
        }
    }

    private func drawAmbientTrailSegment(
        _ context: GraphicsContext,
        points: [TrailStore.TrailPoint],
        tint: Color,
        front: Bool
    ) {
        guard points.count > 1 else { return }
        SkyRenderer.drawTrail(
            context,
            points: points,
            frameTime: frameTime,
            tint: tint,
            intensity: front ? 0.72 : 0.16,
            lifetime: ambientTrails.trailLifetime
        )
    }

    private func drawSpatialTrails(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        front: Bool,
        simplified: Bool
    ) {
        // Thousands of simultaneous histories turn the globe into an unreadable wire cage.
        // Satellite cores carry population density; a spatial trail is reserved for the
        // object the user is actually following, so land, observer and visibility stay legible.
        guard let focusedObjectId,
              let object = session.catalog.objectsByID[focusedObjectId],
              let spatialPoints = trails.spatialTrails[focusedObjectId],
              spatialPoints.count > 1
        else { return }
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
                orientation: geometry.orientation,
                zoom: zoom
            ) else { return nil }
            return (projection, point.at)
        }
        let tint = object.identityTint
        var segment: [TrailStore.TrailPoint] = []
        for item in projected {
            if (item.0.depth >= 0) == front {
                segment.append(TrailStore.TrailPoint(point: item.0.point, at: item.1))
            } else {
                drawTrailSegment(
                    context,
                    points: segment,
                    tint: tint,
                    front: front
                )
                segment.removeAll(keepingCapacity: true)
            }
        }
        drawTrailSegment(
            context,
            points: segment,
            tint: tint,
            front: front
        )
    }

    private func drawTrailSegment(
        _ context: GraphicsContext,
        points: [TrailStore.TrailPoint],
        tint: Color,
        front: Bool
    ) {
        guard points.count > 1 else { return }
        SkyRenderer.drawTrail(
            context,
            points: points,
            frameTime: frameTime,
            tint: tint,
            intensity: front ? 1.0 : 0.3,
            lifetime: trails.trailLifetime
        )
    }

    private func drawEarth(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        simplified: Bool
    ) {
        let siderealRadians = zeroMeanSiderealTime(
            julianDate: observation.julianDate
        ) * .pi / 180
        Self.drawGlobeSurface(
            context,
            geometry: geometry,
            zoom: zoom,
            siderealRadians: siderealRadians,
            landDots: coastlineStore.landDots,
            detailedCoastlines: coastlineStore.coastlines,
            fallbackCoastlines: Self.coastlineSamples,
            presence: surfaceDetailPresence,
            simplified: simplified
        )
        let earthRadius = geometry.radius * zoom * Self.earthDisplayRadius
        let earthRect = CGRect(
            x: geometry.center.x - earthRadius,
            y: geometry.center.y - earthRadius,
            width: earthRadius * 2,
            height: earthRadius * 2
        )
        drawObserverVisibilityRegion(
            context,
            geometry: geometry,
            earthPath: Path(ellipseIn: earthRect),
            simplified: simplified,
            presence: surfaceDetailPresence
        )
    }

    /// 与具体会话解耦的地球表面绘制入口。启动电影和全局页共享材质、点阵大陆、
    /// 经纬网与轮廓；资源尚未准备好时，两者都使用同一份编译期海岸线回退。
    static func drawGlobeSurface(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        zoom: CGFloat,
        siderealRadians: Double,
        landDots: [EarthLandDot],
        detailedCoastlines: [[SIMD2<Float>]],
        fallbackCoastlines: [[Float]],
        presence: Double,
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
            atmosphere.addFilter(.blur(radius: 8))
            atmosphere.stroke(
                Path(ellipseIn: earthRect.insetBy(dx: -3.2, dy: -3.2)),
                with: .color(Palette.observationTint.opacity(0.14)),
                style: StrokeStyle(lineWidth: 3.8)
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

        // 单一方向光把球体从“圆形底板”提升为具有体积的观测对象。光照只作用于
        // 地表底色，不改变卫星、轨道和功能色的既有语义。
        context.drawLayer { lighting in
            lighting.clip(to: earth)
            lighting.fill(
                earth,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(
                            color: Palette.observationTint.opacity(0.055),
                            location: 0
                        ),
                        .init(
                            color: Palette.voidBlack.opacity(0.02),
                            location: 0.46
                        ),
                        .init(
                            color: Palette.voidBlack.opacity(0.34),
                            location: 1
                        ),
                    ]),
                    startPoint: CGPoint(
                        x: earthRect.minX + earthRadius * 0.24,
                        y: earthRect.minY + earthRadius * 0.18
                    ),
                    endPoint: CGPoint(
                        x: earthRect.maxX - earthRadius * 0.08,
                        y: earthRect.maxY - earthRadius * 0.02
                    )
                )
            )
        }

        drawEarthSurfaceMaterial(
            context,
            earth: earth,
            earthRect: earthRect,
            earthRadius: earthRadius,
            simplified: simplified
        )

        drawEarthGrid(
            context,
            geometry: geometry,
            zoom: zoom,
            presence: presence,
            simplified: simplified
        )
        if landDots.isEmpty {
            drawEarthCoastlines(
                context,
                geometry: geometry,
                zoom: zoom,
                siderealRadians: siderealRadians,
                detailedCoastlines: detailedCoastlines,
                fallbackCoastlines: fallbackCoastlines,
                presence: presence,
                simplified: simplified
            )
        } else {
            drawEarthLandDots(
                context,
                geometry: geometry,
                zoom: zoom,
                siderealRadians: siderealRadians,
                landDots: landDots,
                presence: presence
            )
        }
        context.stroke(
            Path(ellipseIn: earthRect.insetBy(dx: -1.45, dy: -1.45)),
            with: .color(Palette.observationTint.opacity(simplified ? 0.1 : 0.16)),
            style: StrokeStyle(lineWidth: 0.46)
        )
    }

    /// 前景卫星绘制完成后重新压住地球边缘。深色底线清出物理遮挡关系，
    /// 受光侧的短弧再给出大气层厚度，避免高密度轨道点把球体轮廓咬碎。
    static func drawGlobeForegroundRim(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        zoom: CGFloat,
        presence: Double
    ) {
        guard presence > 0.01 else { return }
        let earthRadius = geometry.radius * zoom * Self.earthDisplayRadius
        let earthRect = CGRect(
            x: geometry.center.x - earthRadius,
            y: geometry.center.y - earthRadius,
            width: earthRadius * 2,
            height: earthRadius * 2
        )
        let earth = Path(ellipseIn: earthRect)
        context.stroke(
            earth,
            with: .color(Palette.voidBlack.opacity(0.84 * presence)),
            style: StrokeStyle(lineWidth: 2.35)
        )
        context.stroke(
            earth,
            with: .color(Palette.inkMid.opacity(0.47 * presence)),
            style: StrokeStyle(lineWidth: 0.68)
        )

        var illuminatedLimb = Path()
        illuminatedLimb.addArc(
            center: geometry.center,
            radius: earthRadius - 0.3,
            startAngle: .degrees(192),
            endAngle: .degrees(310),
            clockwise: false
        )
        context.stroke(
            illuminatedLimb,
            with: .color(Palette.inkHigh.opacity(0.34 * presence)),
            style: StrokeStyle(lineWidth: 0.86, lineCap: .round)
        )
    }

    /// 用海面高光、柔和昼夜分界与内侧大气边缘建立球体体积。它们全部裁切在
    /// 同一个 Canvas 图层内，不引入纹理贴图，也不会在拖动时改变几何复杂度。
    private static func drawEarthSurfaceMaterial(
        _ context: GraphicsContext,
        earth: Path,
        earthRect: CGRect,
        earthRadius: CGFloat,
        simplified: Bool
    ) {
        context.drawLayer { surface in
            surface.clip(to: earth)

            // 海面并非纯色圆盘：受光侧有一块宽而克制的反射，中心保持深黑。
            surface.fill(
                earth,
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Palette.inkHigh.opacity(simplified ? 0.025 : 0.045), location: 0),
                        .init(color: Palette.observationTint.opacity(0.018), location: 0.38),
                        .init(color: .clear, location: 0.76),
                    ]),
                    center: CGPoint(
                        x: earthRect.minX + earthRadius * 0.58,
                        y: earthRect.minY + earthRadius * 0.48
                    ),
                    startRadius: 0,
                    endRadius: earthRadius * 0.92
                )
            )

            // 椭圆形暗部形成柔和的 terminator，而不是把球体简单做成径向渐变圆。
            let nightRect = CGRect(
                x: earthRect.midX + earthRadius * 0.16,
                y: earthRect.minY - earthRadius * 0.08,
                width: earthRadius * 1.34,
                height: earthRadius * 2.16
            )
            surface.addFilter(.blur(radius: simplified ? 7 : 10))
            surface.fill(
                Path(ellipseIn: nightRect),
                with: .color(Palette.voidBlack.opacity(simplified ? 0.22 : 0.3))
            )
        }

        // 内侧大气边缘仅在受光半球可见，避免再画一圈完整装饰环。
        var innerAtmosphere = Path()
        innerAtmosphere.addArc(
            center: CGPoint(x: earthRect.midX, y: earthRect.midY),
            radius: earthRadius - 1.25,
            startAngle: .degrees(132),
            endAngle: .degrees(302),
            clockwise: false
        )
        context.stroke(
            innerAtmosphere,
            with: .color(Palette.observationTint.opacity(simplified ? 0.14 : 0.2)),
            style: StrokeStyle(lineWidth: 1.15, lineCap: .round)
        )
    }

    /// 大陆在构建期被采样成近似等面积的点阵。Canvas 每帧只旋转预计算的
    /// 单位球方向并合并为六条 Path；不做多边形判断，也不逐段描摹复杂海岸线。
    /// 海岸邻近点更小、更亮，内陆点稍大、更安静，兼顾轮廓精度与陆地体量。
    private static func drawEarthLandDots(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        zoom: CGFloat,
        siderealRadians: Double,
        landDots: [EarthLandDot],
        presence: Double
    ) {
        guard presence > 0.01 else { return }
        let earthRotation = simd_quatd(
            angle: siderealRadians,
            axis: SIMD3(0, 0, 1)
        )
        let surfaceOrientation = simd_normalize(geometry.orientation * earthRotation)

        var coastal = Path()
        var coastalRim = Path()
        var nearCoastal = Path()
        var nearCoastalRim = Path()
        var interior = Path()
        var interiorRim = Path()

        for dot in landDots {
            let direction = SIMD3(
                Double(dot.direction.x),
                Double(dot.direction.y),
                Double(dot.direction.z)
            )
            let projected = Self.projectDirection(
                direction,
                displayRadius: Self.earthDisplayRadius,
                center: geometry.center,
                radius: geometry.radius,
                orientation: surfaceOrientation,
                zoom: zoom
            )
            guard projected.depth >= 0.012 else { continue }
            let nearHorizon = projected.depth < Self.earthDisplayRadius * 0.24
            let diameter = Self.landDotDiameter(
                sizeClass: dot.sizeClass,
                zoom: zoom,
                nearHorizon: nearHorizon
            )
            let rect = CGRect(
                x: projected.point.x - diameter / 2,
                y: projected.point.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            switch (dot.sizeClass, nearHorizon) {
            case (0, false): coastal.addEllipse(in: rect)
            case (0, true): coastalRim.addEllipse(in: rect)
            case (1, false): nearCoastal.addEllipse(in: rect)
            case (1, true): nearCoastalRim.addEllipse(in: rect)
            case (_, false): interior.addEllipse(in: rect)
            case (_, true): interiorRim.addEllipse(in: rect)
            }
        }

        context.fill(
            interior,
            with: .color(Palette.observationTint.opacity(0.25 * presence))
        )
        context.fill(
            interiorRim,
            with: .color(Palette.observationTint.opacity(0.1 * presence))
        )
        context.fill(
            nearCoastal,
            with: .color(Palette.observationTint.opacity(0.34 * presence))
        )
        context.fill(
            nearCoastalRim,
            with: .color(Palette.observationTint.opacity(0.15 * presence))
        )
        context.fill(
            coastal,
            with: .color(Palette.inkHigh.opacity(0.62 * presence))
        )
        context.fill(
            coastalRim,
            with: .color(Palette.inkHigh.opacity(0.22 * presence))
        )
    }

    nonisolated static func landDotDiameter(
        sizeClass: UInt8,
        zoom: CGFloat,
        nearHorizon: Bool
    ) -> CGFloat {
        let base: CGFloat = switch sizeClass {
        case 0: 0.68
        case 1: 0.92
        default: 1.16
        }
        let zoomScale = min(1.34, max(0.84, sqrt(zoom)))
        return base * zoomScale * (nearHorizon ? 0.76 : 1)
    }

    private static func drawEarthGrid(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        zoom: CGFloat,
        presence: Double,
        simplified: Bool
    ) {
        let tint = Palette.inkLow.opacity(
            (simplified ? 0.06 : 0.09) * presence
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
                    orientation: geometry.orientation,
                    zoom: zoom
                )
            }
            strokeGlobeSegments(context, projected: points, front: true, color: tint)
            if !simplified {
                strokeGlobeSegments(
                    context,
                    projected: points,
                    front: true,
                    color: Palette.inkMid.opacity(0.045 * presence),
                    minimumFrontDepth: Self.earthDisplayRadius * 0.34
                )
            }
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
                    orientation: geometry.orientation,
                    zoom: zoom
                )
            }
            strokeGlobeSegments(context, projected: points, front: true, color: tint)
            if !simplified {
                strokeGlobeSegments(
                    context,
                    projected: points,
                    front: true,
                    color: Palette.inkMid.opacity(0.045 * presence),
                    minimumFrontDepth: Self.earthDisplayRadius * 0.34
                )
            }
        }
    }

    private static func drawEarthCoastlines(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        zoom: CGFloat,
        siderealRadians: Double,
        detailedCoastlines: [[SIMD2<Float>]],
        fallbackCoastlines: [[Float]],
        presence: Double,
        simplified: Bool
    ) {
        if Self.usesDetailedCoastlines(
            renderingSimplified: simplified,
            resourceAvailable: !detailedCoastlines.isEmpty
        ) {
            for coastline in detailedCoastlines {
                let projected = stride(
                    from: 0,
                    to: coastline.count,
                    by: 1
                ).map { index in
                    let coordinate = coastline[index]
                    let direction = Self.sphericalSurfaceDirection(
                        latitude: Double(coordinate.x),
                        longitude: Double(coordinate.y),
                        siderealRadians: siderealRadians
                    )
                    return Self.projectDirection(
                        direction,
                        displayRadius: Self.earthDisplayRadius,
                        center: geometry.center,
                        radius: geometry.radius,
                        orientation: geometry.orientation,
                        zoom: zoom
                    )
                }
                strokeGlobeCoastline(
                    context,
                    projected: projected,
                    presence: presence,
                    simplified: false
                )
            }
            return
        }

        // 交互时持续绘制完整的编译期基础轮廓；静止后才替换为资源中的高精度海岸线。
        // 这样缩放、Arcball 与惯性期间不会出现“无大陆”的空白球体。
        for coastline in fallbackCoastlines {
            let projected = stride(
                from: 0,
                to: coastline.count - 1,
                by: 2
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
                    orientation: geometry.orientation,
                    zoom: zoom
                )
            }
            strokeGlobeCoastline(
                context,
                projected: projected,
                presence: presence,
                simplified: false
            )
        }
    }

    nonisolated static func usesDetailedCoastlines(
        renderingSimplified: Bool,
        resourceAvailable: Bool
    ) -> Bool {
        !renderingSimplified && resourceAvailable
    }

    private static func strokeGlobeCoastline(
        _ context: GraphicsContext,
        projected: [Projected3D],
        presence: Double,
        simplified: Bool
    ) {
        // 极细暗底把海岸从经纬线中分离出来，仍保持地图是轨道空间的背景。
        strokeGlobeSegments(
            context,
            projected: projected,
            front: true,
            color: Palette.voidBlack.opacity(
                (simplified ? 0.24 : 0.42) * presence
            ),
            style: StrokeStyle(
                lineWidth: simplified ? 0.9 : 1.25,
                lineCap: .round,
                lineJoin: .round
            )
        )
        strokeGlobeSegments(
            context,
            projected: projected,
            front: true,
            color: Palette.observationTint.opacity(
                (simplified ? 0.16 : 0.2) * presence
            ),
            style: StrokeStyle(
                lineWidth: simplified ? 0.4 : 0.56,
                lineCap: .round,
                lineJoin: .round
            )
        )
        if !simplified {
            strokeGlobeSegments(
                context,
                projected: projected,
                front: true,
                color: Palette.inkHigh.opacity(0.23 * presence),
                style: StrokeStyle(lineWidth: 0.42, lineCap: .round, lineJoin: .round),
                minimumFrontDepth: Self.earthDisplayRadius * 0.28
            )
        }
    }

    private static func strokeGlobeSegments(
        _ context: GraphicsContext,
        projected: [Projected3D],
        front: Bool,
        color: Color,
        style: StrokeStyle = StrokeStyle(lineWidth: 0.42),
        minimumFrontDepth: Double = 0
    ) {
        var path = Path()
        var drawing = false
        for point in projected {
            let matches = (point.depth >= 0) == front
                && (!front || point.depth >= minimumFrontDepth)
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

    /// 默认可见区域是一块真正贴在球面的球冠，而不是屏幕坐标中的平面圆。
    private func drawObserverVisibilityRegion(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        earthPath: Path,
        simplified: Bool,
        presence: Double
    ) {
        guard presence > 0.01,
              let centerProjection = observerProjection(geometry: geometry),
              let ring = observerVisibilityRing(
                  geometry: geometry,
                  sampleCount: simplified ? 28 : 56,
                  angularRadiusDegrees: 28
              )
        else { return }
        guard centerProjection.depth > -0.02 else { return }

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
                            (simplified ? 0.045 : 0.068) * presence
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
                (simplified ? 0.17 : 0.28) * presence
            ),
            style: StrokeStyle(
                lineWidth: simplified ? 0.42 : 0.54,
                lineCap: .round,
                dash: [1.1, 2.8]
            )
        )
    }

    /// 可见范围的面填充留在地球表面，轮廓则在卫星层之上再描一次。
    /// 深色底线先清出一圈视觉缝隙，避免高密度卫星把地表范围切碎。
    private func drawObserverVisibilityOverlay(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        simplified: Bool
    ) {
        guard surfaceDetailPresence > 0.01,
              let ring = observerVisibilityRing(
                  geometry: geometry,
                  sampleCount: simplified ? 32 : 64,
                  angularRadiusDegrees: 28
              )
        else { return }

        strokeSegments(
            context,
            projected: ring,
            front: true,
            color: Palette.voidBlack.opacity(0.82 * surfaceDetailPresence),
            style: StrokeStyle(
                lineWidth: simplified ? 1.18 : 1.38,
                lineCap: .round
            )
        )
        strokeSegments(
            context,
            projected: ring,
            front: true,
            color: Palette.signal.opacity(
                (simplified ? 0.5 : 0.62) * surfaceDetailPresence
            ),
            style: StrokeStyle(
                lineWidth: simplified ? 0.56 : 0.66,
                lineCap: .round,
                dash: [1.1, 2.8]
            )
        )

        if !simplified,
           let innerRing = observerVisibilityRing(
               geometry: geometry,
               sampleCount: 64,
               angularRadiusDegrees: 25.5
           ) {
            strokeSegments(
                context,
                projected: innerRing,
                front: true,
                color: Palette.observationTint.opacity(
                    0.2 * surfaceDetailPresence
                ),
                style: StrokeStyle(
                    lineWidth: 0.34,
                    lineCap: .round,
                    dash: [0.7, 3.6]
                )
            )

            var calibrationTicks = Path()
            let uniqueCount = max(0, ring.count - 1)
            let tickStride = max(1, uniqueCount / 12)
            if uniqueCount >= 3 {
                for index in stride(from: 0, to: uniqueCount, by: tickStride) {
                    let sample = ring[index]
                    guard sample.depth >= 0 else { continue }
                    let previous = ring[(index - 1 + uniqueCount) % uniqueCount].point
                    let next = ring[(index + 1) % uniqueCount].point
                    let dx = next.x - previous.x
                    let dy = next.y - previous.y
                    let length = max(0.001, hypot(dx, dy))
                    let normalX = -dy / length
                    let normalY = dx / length
                    let halfLength: CGFloat = 1.7
                    calibrationTicks.move(to: CGPoint(
                        x: sample.point.x - normalX * halfLength,
                        y: sample.point.y - normalY * halfLength
                    ))
                    calibrationTicks.addLine(to: CGPoint(
                        x: sample.point.x + normalX * halfLength,
                        y: sample.point.y + normalY * halfLength
                    ))
                }
            }
            context.stroke(
                calibrationTicks,
                with: .color(
                    Palette.inkHigh.opacity(0.36 * surfaceDetailPresence)
                ),
                style: StrokeStyle(lineWidth: 0.46, lineCap: .round)
            )
        }

        let labelPresence = transitionVisuals.chromePresence
        guard !simplified,
              observerLabelEmphasized,
              labelPresence > 0.01,
              let labelAnchor = ring
                  .filter({ $0.depth >= 0 })
                  .min(by: { $0.point.y < $1.point.y })
        else { return }
        let labelCenter = CGPoint(x: labelAnchor.point.x, y: labelAnchor.point.y - 13)
        let labelRect = CGRect(
            x: labelCenter.x - 30,
            y: labelCenter.y - 8,
            width: 60,
            height: 16
        )
        let labelShape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            .path(in: labelRect)
        context.fill(labelShape, with: .color(Palette.voidBlack.opacity(0.78)))
        context.stroke(
            labelShape,
            with: .color(Palette.signal.opacity(0.34 * labelPresence)),
            style: StrokeStyle(lineWidth: 0.5)
        )
        context.draw(
            Text(L10n.text("overview.visibility.default"))
                .font(Typography.statusTag)
                .tracking(0.5)
                .foregroundStyle(Palette.inkHigh.opacity(0.82 * labelPresence)),
            at: labelCenter,
            anchor: .center
        )
    }

    private func observerVisibilityRing(
        geometry: GlobeGeometry,
        sampleCount: Int,
        angularRadiusDegrees: Double
    ) -> [Projected3D]? {
        guard let up = observerSurfaceDirection() else { return nil }
        var tangent = simd_cross(SIMD3<Double>(0, 0, 1), up)
        if simd_length(tangent) < 1e-6 {
            tangent = SIMD3(1, 0, 0)
        } else {
            tangent = simd_normalize(tangent)
        }
        let bitangent = simd_normalize(simd_cross(up, tangent))
        let angularRadius = angularRadiusDegrees * Double.pi / 180
        return (0 ... sampleCount).map { index in
            let angle = Double(index) / Double(sampleCount) * 2 * Double.pi
            let surfaceDirection = up * cos(angularRadius)
                + (tangent * cos(angle) + bitangent * sin(angle)) * sin(angularRadius)
            return Self.projectDirection(
                surfaceDirection,
                displayRadius: Self.earthDisplayRadius,
                center: geometry.center,
                radius: geometry.radius,
                orientation: geometry.orientation,
                zoom: zoom
            )
        }
    }

    /// 观察者标记在真实地表位置：呼吸定位环、坐标核心和外向刻度组成仪器符号，
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
        let alpha = (simplified ? 0.9 : 1.0) * surfaceDetailPresence
        guard alpha > 0.01 else { return }
        let motionEnabled = transitionMotionEnabled && !simplified
        let breath = motionEnabled
            ? CGFloat((sin(motionTime * 2.15) + 1) * 0.5)
            : 0
        let pulseProgress = motionEnabled
            ? CGFloat(motionTime.truncatingRemainder(dividingBy: 2.8) / 2.8)
            : 0.38
        let ringRadius: CGFloat = 5.8 + breath * 0.65
        let pulseRadius: CGFloat = 8.2 + pulseProgress * 5.6
        let pulseOpacity = motionEnabled
            ? Double((1 - pulseProgress) * (1 - pulseProgress)) * 0.42
            : 0.14

        // 地表定位符始终位于点云之上；先清出一枚低调暗盘，保证它不会被卫星
        // 光核切碎，同时仍能看到下面的大陆和视域轮廓关系。
        context.fill(
            Path(ellipseIn: CGRect(
                x: point.x - 9,
                y: point.y - 9,
                width: 18,
                height: 18
            )),
            with: .color(Palette.voidBlack.opacity(0.78 * alpha))
        )

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
                    with: .color(Palette.signal.opacity(0.22 * alpha))
                )
            }
        }
        context.stroke(
            Path(ellipseIn: CGRect(
                x: point.x - pulseRadius,
                y: point.y - pulseRadius,
                width: pulseRadius * 2,
                height: pulseRadius * 2
            )),
            with: .color(Palette.signal.opacity(pulseOpacity * alpha)),
            style: StrokeStyle(lineWidth: 0.58, lineCap: .round)
        )
        context.stroke(
            Path(ellipseIn: CGRect(
                x: point.x - ringRadius,
                y: point.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )),
            with: .color(Palette.signal.opacity(0.76 * alpha)),
            style: StrokeStyle(
                lineWidth: 0.68,
                lineCap: .round
            )
        )

        var coordinateTicks = Path()
        let tickInner: CGFloat = 7.6
        let tickOuter: CGFloat = 10
        coordinateTicks.move(to: CGPoint(x: point.x, y: point.y - tickOuter))
        coordinateTicks.addLine(to: CGPoint(x: point.x, y: point.y - tickInner))
        coordinateTicks.move(to: CGPoint(x: point.x + tickInner, y: point.y))
        coordinateTicks.addLine(to: CGPoint(x: point.x + tickOuter, y: point.y))
        coordinateTicks.move(to: CGPoint(x: point.x, y: point.y + tickInner))
        coordinateTicks.addLine(to: CGPoint(x: point.x, y: point.y + tickOuter))
        coordinateTicks.move(to: CGPoint(x: point.x - tickInner, y: point.y))
        coordinateTicks.addLine(to: CGPoint(x: point.x - tickOuter, y: point.y))
        context.stroke(
            coordinateTicks,
            with: .color(Palette.inkHigh.opacity(0.72 * alpha)),
            style: StrokeStyle(lineWidth: 0.62, lineCap: .round)
        )
        context.fill(
            Path(ellipseIn: CGRect(
                x: point.x - 2.25,
                y: point.y - 2.25,
                width: 4.5,
                height: 4.5
            )),
            with: .color(Palette.signal.opacity(0.92 * alpha))
        )
        context.fill(
            Path(ellipseIn: CGRect(
                x: point.x - 0.82,
                y: point.y - 0.82,
                width: 1.64,
                height: 1.64
            )),
            with: .color(Palette.inkHigh.opacity(0.98 * alpha))
        )
        let labelPresence = transitionVisuals.chromePresence
        guard observerLabelEmphasized, labelPresence > 0.01 else { return }
        let labelTint = observerLabelEmphasized ? Palette.signal : Palette.inkMid
        let baseLabelOpacity = observerLabelEmphasized
            ? 0.9
            : (simplified ? 0.68 : 0.78)
        let labelOpacity = baseLabelOpacity * labelPresence
        var leader = Path()
        leader.move(to: CGPoint(x: point.x + 8, y: point.y - 6))
        leader.addLine(to: CGPoint(x: point.x + 14, y: point.y - 11))
        context.stroke(
            leader,
            with: .color(Palette.signal.opacity(0.62 * alpha)),
            style: StrokeStyle(lineWidth: 0.62, lineCap: .round)
        )
        let labelRect = CGRect(x: point.x + 13, y: point.y - 22, width: 58, height: 18)
        let labelShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            .path(in: labelRect)
        context.fill(labelShape, with: .color(Palette.voidBlack.opacity(0.82 * alpha)))
        context.stroke(
            labelShape,
            with: .color(Palette.signal.opacity(0.28 * alpha)),
            style: StrokeStyle(lineWidth: 0.5)
        )
        context.draw(
            Text(L10n.text("overview.observer.current"))
                .font(Typography.statusTag)
                .tracking(0.55)
                .foregroundStyle(labelTint.opacity(labelOpacity)),
            at: CGPoint(x: labelRect.midX, y: labelRect.midY),
            anchor: .center
        )
    }

    private func observerProjection(geometry: GlobeGeometry) -> Projected3D? {
        guard let direction = observerSurfaceDirection() else { return nil }
        return Self.projectDirection(
            direction,
            displayRadius: Self.earthDisplayRadius,
            center: geometry.center,
            radius: geometry.radius,
            orientation: geometry.orientation,
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
        style: StrokeStyle = StrokeStyle(lineWidth: 0.42),
        minimumFrontDepth: Double = 0
    ) {
        var path = Path()
        var drawing = false
        for point in projected {
            let matches = (point.depth >= 0) == front
                && (!front || point.depth >= minimumFrontDepth)
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

    private func drawGestureHint(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        presence: Double,
        showGestureHint: Bool
    ) {
        guard presence > 0.01, showGestureHint else { return }
        context.draw(
            Text(L10n.text("overview.gesture_hint"))
                .font(Typography.statusTag)
                .tracking(0.7)
                .foregroundStyle(Palette.inkLow.opacity(0.68 * presence)),
            at: CGPoint(
                x: geometry.center.x,
                y: geometry.rect.maxY + 31
            ),
            anchor: .center
        )
    }
}
