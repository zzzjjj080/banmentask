import SwiftUI

/// 文字盤・Watch アプリ・iPhone・ホームウィジェットで共通の色。
/// 白黒を含む15色から、リマインダーと予定それぞれに1色を選ぶ。
enum FaceStyle {
    static let palette: [(name: String, color: Color)] = [
        ("白",     .white),
        ("グレー", Color(white: 0.62)),
        ("赤",     Color(red: 1.00, green: 0.42, blue: 0.42)),
        ("オレンジ", Color(red: 1.00, green: 0.62, blue: 0.25)),
        ("黄",     Color(red: 1.00, green: 0.85, blue: 0.30)),
        ("ライム", Color(red: 0.70, green: 0.95, blue: 0.35)),
        ("緑",     Color(red: 0.40, green: 0.85, blue: 0.50)),
        ("ミント", Color(red: 0.45, green: 0.90, blue: 0.80)),
        ("シアン", Color(red: 0.40, green: 0.85, blue: 1.00)),
        ("青",     Color(red: 0.45, green: 0.72, blue: 1.00)),
        ("藍",     Color(red: 0.55, green: 0.55, blue: 1.00)),
        ("紫",     Color(red: 0.75, green: 0.55, blue: 1.00)),
        ("ピンク", Color(red: 1.00, green: 0.55, blue: 0.80)),
        ("茶",     Color(red: 0.80, green: 0.62, blue: 0.45)),
        ("黒",     Color(white: 0.25)),
    ]

    static func color(_ index: Int) -> Color {
        palette[((index % palette.count) + palette.count) % palette.count].color
    }
    static func name(_ index: Int) -> String {
        palette[((index % palette.count) + palette.count) % palette.count].name
    }
    static func next(_ index: Int) -> Int { (index + 1) % palette.count }

    static func color(_ kind: FaceItem.Kind, layout: FaceLayout) -> Color {
        color(layout.color(kind))
    }

    /// 複数行を1つの Text にまとめ、行ごとに色を付ける。
    /// 1つの Text にしておくと、長い行に合わせて全行が同じ倍率で縮む。
    static func coloredText(_ lines: [FaceLine], layout: FaceLayout) -> Text {
        var out = Text("")
        for (i, line) in lines.enumerated() {
            let t = Text(line.text).foregroundStyle(color(line.kind, layout: layout))
            out = i == 0 ? t : out + Text("\n") + t
        }
        return out
    }
}
