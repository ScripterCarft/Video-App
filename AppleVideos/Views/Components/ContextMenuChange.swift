import SwiftUI

/// Applies a context menu action that can remove the card the menu belongs
/// to, such as Remove from Watchlist or Unsave in Saved.
///
/// While the menu closes, iOS animates the lifted preview back to the card.
/// Removing the card right away let its neighbors move under the returning
/// preview, so both showed on top of each other. SwiftUI's `contextMenu`
/// reports no "menu closed" event (UIKit's `UIContextMenuInteraction` does),
/// so the change waits for the closing animation and then animates.
@MainActor
func applyAfterContextMenuCloses(_ change: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation {
            change()
        }
    }
}
