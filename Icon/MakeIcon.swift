import AppKit

/// Рисует помидор во все размеры iconset. Вызывается из `build.sh`;
/// сам рисунок лежит в `Resources/Tomato.png`.
@main
enum MakeIcon {
    static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
        // Рисунок помидора: при сборке иконки бандла ещё нет, путь даёт build.sh.
        let artwork = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/Tomato.png"
        TomatoIcon.artworkURL = URL(fileURLWithPath: artwork)
        // Нечитаемый рисунок — худший из отказов: `TomatoIcon.draw` молча
        // рисует одну белую плашку, `iconutil` её принимает, `test -s` в
        // build.sh видит непустой файл, и пустая иконка уезжает в релиз.
        guard let image = NSImage(contentsOfFile: artwork), image.size.width > 0 else {
            FileHandle.standardError.write(Data(
                "   ✗ рисунок \(artwork) не читается — иконка вышла бы пустой\n".utf8))
            exit(1)
        }
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

        // Пары «логический размер · множитель» — те, которые требует iconutil.
        let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                                      (256, 1), (256, 2), (512, 1), (512, 2)]
        for (points, scale) in variants {
            let pixels = points * scale
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            TomatoIcon.draw(size: CGFloat(pixels))
            NSGraphicsContext.restoreGraphicsState()

            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            let data = rep.representation(using: .png, properties: [:])!
            try? data.write(to: URL(fileURLWithPath: out + "/" + name))
        }
        print("   \(variants.count) размеров в \(out)")
    }
}
