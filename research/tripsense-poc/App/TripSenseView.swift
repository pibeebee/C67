import SwiftUI
import MapKit
import TripSenseCore

struct TripSenseView: View {
    @State private var model = TripViewModel()
    @State private var tab = 0
    var body: some View {
        @Bindable var model = model
        TabView(selection: $tab) {
            Tab("Preferences", systemImage: "slider.horizontal.3", value: 0) {
                NavigationStack {
                    Form {
                        Section {
                            Label("TripSense POC", systemImage: "sparkles").font(.title2.bold())
                            Text("On-device reasoning. Real places. Native schedule validation.").foregroundStyle(.secondary)
                        }
                        Section("Starting point") {
                            Toggle("Custom city or starting location", isOn: $model.customOrigin)
                            if model.customOrigin { TextField("City or address", text: $model.city) }
                            else { Text("Jakarta demo scenario · Monas area"); Text("Uses live Apple Maps in live mode; no location permission.").font(.caption) }
                            TextField("Time zone ID", text: $model.timeZoneID).textInputAutocapitalization(.never)
                            Text("Times use \(model.timeZone.identifier). Check the zone for custom destinations.").font(.caption)
                        }
                        Section("Your trip") {
                            Picker("Theme", selection: $model.theme) { ForEach(Theme.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                            TextField("Preferences in English", text: $model.request, axis: .vertical).lineLimit(2 ... 4)
                            DatePicker("Date and start", selection: $model.date).environment(\.timeZone, model.timeZone)
                            Stepper("Duration: \(Int(model.hours)) hours", value: $model.hours, in: 1 ... 12)
                            Picker("Travel", selection: $model.mode) { ForEach(TravelMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                            Stepper("Desired stops: \(model.count)", value: $model.count, in: 1 ... 6)
                            Stepper("Visit: \(Int(model.visitMinutes)) minutes / stop", value: $model.visitMinutes, in: 15 ... 120, step: 15)
                            Stepper("Arrival buffer: \(Int(model.bufferMinutes)) minutes", value: $model.bufferMinutes, in: 0 ... 30, step: 5)
                            Toggle("Require available opening hours", isOn: $model.requireHours)
                            Text("OSM community hours may be outdated and do not guarantee a place is open.").font(.caption)
                        }
                        Section("Execution mode") {
                            Toggle("DEMO ONLY · synthetic fixtures", isOn: $model.demo)
                            Text(model.demo ? "Fixed synthetic places, routes and hours. No AI is used. Jakarta fixtures ignore custom origin." : "Apple Maps and OpenStreetMap use network services. Destination coordinates are sent to OpenStreetMap. Model prompts use English.").font(.caption)
                            if !model.demo { Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!).font(.caption) }
                            Text("Model: \(model.availability)").font(.caption)
                        }
                        if !model.candidatePlaces.isEmpty {
                            Section("Lock places for this trip") {
                                Text("Lock places to preserve them, then recalculate the current itinerary.").font(.caption)
                                ForEach(model.candidatePlaces) { place in
                                    Toggle(place.name, isOn: Binding(get: { model.lockedIDs.contains(place.id) }, set: { model.setLocked(place.id, locked: $0) }))
                                        .disabled(model.busy)
                                }
                                Button("Recalculate with locked places") { model.reoptimize() }.disabled(model.busy)
                            }
                        }
                        Section {
                            Button { model.generate() } label: {
                                Label("Generate My Trip", systemImage: "sparkles").frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent).disabled(model.busy)
                            if model.busy { ProgressView(model.diagnostics.phase); Button("Cancel", role: .cancel) { model.cancel() } }
                            if let error = model.error { Text(error).foregroundStyle(.red) }
                        }
                    }
                    .navigationTitle("Plan a little escape")
                }
            }
            Tab("Itinerary", systemImage: "map", value: 1) {
                NavigationStack {
                    if let itinerary = model.itinerary {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if model.isDemoResult { Label("DEMO ONLY · synthetic data", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.headline) }
                                Map {
                                    if let origin = model.resultOrigin { Marker("Starting point", systemImage: "flag", coordinate: origin.mapCoordinate).tint(.green) }
                                    ForEach(itinerary.stops) { stop in
                                        Marker(stop.place.name, coordinate: stop.place.coordinate.mapCoordinate)
                                        if !stop.leg.geometry.isEmpty {
                                            MapPolyline(coordinates: stop.leg.geometry.map(\.mapCoordinate)).stroke(.blue, lineWidth: 4)
                                        }
                                    }
                                }.mapControls { MapCompass(); MapScaleView() }.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 20))
                                Text("\(itinerary.stops.count) stops · \(itinerary.distance / 1000, specifier: "%.1f") km of routes").font(.title3.bold())
                                Text("Travel \(Int(itinerary.travelTime / 60)) min · visits \(Int(itinerary.visitTime / 60)) min. Buffers and waiting are additional.").font(.subheadline)
                                if let report = itinerary.report {
                                    Text("Compared \(report.evaluatedOrders) orders; validated \(report.validatedAlternatives) schedules.").font(.caption)
                                    if let baseline = report.baselineTravelTime {
                                        Text("Validated baseline: \(Int(baseline / 60)) min · selected: \(Int(itinerary.travelTime / 60)) min").font(.caption)
                                    }
                                    if !report.failures.isEmpty { Text("Some schedules could not be validated; results cover available alternatives.").font(.caption).foregroundStyle(.orange) }
                                }
                                Text("Best among validated schedules. No return leg. Travel times are estimates; unknown hours require checking.").font(.caption).foregroundStyle(.secondary)
                                ForEach(Array(itinerary.stops.enumerated()), id: \.element.id) { index, stop in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(index + 1). \(stop.place.name)").font(.headline)
                                        Text("\(time(stop.arrival)) – \(time(stop.departure))")
                                        Text("\(stop.leg.mode.rawValue.capitalized): \(stop.leg.distance / 1000, specifier: "%.1f") km · \(Int(stop.leg.travelTime / 60)) min").font(.subheadline)
                                        Text(stop.place.category).font(.caption).foregroundStyle(.secondary)
                                        Text(stop.reason)
                                        Text("Model interpretation / fixture reason; thematic tags: \(stop.place.themes.map(\.rawValue).sorted().joined(separator: ", "))").font(.caption)
                                        Text(stop.hours.label).font(.caption).foregroundStyle(.orange)
                                        if case let .sourced(_, metadata) = stop.hours {
                                            Text("Retrieved \(metadata.fetchedAt.formatted(date: .abbreviated, time: .shortened)); community data, not a venue verification.").font(.caption2)
                                        }
                                        if let source = model.osmSource(for: stop.id) { Link("OpenStreetMap source", destination: source).font(.caption) }
                                        if let website = model.osmWebsite(for: stop.id) { Link("Website listed on OpenStreetMap", destination: website).font(.caption) }
                                        if let website = stop.place.websiteURL, ["http", "https"].contains(website.scheme?.lowercased() ?? ""), website.host != nil {
                                            Link("Website listed on Apple Maps", destination: website).font(.caption)
                                        }
                                        Text("Data: \(stop.place.provenance); route: \(stop.leg.provenance)").font(.caption2).foregroundStyle(.secondary)
                                        Button("Remove and recalculate", role: .destructive) { model.remove(stop) }.disabled(model.busy)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                                }
                                if model.busy { ProgressView(model.diagnostics.phase) }
                                if let error = model.error { Text(error).foregroundStyle(.red) }
                            }.padding()
                        }.navigationTitle("Your itinerary")
                    } else { ContentUnavailableView("Your trip starts here", systemImage: "map", description: Text("Generate a trip from Preferences.")) }
                }
            }
            Tab("Diagnostics", systemImage: "stethoscope", value: 2) {
                NavigationStack {
                    List {
                        Section("Device capabilities") {
                            Text("Foundation Model: \(model.availability)")
                            Text(model.languages)
                            Text("On-device inference; MapKit network services. No location permission, backend or API key.")
                        }
                        Section("Overpass network comparison") { OSMProbeControls() }
                        Section("Actual events · current run") {
                            if model.diagnostics.events.isEmpty { Text("No experiment executed yet.") }
                            ForEach(model.diagnostics.events) { Text($0.message).font(.caption.monospaced()).textSelection(.enabled) }
                        }
                    }.navigationTitle("Developer diagnostics")
                }
            }
        }
        .onChange(of: model.itinerary?.stops.map(\.id)) { _, new in if new != nil { tab = 1 } }
        .onDisappear { model.cancel() }
    }
    private func time(_ date: Date) -> String {
        { let formatter = DateFormatter(); formatter.timeZone = model.resultTimeZone; formatter.dateFormat = "HH:mm z"; return formatter.string(from: date) }()
    }
}
