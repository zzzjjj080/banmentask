import UIKit

/// 操作のたびに鳴らす振動。全部ここを通す。
enum Haptic {
    /// 軽いタップ（行を触った、入力を始めた）
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    /// 確定（追加した、改名した、送った）
    static func confirm() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    /// 完了した
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// 取り消した・失敗した
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    /// 並べ替え・選択が変わった
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}
