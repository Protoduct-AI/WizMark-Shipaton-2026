import CoreLocation
import MapKit
import SwiftUI
import os

/// A small map of the place a bookmark points at.
///
/// The extracted address answers "where", but only if you already know the area.
/// A map answers it at a glance, which is the difference between a saved café
/// and one you will actually go to.
///
/// Built on MapKit rather than an embedded web map: no API key, no web view, and
/// it follows the system appearance for free. The address is geocoded on first
/// appearance — the extractor returns a written address, not coordinates.
///
/// Renders nothing until geocoding succeeds. A blank frame where a map should be
/// reads worse than no map at all, and an address that cannot be located is
/// common enough (fictional places, partial addresses) to be worth handling
/// quietly.
struct PlaceMapView: View {

    let places: [ExtractedPlace]

    private struct Located: Identifiable {
        let id: Int
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    @State private var located: [Located] = []
    @State private var didAttempt = false

    private static let logger = Logger(
        subsystem: "com.protoductai.wizmark",
        category: "PlaceMap"
    )

    var body: some View {
        // The placeholder is not decoration: a `Group` that resolves to nothing
        // is never laid out, and `.task` attached to it never runs — which left
        // the geocode unstarted and the map permanently absent.
        ZStack {
            if !located.isEmpty {
                Map(initialPosition: .region(regionCovering(located))) {
                    ForEach(located) { place in
                        Marker(place.name, systemImage: "mappin", coordinate: place.coordinate)
                    }
                }
                .frame(height: located.count > 1 ? 220 : 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                // A preview, not something to pan inside a scrolling screen;
                // tapping a place hands off to a maps app instead.
                .allowsHitTesting(false)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task {
            guard !didAttempt else { return }
            didAttempt = true
            await locate()
        }
    }

    private func locate() async {
        // Sequential rather than concurrent: CLGeocoder throttles, and a
        // round-up of twenty places would trip the limit and return nothing.
        var found: [Located] = []
        for (index, place) in places.enumerated() {
            guard let query = MapLauncher.plainQuery(
                placeName: place.name,
                address: place.address
            ) else { continue }

            do {
                let marks = try await CLGeocoder().geocodeAddressString(query)
                guard let coordinate = marks.first?.location?.coordinate else { continue }
                found.append(
                    Located(
                        id: index,
                        name: place.displayName ?? "",
                        coordinate: coordinate
                    )
                )
            } catch {
                // A place that cannot be located just does not get a pin.
                Self.logger.info("Geocoding found nothing for \(query, privacy: .public)")
            }
        }
        located = found
    }

    /// A region holding every pin, with room around the edges.
    private func regionCovering(_ places: [Located]) -> MKCoordinateRegion {
        let coordinates = places.map(\.coordinate)
        guard let first = coordinates.first else {
            return MKCoordinateRegion()
        }
        guard coordinates.count > 1 else {
            return MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min() ?? first.latitude
        let maxLat = latitudes.max() ?? first.latitude
        let minLon = longitudes.min() ?? first.longitude
        let maxLon = longitudes.max() ?? first.longitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.004),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.004)
            )
        )
    }
}
