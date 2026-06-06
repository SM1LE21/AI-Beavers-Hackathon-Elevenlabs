import Foundation

struct LiveServeEmissionThresholds {
    let clusterImpactGapSeconds: Double
    let clusterTrophyGapSeconds: Double
    let clusterCoreOverlapSeconds: Double
    let maximumImpactBacktrackSeconds: Double
    let settleSeconds: Double
}

private struct LiveServePendingCluster {
    let id = UUID()
    var bestEvent: ServeEvent
    var firstSeenTimestamp: Double
    var lastSeenTimestamp: Double
    var observationCount: Int

    mutating func observe(_ event: ServeEvent, at timestamp: Double) {
        if event.confidence > bestEvent.confidence {
            bestEvent = event
        }
        lastSeenTimestamp = timestamp
        observationCount += 1
    }
}

struct LiveServeEmissionUpdate {
    let emittedServe: ServeEvent?
    let heldCandidates: [ServeEvent]
    let dedupedCandidates: [ServeEvent]
}

final class LiveServeEmissionTracker {
    private let retentionSeconds: Double
    private var emittedEvents: [ServeEvent] = []
    private var pendingClusters: [LiveServePendingCluster] = []

    init(retentionSeconds: Double) {
        self.retentionSeconds = retentionSeconds
    }

    func reset() {
        emittedEvents.removeAll()
        pendingClusters.removeAll()
    }

    func forgetEmittedServe(_ event: ServeEvent) {
        emittedEvents.removeAll { emittedEvent in
            emittedEvent.id == event.id
        }
    }

    func registerEmittedServe(
        _ event: ServeEvent,
        thresholds: LiveServeEmissionThresholds
    ) {
        pendingClusters.removeAll { cluster in
            isSameServeCluster(lhs: event, rhs: cluster.bestEvent, thresholds: thresholds)
        }
        emittedEvents.removeAll { emittedEvent in
            isSameServeCluster(lhs: event, rhs: emittedEvent, thresholds: thresholds)
        }
        emittedEvents.append(event)
    }

    func ingest(
        validatedCandidates: [ServeEvent],
        latestTimestamp: Double,
        thresholds: LiveServeEmissionThresholds
    ) -> LiveServeEmissionUpdate {
        trimState(endingAt: latestTimestamp)

        var touchedClusterIDs: Set<UUID> = []
        var dedupedCandidates: [ServeEvent] = []

        for candidate in validatedCandidates.sorted(by: { $0.impactTimeSeconds < $1.impactTimeSeconds }) {
            if let latestEmittedImpact = emittedEvents.map(\.impactTimeSeconds).max(),
               candidate.impactTimeSeconds < latestEmittedImpact - thresholds.maximumImpactBacktrackSeconds
            {
                dedupedCandidates.append(candidate)
                continue
            }

            if emittedEvents.contains(where: { isSameServeCluster(lhs: candidate, rhs: $0, thresholds: thresholds) }) {
                dedupedCandidates.append(candidate)
                continue
            }

            if let clusterIndex = pendingClusters.firstIndex(where: {
                isSameServeCluster(lhs: candidate, rhs: $0.bestEvent, thresholds: thresholds)
            }) {
                pendingClusters[clusterIndex].observe(candidate, at: latestTimestamp)
                touchedClusterIDs.insert(pendingClusters[clusterIndex].id)
                continue
            }

            let newCluster = LiveServePendingCluster(
                bestEvent: candidate,
                firstSeenTimestamp: latestTimestamp,
                lastSeenTimestamp: latestTimestamp,
                observationCount: 1
            )
            pendingClusters.append(newCluster)
            touchedClusterIDs.insert(newCluster.id)
        }

        let emittedServe = emitReadyCluster(
            latestTimestamp: latestTimestamp,
            thresholds: thresholds
        )
        if let emittedServe {
            dedupedCandidates.append(
                contentsOf: discardStalePendingClusters(
                    afterEmitting: emittedServe,
                    thresholds: thresholds
                )
            )
        }
        let heldCandidates = pendingClusters.compactMap { cluster in
            touchedClusterIDs.contains(cluster.id) ? cluster.bestEvent : nil
        }

        return LiveServeEmissionUpdate(
            emittedServe: emittedServe,
            heldCandidates: heldCandidates,
            dedupedCandidates: dedupedCandidates
        )
    }

    private func emitReadyCluster(
        latestTimestamp: Double,
        thresholds: LiveServeEmissionThresholds
    ) -> ServeEvent? {
        let readyIndices = pendingClusters.indices.filter { index in
            latestTimestamp - pendingClusters[index].firstSeenTimestamp >= thresholds.settleSeconds
        }
        guard let emitIndex = readyIndices.min(by: {
            pendingClusters[$0].bestEvent.impactTimeSeconds < pendingClusters[$1].bestEvent.impactTimeSeconds
        }) else {
            return nil
        }

        let emittedServe = pendingClusters.remove(at: emitIndex).bestEvent
        emittedEvents.append(emittedServe)
        return emittedServe
    }

    private func discardStalePendingClusters(
        afterEmitting emittedServe: ServeEvent,
        thresholds: LiveServeEmissionThresholds
    ) -> [ServeEvent] {
        let staleClusters = pendingClusters.filter { cluster in
            cluster.bestEvent.impactTimeSeconds < emittedServe.impactTimeSeconds - thresholds.maximumImpactBacktrackSeconds
        }
        pendingClusters.removeAll { cluster in
            cluster.bestEvent.impactTimeSeconds < emittedServe.impactTimeSeconds - thresholds.maximumImpactBacktrackSeconds
        }
        return staleClusters.map(\.bestEvent)
    }

    private func trimState(endingAt latestTimestamp: Double) {
        emittedEvents.removeAll { event in
            latestTimestamp - event.endTimeSeconds > retentionSeconds
        }
        pendingClusters.removeAll { cluster in
            latestTimestamp - cluster.lastSeenTimestamp > retentionSeconds
        }
    }

    private func isSameServeCluster(
        lhs: ServeEvent,
        rhs: ServeEvent,
        thresholds: LiveServeEmissionThresholds
    ) -> Bool {
        guard lhs.handedness == rhs.handedness else {
            return false
        }

        let impactGap = abs(lhs.impactTimeSeconds - rhs.impactTimeSeconds)
        let trophyGap = abs(lhs.trophyTimeSeconds - rhs.trophyTimeSeconds)
        if impactGap <= thresholds.clusterImpactGapSeconds
            && trophyGap <= thresholds.clusterTrophyGapSeconds
        {
            return true
        }

        let lhsCoreStart = lhs.trophyTimeSeconds - 0.25
        let lhsCoreEnd = lhs.impactTimeSeconds + 0.25
        let rhsCoreStart = rhs.trophyTimeSeconds - 0.25
        let rhsCoreEnd = rhs.impactTimeSeconds + 0.25
        let overlap = min(lhsCoreEnd, rhsCoreEnd) - max(lhsCoreStart, rhsCoreStart)
        return overlap >= thresholds.clusterCoreOverlapSeconds
    }
}
