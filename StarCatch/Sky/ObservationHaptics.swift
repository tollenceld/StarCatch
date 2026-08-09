import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// 观测流程共用的触觉发生器。
///
/// 发生器在启动叙事期间预热并持续复用，避免第一次进入感应范围时临时创建
/// Core Haptics 管线，和轨道精算、玻璃面板首次合成挤在同一帧。
@MainActor
final class ObservationHaptics {
    static let shared = ObservationHaptics()

    #if canImport(UIKit) && !targetEnvironment(simulator)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let selection = UISelectionFeedbackGenerator()
    #endif

    private init() {}

    func prepare() {
        #if canImport(UIKit) && !targetEnvironment(simulator)
        soft.prepare()
        rigid.prepare()
        medium.prepare()
        light.prepare()
        selection.prepare()
        #endif
    }

    func softImpact(intensity: CGFloat) {
        #if canImport(UIKit) && !targetEnvironment(simulator)
        soft.impactOccurred(intensity: intensity)
        soft.prepare()
        #endif
    }

    func rigidImpact(intensity: CGFloat) {
        #if canImport(UIKit) && !targetEnvironment(simulator)
        rigid.impactOccurred(intensity: intensity)
        rigid.prepare()
        #endif
    }

    func mediumImpact(intensity: CGFloat = 1) {
        #if canImport(UIKit) && !targetEnvironment(simulator)
        medium.impactOccurred(intensity: intensity)
        medium.prepare()
        #endif
    }

    func lightImpact(intensity: CGFloat = 1) {
        #if canImport(UIKit) && !targetEnvironment(simulator)
        light.impactOccurred(intensity: intensity)
        light.prepare()
        #endif
    }

    func selectionChanged() {
        #if canImport(UIKit) && !targetEnvironment(simulator)
        selection.selectionChanged()
        selection.prepare()
        #endif
    }
}
