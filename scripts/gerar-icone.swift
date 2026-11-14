// Gera Recursos/AppIcon.icns a partir de docs/logo/my-stats-icone-escuro.svg.
// Uso: swift scripts/gerar-icone.swift   (na raiz do repositório)
import AppKit

let raiz = FileManager.default.currentDirectoryPath
let origem = URL(fileURLWithPath: raiz + "/docs/logo/my-stats-icone-escuro.svg")
let pasta = URL(fileURLWithPath: NSTemporaryDirectory() + "AppIcon.iconset")
let destino = URL(fileURLWithPath: raiz + "/Recursos/AppIcon.icns")

guard let svg = NSImage(contentsOf: origem) else {
    FileHandle.standardError.write("Não consegui ler \(origem.path)\n".data(using: .utf8)!)
    exit(1)
}
try? FileManager.default.removeItem(at: pasta)
try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for escala in [1, 2] {
        let px = base * escala
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        svg.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let nome = escala == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: pasta.appendingPathComponent(nome))
    }
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", pasta.path, "-o", destino.path]
try p.run()
p.waitUntilExit()
guard p.terminationStatus == 0 else { exit(p.terminationStatus) }
print("Gerado: \(destino.path)")
