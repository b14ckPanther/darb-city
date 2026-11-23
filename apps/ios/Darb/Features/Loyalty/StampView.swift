import AVFoundation
import SwiftUI
import VisionKit

/// The counter, native: the camera reads a customer's Darb card, the card's stamps show for each offer this person
/// stamps for, and one big button stamps it, or hands over the reward when it is ready.
struct StampView: View {
    @State private var code: String?
    @State private var card: LoyaltyCard?
    @State private var message: (text: String, good: Bool)?
    @State private var typed = ""
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            if let card {
                result(card)
            } else {
                scanner
            }
        }
        .background(Color.canvas)
        .page(L("החתמת כרטיס"))
        .sensoryFeedback(.success, trigger: message?.good == true ? message?.text : nil)
    }

    // MARK: scanning

    private var scanner: some View {
        VStack(spacing: 14) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                QRScanner { scanned in
                    guard code == nil, let c = LoyaltyAPI.code(from: scanned) else { return }
                    Task { await open(c) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.mustard, lineWidth: 4).frame(width: 230, height: 230)
                }
                .overlay(alignment: .bottom) {
                    Text(L("כוונו את המצלמה לקוד שעל כרטיס דרב"))
                        .font(.darb(.subheadline, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 38)
                        .background(.black.opacity(0.55), in: Capsule()).padding(16)
                }
            } else {
                ContentUnavailableView(L("אין גישה למצלמה"), systemImage: "camera.fill",
                                       description: Text(L("אפשר לאשר אותה בהגדרות, או להקליד את הקוד שמתחת לברקוד.")))
                    .font(.darb(.body))
            }
            HStack(spacing: 10) {
                TextField(L("או הקלידו את הקוד"), text: $typed)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.horizontal, 14).frame(height: 52)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .submitLabel(.go)
                    .onSubmit { if let c = LoyaltyAPI.code(from: typed) { Task { await open(c) } } }
                Button { if let c = LoyaltyAPI.code(from: typed) { Task { await open(c) } } } label: {
                    Image(systemName: "arrow.forward").font(.symbol(.headline)).foregroundStyle(Color.onColor)
                        .frame(width: 52, height: 52).sticker(.mustard, radius: 16, line: 2.5, drop: 3)
                }
                .buttonStyle(PressStyle(scale: 0.95))
                .disabled(LoyaltyAPI.code(from: typed) == nil)
            }
            if let message { note(message) }
        }
        .padding(16)
        .overlay { if working { ProgressView() } }
    }

    // MARK: the scanned card

    private func result(_ card: LoyaltyCard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: "\(card.code.prefix(5)) \(card.code.suffix(5))")
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .environment(\.layoutDirection, .leftToRight)
                if let message { note(message) }
                if card.standings.isEmpty {
                    Text(L("אין עדיין הטבה פעילה. יוצרים הטבה בניהול, ואז מחתימים כאן."))
                        .font(.darb(.subheadline)).foregroundStyle(.secondary)
                }
                ForEach(card.standings) { s in
                    VStack(alignment: .leading, spacing: 12) {
                        StandingCard(standing: s)
                        Button { Task { await act(card.code, s) } } label: {
                            Label(s.ready ? L("לתת את ההטבה") : L("להחתים"), systemImage: s.ready ? "gift.fill" : "checkmark.seal.fill")
                                .font(.darb(.title3, .black)).foregroundStyle(Color.onColor)
                                .frame(maxWidth: .infinity).frame(height: 64)
                                .sticker(s.ready ? Color(hex: 0x3DDC97) : .mustard, radius: 20)
                        }
                        .buttonStyle(PressStyle(scale: 0.97))
                        .disabled(working || (!s.ready && s.nextStampAt != nil))
                        if !s.ready, let next = s.nextStampAt.flatMap(LoyaltyAPI.date) {
                            Text(L("החתמה הבאה מ %@", next.formatted(date: .omitted, time: .shortened)))
                                .font(.darb(.footnote)).foregroundStyle(.secondary)
                        }
                    }
                }
                Button { self.card = nil; code = nil; message = nil; typed = "" } label: {
                    Label(L("לסרוק כרטיס אחר"), systemImage: "qrcode.viewfinder")
                        .font(.darb(.headline, .bold)).frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressStyle(scale: 0.97))
            }
            .padding(16)
        }
    }

    private func note(_ m: (text: String, good: Bool)) -> some View {
        Label(m.text, systemImage: m.good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.darb(.headline, .heavy))
            .foregroundStyle(m.good ? Color.open : Color.shut)
    }

    // MARK: talking to the server

    private func open(_ c: String) async {
        code = c; working = true; defer { working = false }
        do {
            card = try await LoyaltyAPI.card(c)
            message = nil
            Haptic.tap()
        } catch {
            code = nil
            message = (Self.text(error), false)
        }
    }

    private func act(_ c: String, _ s: LoyaltyStanding) async {
        working = true; defer { working = false }
        do {
            _ = try await LoyaltyAPI.stamp(c, offer: s.offer.id, redeem: s.ready)
            message = (s.ready ? L("ההטבה ניתנה") : L("הוחתם"), true)
            Haptic.done()
        } catch {
            message = (Self.text(error), false)
        }
        if let fresh = try? await LoyaltyAPI.card(c) { card = fresh }
    }

    private static func text(_ e: LoyaltyAPI.Failure) -> String {
        switch e {
        case .notACard: L("זה לא כרטיס של דרב.")
        case .notStaff: L("אתם לא מחתימים כרטיסים לעסק הזה.")
        case .tooSoon: L("הכרטיס כבר הוחתם לפני זמן קצר")
        case .rewardReady: L("קודם לתת את ההטבה")
        case .notReady: L("עוד אין מספיק החתמות")
        case .gone, .offline, .unavailable: L("אין חיבור. נסו שוב.")
        }
    }
}

/// The camera, reading QR codes only, with Apple's own scanner.
struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                           isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        init(found: @escaping (String) -> Void) { self.found = found }
        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let b) in items { if let s = b.payloadStringValue { found(s); return } }
        }
    }
}
