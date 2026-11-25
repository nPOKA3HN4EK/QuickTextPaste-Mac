import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

/// Вкладка «Поддержать»: адрес для пожертвований в сети TRON (TRC20).
struct DonateView: View {
    static let address = "TCSv6HjHqZmQHTUzP6Pytj1Wq5rccqfcVw"
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.fill").font(.system(size: 32)).foregroundStyle(.pink)
            Text("Поддержать проект").font(.title2.bold())
            Text("QuickTextPaste-Mac бесплатный и с открытым кодом. Если программа тебе помогает, можно отблагодарить автора криптовалютой.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let qr = Self.qrImage(Self.address) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 160, height: 160)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white))
            }

            VStack(spacing: 6) {
                Text("Сеть TRON (TRC20)").font(.caption).foregroundStyle(.secondary)
                Text(Self.address)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Button(copied ? "Скопировано ✓" : "Скопировать адрес") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.address, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
            }

            Text("⚠️ Отправляй только через сеть TRON (TRC20). Перевод через другую сеть, например ERC20 или BEP20, до адреса не дойдёт, и вернуть его будет нельзя.")
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    static func qrImage(_ s: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
