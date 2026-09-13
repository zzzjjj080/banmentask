import AppKit

let out = CommandLine.arguments[1]
let S: CGFloat = 1024
let C = CGPoint(x: 512, y: 512)

func gray(_ g: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(gray: g, alpha: a) }
let red = CGColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1)
let greyRow = gray(0.56)

func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let base = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = base.cgContext
    NSGraphicsContext.saveGraphicsState()
    cg.translateBy(x: 0, y: CGFloat(h)); cg.scaleBy(x: 1, y: -1)          // 上が y=0
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    draw(cg)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func background(_ cg: CGContext) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [gray(0.15), gray(0.02)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: S), options: [])
}
func rrect(_ cg: CGContext, _ r: CGRect, _ radius: CGFloat, fill: CGColor? = nil, stroke: CGColor? = nil, lw: CGFloat = 0) {
    let p = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if let f = fill { cg.setFillColor(f); cg.addPath(p); cg.fillPath() }
    if let s = stroke { cg.setStrokeColor(s); cg.setLineWidth(lw); cg.addPath(p); cg.strokePath() }
}
func circle(_ cg: CGContext, _ c: CGPoint, _ r: CGFloat, fill: CGColor? = nil, stroke: CGColor? = nil, lw: CGFloat = 0) {
    let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    if let f = fill { cg.setFillColor(f); cg.fillEllipse(in: rect) }
    if let s = stroke { cg.setStrokeColor(s); cg.setLineWidth(lw); cg.strokeEllipse(in: rect) }
}
func onCircle(_ c: CGPoint, _ r: CGFloat, _ deg: CGFloat) -> CGPoint {
    let a = deg * .pi / 180
    return CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a))
}
/// ○＋棒の1行
func row(_ cg: CGContext, x: CGFloat, y: CGFloat, bar: CGFloat, color: CGColor, s: CGFloat) {
    let r = 38 * s
    circle(cg, CGPoint(x: x, y: y), r, stroke: color, lw: 13 * s)
    let h = 66 * s
    rrect(cg, CGRect(x: x + 98 * s, y: y - h / 2, width: bar * s, height: h), h / 2, fill: color)
}
func rows(_ cg: CGContext, x: CGFloat, y: CGFloat, gap: CGFloat, s: CGFloat) {
    row(cg, x: x, y: y - gap, bar: 430, color: red, s: s)
    row(cg, x: x, y: y, bar: 366, color: red, s: s)
    row(cg, x: x, y: y + gap, bar: 300, color: greyRow, s: s)
}
func font(_ size: CGFloat, _ w: NSFont.Weight, rounded: Bool = false) -> NSFont {
    let f = NSFont.systemFont(ofSize: size, weight: w)
    if rounded, let d = f.fontDescriptor.withDesign(.rounded) { return NSFont(descriptor: d, size: size) ?? f }
    return f
}
func text(_ s: String, _ f: NSFont, _ color: CGColor, center: CGPoint? = nil, left: CGPoint? = nil, right: CGPoint? = nil) {
    let str = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: NSColor(cgColor: color)!])
    let b = str.size()
    var p = CGPoint.zero
    if let c = center { p = CGPoint(x: c.x - b.width / 2, y: c.y - b.height / 2) }
    if let l = left { p = CGPoint(x: l.x, y: l.y - b.height / 2) }
    if let r = right { p = CGPoint(x: r.x - b.width, y: r.y - b.height / 2) }
    str.draw(at: p)
}
func faceContent(_ cg: CGContext, rect: CGRect, textSize: CGFloat, timeSize: CGFloat) {
    // 時刻（右上）と横長スロットに2行
    text("10:09", font(timeSize, .medium, rounded: true), gray(1), right: CGPoint(x: rect.maxX, y: rect.minY + timeSize * 0.55))
    let slot = CGRect(x: rect.minX, y: rect.minY + timeSize * 1.25, width: rect.width, height: textSize * 2.9)
    rrect(cg, slot, textSize * 0.45, fill: gray(0.16))
    text("洗濯する", font(textSize, .bold), red, left: CGPoint(x: slot.minX + textSize * 0.4, y: slot.minY + textSize * 0.95))
    text("電話する", font(textSize, .bold), red, left: CGPoint(x: slot.minX + textSize * 0.4, y: slot.minY + textSize * 2.0))
}

// ── 10案（安全 → 危ない の順）──────────────────────────────
let concepts: [(title: String, risk: String, draw: (CGContext) -> Void)] = [
    ("「盤」一文字", "安全", { cg in
        background(cg)
        text("盤", font(430, .heavy), gray(1), center: CGPoint(x: 512, y: 455))
        rrect(cg, CGRect(x: 322, y: 752, width: 380, height: 36), 18, fill: red)
        rrect(cg, CGRect(x: 382, y: 812, width: 260, height: 36), 18, fill: red)
    }),
    ("盤（ボード）", "安全", { cg in
        background(cg)
        let b = CGRect(x: 232, y: 232, width: 560, height: 560)
        rrect(cg, b, 36, fill: gray(0.14), stroke: gray(0.32), lw: 6)
        let step = (b.width - 72) / 5
        cg.setStrokeColor(gray(0.30)); cg.setLineWidth(5)
        for i in 0...5 {
            let v = b.minX + 36 + CGFloat(i) * step
            cg.move(to: CGPoint(x: v, y: b.minY + 36)); cg.addLine(to: CGPoint(x: v, y: b.maxY - 36))
            cg.move(to: CGPoint(x: b.minX + 36, y: v)); cg.addLine(to: CGPoint(x: b.maxX - 36, y: v))
        }
        cg.strokePath()
        for (i, c) in [red, red, greyRow].enumerated() {
            let y = b.minY + 36 + CGFloat(i) * step
            let w = (i == 2 ? 3 : 5) * step
            rrect(cg, CGRect(x: b.minX + 36 + 12, y: y + 12, width: w - 24, height: step - 24), 20, fill: c)
        }
    }),
    ("目盛り＋リスト", "低", { cg in
        background(cg)
        for i in 0..<60 {
            let major = i % 5 == 0
            cg.setStrokeColor(major ? gray(0.8) : gray(0.35)); cg.setLineWidth(major ? 11 : 5); cg.setLineCap(.round)
            cg.move(to: onCircle(C, major ? 330 : 358, CGFloat(i) * 6)); cg.addLine(to: onCircle(C, 388, CGFloat(i) * 6))
            cg.strokePath()
        }
        rows(cg, x: 322, y: 512, gap: 112, s: 0.78)
    }),
    ("輪＋リスト", "低", { cg in
        background(cg)
        cg.setStrokeColor(gray(0.55)); cg.setLineWidth(34); cg.setLineCap(.round); cg.setLineJoin(.round)
        var first = true
        for a in stride(from: CGFloat(-50), through: 250, by: 2) {
            let p = onCircle(C, 360, a)
            if first { cg.move(to: p); first = false } else { cg.addLine(to: p) }
        }
        cg.strokePath()
        let end = onCircle(C, 360, 250); let ar = 250 * CGFloat.pi / 180
        let t = CGPoint(x: cos(ar), y: sin(ar)); let n = CGPoint(x: -t.y, y: t.x)
        cg.setFillColor(gray(0.55))
        cg.move(to: CGPoint(x: end.x + t.x * 70, y: end.y + t.y * 70))
        cg.addLine(to: CGPoint(x: end.x + n.x * 58 - t.x * 10, y: end.y + n.y * 58 - t.y * 10))
        cg.addLine(to: CGPoint(x: end.x - n.x * 58 - t.x * 10, y: end.y - n.y * 58 - t.y * 10))
        cg.closePath(); cg.fillPath()
        rows(cg, x: 350, y: 512, gap: 96, s: 0.66)
    }),
    ("針がチェック", "低", { cg in
        background(cg)
        circle(cg, C, 380, fill: gray(0.10), stroke: gray(0.28), lw: 6)
        for i in 0..<12 {
            let major = i % 3 == 0
            cg.setStrokeColor(major ? gray(0.8) : gray(0.45)); cg.setLineWidth(major ? 16 : 8); cg.setLineCap(.round)
            cg.move(to: onCircle(C, major ? 300 : 322, CGFloat(i) * 30)); cg.addLine(to: onCircle(C, 348, CGFloat(i) * 30))
            cg.strokePath()
        }
        cg.setStrokeColor(red); cg.setLineWidth(54); cg.setLineCap(.round); cg.setLineJoin(.round)
        cg.move(to: CGPoint(x: 372, y: 450)); cg.addLine(to: CGPoint(x: 486, y: 580)); cg.addLine(to: CGPoint(x: 712, y: 318))
        cg.strokePath()
        circle(cg, CGPoint(x: 486, y: 580), 24, fill: gray(1))
    }),
    ("丸い腕時計", "中", { cg in
        background(cg)
        rrect(cg, CGRect(x: 402, y: 118, width: 220, height: 190), 40, fill: gray(0.26))
        rrect(cg, CGRect(x: 402, y: 716, width: 220, height: 190), 40, fill: gray(0.26))
        rrect(cg, CGRect(x: 812, y: 470, width: 60, height: 84), 18, fill: gray(0.55))
        circle(cg, C, 330, fill: gray(0.62))
        circle(cg, C, 302, fill: gray(0.20))
        circle(cg, C, 282, fill: gray(0.0))
        rows(cg, x: 372, y: 512, gap: 88, s: 0.6)
    }),
    ("横長スロット", "中", { cg in
        background(cg)
        let tile = CGRect(x: 150, y: 330, width: 724, height: 364)
        rrect(cg, tile, 88, fill: gray(0.17), stroke: gray(0.30), lw: 4)
        text("洗濯する", font(138, .bold), red, left: CGPoint(x: 220, y: 440))
        text("電話する", font(138, .bold), gray(1), left: CGPoint(x: 220, y: 590))
    }),
    ("文字盤そのもの", "ギリギリ", { cg in
        cg.setFillColor(gray(0)); cg.fill(CGRect(x: 0, y: 0, width: S, height: S))
        text("SUN", font(62, .semibold), red, left: CGPoint(x: 212, y: 255))
        text("13", font(100, .semibold, rounded: true), gray(1), left: CGPoint(x: 212, y: 330))
        faceContent(cg, rect: CGRect(x: 200, y: 215, width: 624, height: 600), textSize: 96, timeSize: 170)
    }),
    ("画面だけ浮かす", "ギリギリ", { cg in
        background(cg)
        let screen = CGRect(x: 257, y: 202, width: 510, height: 620)
        rrect(cg, screen, 124, fill: gray(0), stroke: gray(0.26), lw: 22)
        faceContent(cg, rect: screen.insetBy(dx: 58, dy: 70), textSize: 72, timeSize: 118)
    }),
    ("画面＋短い帯", "高", { cg in
        background(cg)
        rrect(cg, CGRect(x: 352, y: -40, width: 320, height: 330), 50, fill: gray(0.22))
        rrect(cg, CGRect(x: 352, y: 734, width: 320, height: 330), 50, fill: gray(0.22))
        let screen = CGRect(x: 282, y: 232, width: 460, height: 560)
        rrect(cg, screen, 110, fill: gray(0), stroke: gray(0.32), lw: 20)
        faceContent(cg, rect: screen.insetBy(dx: 50, dy: 62), textSize: 64, timeSize: 106)
    }),
]

// 1枚ずつ
var reps: [NSBitmapImageRep] = []
for (i, c) in concepts.enumerated() {
    let rep = canvas(1024, 1024, c.draw)
    save(rep, "\(out)/\(String(format: "%02d", i + 1)).png")
    reps.append(rep)
}

// 一覧（5×2）
let cell: CGFloat = 320, pad: CGFloat = 44, labelH: CGFloat = 96
let sheet = canvas(Int(5 * cell + 6 * pad), Int(2 * (cell + labelH) + 3 * pad)) { cg in
    cg.setFillColor(gray(0.07)); cg.fill(CGRect(x: 0, y: 0, width: 5 * cell + 6 * pad, height: 2 * (cell + labelH) + 3 * pad))
    for (i, c) in concepts.enumerated() {
        let col = CGFloat(i % 5), line = CGFloat(i / 5)
        let r = CGRect(x: pad + col * (cell + pad), y: pad + line * (cell + labelH + pad), width: cell, height: cell)
        cg.saveGState()
        cg.addPath(CGPath(roundedRect: r, cornerWidth: 72, cornerHeight: 72, transform: nil)); cg.clip()
        let img = NSImage(size: NSSize(width: 1024, height: 1024)); img.addRepresentation(reps[i])
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        cg.restoreGState()
        let riskColor: CGColor = ["安全": CGColor(red: 0.4, green: 0.85, blue: 0.5, alpha: 1),
                                  "低": CGColor(red: 0.4, green: 0.85, blue: 0.5, alpha: 1),
                                  "中": CGColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1),
                                  "ギリギリ": CGColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1),
                                  "高": red][c.risk]!
        text("\(i + 1)  \(c.title)", font(30, .semibold), gray(1), left: CGPoint(x: r.minX, y: r.maxY + 34))
        text("却下の危険：\(c.risk)", font(26, .medium), riskColor, left: CGPoint(x: r.minX, y: r.maxY + 76))
    }
}
save(sheet, "\(out)/sheet.png")
print("ok")
