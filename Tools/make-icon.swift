// アプリアイコンを描く。1024x1024 の PNG を作る。
//   swift tools/make-icon.swift <出力先.png>
//
// **Apple の製品に似た絵を描かないこと。**
// 1.0 (2) は「アイコンが Apple Watch に似ている」で 5.2.5 却下された（引き継ぎ書 4-107）。
// 時計・バンド・竜頭・側面ボタンは描かない。リストそのものを記号にする。
//
// watchOS 側は円に切り抜かれるので、中身は中心から半径 410 の円に収める。
import AppKit
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

/// 上からの y を CoreGraphics の y に直す
func flip(_ y: CGFloat) -> CGFloat { CGFloat(side) - y }

// 背景（上がわずかに明るい炭色）
let bg = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1),
    CGColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: CGFloat(side)), end: CGPoint(x: 0, y: 0), options: [])

let red = CGColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1)
let grey = CGColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1)

/// ○ と棒を1行ぶん描く
func row(y: CGFloat, barWidth: CGFloat, color: CGColor) {
    let ringCenter = CGPoint(x: 262, y: flip(y))
    let ringRadius: CGFloat = 38
    ctx.setStrokeColor(color)
    ctx.setLineWidth(13)
    ctx.strokeEllipse(in: CGRect(x: ringCenter.x - ringRadius, y: ringCenter.y - ringRadius,
                                 width: ringRadius * 2, height: ringRadius * 2))

    let barHeight: CGFloat = 66
    let bar = CGRect(x: 360, y: flip(y) - barHeight / 2, width: barWidth, height: barHeight)
    ctx.setFillColor(color)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
    ctx.fillPath()
}

// 上2件が文字盤に出るもの（赤）、3件目はまだ出ないもの（灰）
row(y: 330, barWidth: 430, color: red)
row(y: 512, barWidth: 366, color: red)
row(y: 694, barWidth: 300, color: grey)

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
