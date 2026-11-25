import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

/// Вкладка «Поддержать»: адреса для пожертвований, у каждой сети свой.
struct DonateView: View {
    struct Wallet: Identifiable {
        var network: String  // как подписано в кошельке
        var chain: String
        var address: String
        var id: String { network }
    }

    static let wallets = [
        Wallet(network: "TRC20", chain: "TRON", address: "TCSv6HjHqZmQHTUzP6Pytj1Wq5rccqfcVw"),
        Wallet(network: "BEP20", chain: "BNB Smart Chain", address: "0x7c874a208ebc5c24b5cf9c2eafebe7eec563e186"),
        Wallet(network: "ERC20", chain: "Ethereum", address: "0xbb324a4e0f3e5631ae9a0f6c0e69178f2be111c8"),
    ]

    @State private var selected = wallets[0].network
    @State private var copied = false

    private var wallet: Wallet { Self.wallets.first { $0.network == selected } ?? Self.wallets[0] }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.fill").font(.system(size: 32)).foregroundStyle(.pink)
            Text("Поддержать проект").font(.title2.bold())
            Text("QuickTextPaste-Mac бесплатный и с открытым кодом. Если программа тебе помогает, можно отблагодарить автора криптовалютой.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Сеть", selection: $selected) {
                ForEach(Self.wallets) { Text($0.network).tag($0.network) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .onChange(of: selected) { _, _ in copied = false }

            if let qr = Self.qrImage(wallet.address) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 160, height: 160)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white))
            }

            VStack(spacing: 6) {
                Text("Сеть \(wallet.chain) (\(wallet.network))").font(.caption).foregroundStyle(.secondary)
                Text(wallet.address)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Button(copied ? "Скопировано ✓" : "Скопировать адрес") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(wallet.address, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
            }

            Text("⚠️ У каждой сети свой адрес. Отправляй на адрес \(wallet.network) только через сеть \(wallet.network). Перевод через другую сеть может не дойти, и вернуть его будет нельзя.")
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
