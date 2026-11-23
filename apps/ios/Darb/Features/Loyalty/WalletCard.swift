import PassKit
import SwiftUI

/// The visitor's Darb card lives in Apple Wallet: added once from the menu, and from then on Wallet keeps it
/// current itself (a stamp at the counter updates the pass and shows on the lock screen).
@MainActor @Observable
final class WalletCard {
    static let shared = WalletCard()
    static let passType = "pass.il.co.darb.loyalty"
    private static let serialKey = "wallet.serial"

    private(set) var busy = false
    var error: String?
    /// The card as it sits in Wallet, when it does.
    private(set) var inWallet: PKPass?
    /// A pass waiting for the person to add it.
    var adding: PKPass?

    var canAdd: Bool { PKAddPassesViewController.canAddPasses() }

    func refresh() {
        guard let serial = UserDefaults.standard.string(forKey: Self.serialKey) else { inWallet = nil; return }
        inWallet = PKPassLibrary().pass(withPassTypeIdentifier: Self.passType, serialNumber: serial)
    }

    /// Downloads the card's pass and offers it to Wallet, or opens it there when it is already in.
    func add() async {
        busy = true; defer { busy = false }
        error = nil
        do {
            let pass = try PKPass(data: try await LoyaltyAPI.walletPass())
            UserDefaults.standard.set(pass.serialNumber, forKey: Self.serialKey)
            if let kept = PKPassLibrary().pass(withPassTypeIdentifier: pass.passTypeIdentifier, serialNumber: pass.serialNumber) {
                inWallet = kept
                open()
            } else {
                adding = pass
            }
        } catch LoyaltyAPI.Failure.unavailable {
            error = L("הכרטיס לארנק עוד לא זמין. נסו שוב בקרוב.")
        } catch {
            self.error = L("אין חיבור. נסו שוב.")
        }
    }

    func open() {
        guard let url = inWallet?.passURL else { return }
        UIApplication.shared.open(url)
    }
}

/// The menu's card row: Apple's own "Add to Apple Wallet" button, or, once added, a row that opens it there.
struct WalletCardRow: View {
    @State private var wallet = WalletCard.shared

    var body: some View {
        Group {
            if wallet.inWallet != nil {
                Button { wallet.open() } label: {
                    MenuRow(symbol: "wallet.pass.fill", title: L("כרטיס דרב"), detail: L("בארנק. החותמות מתעדכנות שם לבד."), tint: .mustard) {
                        Image(systemName: "arrow.up.forward").font(.symbol(.footnote)).foregroundStyle(.secondary)
                    }
                }
            } else if wallet.canAdd {
                VStack(alignment: .leading, spacing: 10) {
                    MenuRow(symbol: "wallet.pass.fill", title: L("כרטיס דרב"), detail: L("חותמות והטבות אצל העסקים השותפים, ב‑Apple Wallet"), tint: .mustard) { EmptyView() }
                    AddToWalletButton { Task { await wallet.add() } }
                        .frame(height: 48)
                        .opacity(wallet.busy ? 0.5 : 1)
                        .disabled(wallet.busy)
                        .overlay { if wallet.busy { ProgressView() } }
                    if let error = wallet.error {
                        Text(error).font(.darb(.caption)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .onAppear { wallet.refresh() }
        .sheet(item: $wallet.adding) { pass in
            AddPassSheet(pass: pass) { wallet.adding = nil; wallet.refresh() }
                .ignoresSafeArea()
        }
    }
}

extension PKPass: @retroactive Identifiable {
    public var id: String { serialNumber }
}

/// Apple's "Add to Apple Wallet" button, as Apple draws it in the phone's language.
private struct AddToWalletButton: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .blackOutline)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: PKAddPassButton, context: Context) { context.coordinator.action = action }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

/// Wallet's own sheet showing the pass, with its Add button.
private struct AddPassSheet: UIViewControllerRepresentable {
    let pass: PKPass
    let done: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let sheet = PKAddPassesViewController(pass: pass) ?? UIViewController()
        (sheet as? PKAddPassesViewController)?.delegate = context.coordinator
        return sheet
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) { done() }
    }
}
