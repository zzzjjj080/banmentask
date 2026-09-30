import SwiftUI

/// 画面のいちばん下（接続の情報の下）に置く、作者の他のアプリへの1行。
/// 2026-09-30、投げ銭（コーヒー1杯）を廃止した跡地。本人が副業にあたる収入の入り口を無くす判断。
struct OtherAppsLink: View {
    private static let url = URL(string: "https://apps.apple.com/jp/developer/jin-nakamura/id6802013586")!

    var body: some View {
        Link(destination: Self.url) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13))
                Text("作者の他のアプリ")
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color(white: 0.55))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(white: 0.18), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
