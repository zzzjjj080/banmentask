import SwiftUI

/// 文字盤・Watch アプリ・iPhone のプレビューで共通の色。
/// リマインダーは赤系、予定は青系。
enum FaceStyle {
    static let reminder = Color(red: 1.00, green: 0.42, blue: 0.42)
    static let event = Color(red: 0.45, green: 0.72, blue: 1.00)

    static func color(_ kind: FaceItem.Kind) -> Color {
        kind == .reminder ? reminder : event
    }

    /// 複数行を1つの Text にまとめ、行ごとに色を付ける。
    /// 1つの Text にしておくと、長い行に合わせて全行が同じ倍率で縮む。
    static func coloredText(_ lines: [FaceLine]) -> Text {
        var out = Text("")
        for (i, line) in lines.enumerated() {
            let t = Text(line.text).foregroundStyle(color(line.kind))
            out = i == 0 ? t : out + Text("\n") + t
        }
        return out
    }
}
