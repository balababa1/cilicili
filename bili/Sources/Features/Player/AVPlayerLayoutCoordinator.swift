import AVFoundation
import AVKit
import UIKit

@MainActor
final class AVPlayerLayoutCoordinator {
    static let shared = AVPlayerLayoutCoordinator()

    private init() {}

    private weak var diagnosticItem: AVPlayerItem?
    private var lastGeometry = ""

    func apply(
        playerLayer: AVPlayerLayer?,
        in containerView: UIView?,
        gravity: AVLayerVideoGravity
    ) {
        guard let playerLayer, let containerView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.videoGravity = gravity
        playerLayer.frame = containerView.bounds
        playerLayer.position = CGPoint(x: containerView.bounds.midX, y: containerView.bounds.midY)
        playerLayer.setNeedsLayout()
        playerLayer.setNeedsDisplay()
        playerLayer.layoutIfNeeded()
        CATransaction.commit()
        if PlayerGeometryDiagnostics.isEnabled {
            let geometry: String = "[VideoDetailGeometry] stage=avPlayerLayerLayout coordinates=drawable-local layerFrame=\(playerLayer.frame) layerBounds=\(playerLayer.bounds) videoRect=\(playerLayer.videoRect) gravity=\(gravity.rawValue) presentationSize=\(playerLayer.player?.currentItem?.presentationSize as Any)"
            if geometry != lastGeometry {
                lastGeometry = geometry
                PlayerGeometryDiagnostics.log(geometry)
            }
            if let item = playerLayer.player?.currentItem, diagnosticItem !== item {
                diagnosticItem = item
                Task { @MainActor [weak item] in
                    guard let item else { return }
                    do {
                        let tracks = try await item.asset.loadTracks(withMediaType: .video)
                        if let track = tracks.first {
                            let size = try await track.load(.naturalSize)
                            PlayerGeometryDiagnostics.log("[VideoDetailGeometry] item=\(ObjectIdentifier(item)) naturalSize=\(size)")
                        }
                    } catch {
                        PlayerGeometryDiagnostics.log("[VideoDetailGeometry] naturalSizeUnavailable=\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func apply(
        playerController: AVPlayerViewController,
        in containerView: UIView,
        gravity: AVLayerVideoGravity
    ) {
        apply(
            playerController: playerController,
            bounds: containerView.bounds,
            gravity: gravity
        )
    }

    func apply(
        playerController: AVPlayerViewController,
        bounds: CGRect,
        gravity: AVLayerVideoGravity
    ) {
        let playerView: UIView = playerController.view
        // bounds.origin 在父容器带偏移时并非零，原样赋值会把这份偏移带进播放器视图。
        let targetFrame: CGRect = CGRect(origin: .zero, size: bounds.size)
        let previousFrame: CGRect = playerView.frame
        let previousMaskRawValue: UInt = playerView.autoresizingMask.rawValue

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            playerController.videoGravity = gravity
            if playerView.frame != targetFrame {
                playerView.frame = targetFrame
            }
            // frame 已由本协调器统一管理，保留 autoresizing 会在父视图尺寸变化时按旧比例二次缩放，
            // 与 AVFoundation 内部的视频布局互相覆盖。
            if !playerView.autoresizingMask.isEmpty {
                playerView.autoresizingMask = []
            }
            playerView.setNeedsLayout()
            // 只标记待布局时，首帧渲染可能读到更新前的几何快照，这里同步落地一次。
            playerView.layoutIfNeeded()
        }
        CATransaction.commit()

        if PlayerGeometryDiagnostics.isEnabled {
            let geometry: String = "[VideoDetailGeometry] stage=avPlayerControllerLayout bounds=\(bounds) target=\(targetFrame) previousFrame=\(previousFrame) frame=\(playerView.frame) maskBefore=\(previousMaskRawValue) videoBounds=\(playerController.videoBounds) gravity=\(gravity.rawValue)"
            PlayerGeometryDiagnostics.log(geometry)
            if previousFrame != targetFrame {
                PlayerGeometryDiagnostics.log("[VideoDetailGeometry] mismatch stage=avPlayerControllerLayout previous=\(previousFrame) target=\(targetFrame)")
            }
        }
    }

    func transition(
        to _: CGSize,
        coordinator: UIViewControllerTransitionCoordinator,
        layout: @escaping @MainActor () -> Void
    ) {
        layout()
        coordinator.animate(alongsideTransition: { _ in
            Task { @MainActor in
                layout()
            }
        }, completion: { _ in
            Task { @MainActor in
                layout()
            }
        })
    }
}

/// 播放器几何诊断日志开关的存储键，设置页与诊断实现共用同一份。
let playerGeometryDiagnosticsEnabledKey: String = "playerGeometryDiagnosticsEnabled"

/// 播放器几何诊断日志。
///
/// 默认关闭，由「我的 → 设置 → 开发者诊断」中的开关控制，开启后同时输出到控制台
/// 与内存环形缓冲，可在同页面查看、复制与清空。
@MainActor
enum PlayerGeometryDiagnostics {
    /// 内存环形缓冲上限，超出后丢弃最早的行。
    static let maximumLineCount: Int = 400
    private static var buffer: [String] = []

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: playerGeometryDiagnosticsEnabledKey)
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line: String = message()
        print(line)
        buffer.append(line)
        if buffer.count > maximumLineCount {
            buffer.removeFirst(buffer.count - maximumLineCount)
        }
    }

    static var lines: [String] {
        buffer
    }

    static var exportText: String {
        buffer.isEmpty ? "暂无日志" : buffer.joined(separator: "\n")
    }

    static func clear() {
        buffer.removeAll(keepingCapacity: true)
    }
}
