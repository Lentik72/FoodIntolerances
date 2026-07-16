import Foundation

/// Pure debounce decision for when the app should re-mine the graph.
public enum RecomputePolicy {
    public static func shouldRecompute(lastRunAt: Date?, lastWatermark: Int, now: Date,
                                       currentWatermark: Int, minInterval: TimeInterval) -> Bool {
        guard let lastRunAt else { return true }              // never run
        if currentWatermark != lastWatermark { return true }  // events changed
        return now.timeIntervalSince(lastRunAt) >= minInterval
    }
}
