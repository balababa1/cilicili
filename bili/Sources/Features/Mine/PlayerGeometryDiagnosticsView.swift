import SwiftUI
import UIKit

/// 播放器几何诊断日志查看页。
///
/// 日志由 `PlayerGeometryDiagnostics` 采集，只有在「播放器几何诊断」开关开启时才会写入；
/// 开关默认关闭，普通使用既不产生日志，也不会在播放布局的热路径上拼接字符串。
struct PlayerGeometryDiagnosticsView: View {
    @ObservedObject var libraryStore: LibraryStore
    @AppStorage(playerGeometryDiagnosticsEnabledKey) private var diagnosticsEnabled = false
    @State private var lines: [String] = []

    /// 列表一次最多渲染的行数，避免长日志把 Form 撑到卡顿。
    private let visibleLineLimit: Int = 120

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $diagnosticsEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        MineSettingsLabel("播放器几何诊断", systemImage: "viewfinder")
                        Text("记录播放器视图、绘制层和全屏容器的几何数据，用于定位全屏画面偏移。")
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("mine.diagnostics.playerGeometry")
            } footer: {
                Text(
                    "默认关闭。开启后日志只缓存在本机内存的最多 "
                        + "\(PlayerGeometryDiagnostics.maximumLineCount) 条，不会上传，退出 App 后清空。"
                )
                .appTypography(.settingsSubtitle, fallback: .caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                if displayedLines.isEmpty {
                    Text(
                        diagnosticsEnabled
                            ? "还没有采集到日志，播放视频并切换一次全屏后再回来查看。"
                            : "开关已关闭，当前不会采集日志。"
                    )
                    .appTypography(.settingsSubtitle, fallback: .caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(displayedLines.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    Text("采集记录")
                    Spacer(minLength: 8)
                    Text(lineCountText)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if hiddenLineCount > 0 {
                    Text("列表只显示最近 \(displayedLines.count) 条，复制会取出全部 \(lines.count) 条。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Button("刷新") {
                    reload()
                }
                Button("复制全部") {
                    UIPasteboard.general.string = PlayerGeometryDiagnostics.exportText
                }
                .disabled(lines.isEmpty)
                Button("清空", role: .destructive) {
                    PlayerGeometryDiagnostics.clear()
                    reload()
                }
                .disabled(lines.isEmpty)
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .standardPageHorizontalContentMargins(libraryStore.standardPageHorizontalInset)
        .nativeTopScrollEdgeEffect()
        .navigationTitle("播放器几何日志")
        .onAppear {
            reload()
        }
    }

    private var displayedLines: [String] {
        guard lines.count > visibleLineLimit else { return lines }
        return Array(lines.suffix(visibleLineLimit))
    }

    private var hiddenLineCount: Int {
        max(0, lines.count - displayedLines.count)
    }

    private var lineCountText: String {
        "\(lines.count)/\(PlayerGeometryDiagnostics.maximumLineCount)"
    }

    private func reload() {
        lines = PlayerGeometryDiagnostics.lines
    }
}
