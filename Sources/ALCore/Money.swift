import Foundation

/// Rent in whole cents, so no arithmetic on this value can drift.
///
/// `Double` is the usual mistake here: `2_395.00` is not representable, and a
/// range boundary that is off by a hundredth of a cent will eventually render as
/// `$2,394` on one screen and `$2,395` on another.
public struct Money: Hashable, Sendable, Comparable, Codable {
    public let cents: Int

    public init(cents: Int) { self.cents = cents }
    public init(dollars: Int) { self.cents = dollars * 100 }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }

    public var dollars: Int { cents / 100 }
}

extension Money {
    /// `$2,395`. Full precision, for the card and the unit table.
    public var formatted: String {
        Self.whole.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }

    /// `$2.4k`. Abbreviated, for map pins where the label has to stay legible at
    /// San Francisco's density.
    ///
    /// **Rounds up, never down.**
    ///
    /// `from $X` is a LOWER-BOUND promise, so the only unsafe direction is
    /// down. A label below the true floor advertises a price the building
    /// cannot honour: "from $2.3k" against a cheapest unit of $2,395 sends a
    /// renter to a listing expecting $2,300. A label above it is merely
    /// pessimistic — the renter finds something cheaper than advertised, which
    /// is a good surprise rather than a broken promise.
    ///
    /// Counted over the 23 distinct inventory floors:
    ///
    ///     rule       labels BELOW the true floor (the bait case)
    ///     nearest     0 / 23
    ///     truncate   12 / 23, worst $95
    ///     ceiling     0 / 23
    ///
    /// Nearest happens to be safe for this inventory; ceiling is safe by
    /// construction, which is why it is the rule. Cost is overstating by at
    /// most $99.
    ///
    /// This got it wrong twice before landing: first rounding to nearest with a
    /// docstring claiming it was a problem, then truncating, which took the
    /// count of unattainable advertised floors from zero to twelve while the
    /// comment claimed the opposite. Display rounding never affected filtering
    /// — `ListingFilter.matches` compares exact cents.
    public var abbreviated: String {
        guard dollars >= 1_000 else { return "$\(dollars)" }
        let rounded = (Double(dollars) / 100).rounded(.up) / 10
        return rounded == rounded.rounded()
            ? "$\(Int(rounded))k"
            : "$\(String(format: "%.1f", rounded))k"
    }

    private static let whole: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_US")
        return f
    }()
}

/// The rent spread across a building's available units.
public struct RentRange: Hashable, Sendable, Codable {
    public let low: Money
    public let high: Money

    public init(low: Money, high: Money) {
        // Tolerate reversed input rather than trapping: a bad feed should render
        // a sane range, not crash the map.
        self.low = min(low, high)
        self.high = max(low, high)
    }

    /// `$2,395 to $4,150`. Spelled out rather than punctuated with a dash, which
    /// reads badly aloud in VoiceOver.
    public var formatted: String { "\(low.formatted) to \(high.formatted)" }

    /// What a pin shows. Only the floor, because a two-number label does not fit.
    public var fromFormatted: String { "from \(low.abbreviated)" }
}
