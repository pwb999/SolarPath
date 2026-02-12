//  ContentView.swift
//  SunPathV1 Watch App
//

import SwiftUI
import WatchKit
import Combine

// MARK: - Theme
let lilacBlue = Color(red: 0.7, green: 0.7, blue: 0.9)

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var locationManager = LocationManager()

    // UI State
    @State private var animate = false
    @State private var currentDate = Date()
    @State private var showSettings = false
    @State private var showCompassGrid = true
    @State private var showRiseSetLines = true
    @State private var selectedTab = 0

    // Refresh flash for Tab 0 time label
    @State private var showRefreshFlash = false

    // Sun events
    @State private var sunrise: String = "–"
    @State private var sunset: String = "–"
    @State private var sunriseAzimuth: Int = 0
    @State private var sunsetAzimuth: Int = 0

    
    @State private var showSunriseSetLines = true
    
    // Timer
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var shadowAzimuth: Int {
        // Opposite direction to the Sun (Sun azimuth + 180), wrapped to 0...359
        (sunAzimuth + 180) % 360
    }
    
    // Compute once per redraw
    private var sunData: (az: Int, alt: Int) {
        let t = computeRealSunData(
            for: currentDate,
            latitude: locationManager.latitude,
            longitude: locationManager.longitude
        )
        return (t.azimuthDeg, t.altitudeDeg)
    }

    var sunAzimuth: Int { sunData.az }
    var sunAltitude: Int { sunData.alt }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {

                // MARK: Tab 0 - Sun Path
                ScrollView {
                    VStack(spacing: 8) {

                        Button {
                            WKInterfaceDevice.current().play(.directionDown)
                            withAnimation { animate.toggle() }
                            refreshFromTitleTap()
                        } label: {
                            Text("Sun Path")
                                .font(.title2)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                                .contentShape(Rectangle())
                                .rotationEffect(.degrees(animate ? 360 : 0))
                                .animation(.easeInOut(duration: 0.6), value: animate)
                        }
                        .buttonStyle(.plain)

                        SunDirectionView(
                            sunAzimuth: sunAzimuth,
                            sunriseAzimuth: sunriseAzimuth,
                            sunsetAzimuth: sunsetAzimuth,
                            showSunriseSetLines: showSunriseSetLines,
                            showCompassGrid: showCompassGrid
                        )
                        .frame(height: 125)
                        .padding(.top, -14)

                        // Time display only; flashes green briefly after refresh
//                        Text(formattedHHMM(currentDate))
//                            .font(.footnote)
//                            .foregroundStyle(showRefreshFlash ? .green : .secondary)
//                            .animation(.easeInOut(duration: 0.25), value: showRefreshFlash)
//                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding()
                }
                .tabItem { Label("Sun Path", systemImage: "circlebadge.fill") }
                .tag(0)

                // MARK: Tab 1 - Times / Bearings
                ScrollView {
                    VStack(spacing: 8) {
                        Text("Bearings")
                            .font(.title3)
                            .foregroundStyle(.primary)

                        Divider()

//                        let visibleNow = isSunVisible(altitude: sunAltitude)

                        Text("Azimuth: \(sunAzimuth)°")
                            .font(.body)
                        Text("Shadow: \(shadowAzimuth)°")
                            .font(.body)
                        Text("Altitude: \(sunAltitude)°")
                            .font(.body)

                        Divider()

                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle")
                                .foregroundColor(.orange)
                            Text(formattedTime(currentDate))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            WKInterfaceDevice.current().play(.directionDown)
                            refreshNow()
                        }
                    }
                    .padding()
                }
                .tabItem { Label("Times", systemImage: "circlebadge.fill") }
                .tag(1)

                // MARK: Tab 3 - Events
                ScrollView {
                    VStack(spacing: 8) {
                        Text("Events")
                            .font(.title3)
                            .foregroundStyle(.primary)

                        Divider()

                        HStack(spacing: 6) {
                            Image(systemName: "sunrise")
                                .foregroundStyle(.green)

                            Text("\(sunrise)  Az: \(String(format: "%03d°", sunriseAzimuth))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "sunset")
                                .foregroundStyle(.red)

                            Text("\(sunset)  Az: \(String(format: "%03d°", sunsetAzimuth))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                        }

                        if let sn = computeSolarTransit(
                            for: currentDate,
                            latitude: locationManager.latitude,
                            longitude: locationManager.longitude
                        ) {
                            Divider()
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.yellow)

                                Text("SN: \(shortFormattedTime(sn))")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                    .padding()
                }
                .tabItem { Label("Sunrise", systemImage: "circlebadge.fill") }
                .tag(3)

                // MARK: Tab 4 - Stats
                ScrollView {
                    VStack(spacing: 8) {

                        // Title + refresh icon
                        HStack {
                            Text("Location")
                                .font(.title3)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .center)

                            Spacer()

                            Button {
                                WKInterfaceDevice.current().play(.directionDown)
                                locationManager.refreshLocation()
                            } label: {
                                Image(systemName: "arrow.clockwise.circle")
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                        }

                        Divider()

                        // Status line directly under divider
                        Text(locationManager.statusText)
                            .font(.caption2)
                            .foregroundStyle(locationManager.isAuthorized ? .green : .orange)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Divider()

                        // One-line GPS display
                        HStack(spacing: 4) {
                            Text("GPS:")
                            Text("\(abs(locationManager.latitude), specifier: "%.2f")\(locationManager.latitude >= 0 ? "N" : "S")")
                            Text("\(abs(locationManager.longitude), specifier: "%.2f")\(locationManager.longitude >= 0 ? "E" : "W")")
                        }
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))

                        // Last fix time (HH:mm)
                        if let t = locationManager.lastFixTime {
                            Text("Last fix: \(formattedHHMM(t))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        let tz = TimeZone.current
                        let abbr = tz.abbreviation() ?? "Unknown"
                        let hoursFromGMT = tz.secondsFromGMT() / 3600

                        (
                            Text("Zone: ")
                                .foregroundStyle(.white.opacity(0.8))
                            + Text("\(abbr) (GMT\(hoursFromGMT >= 0 ? "+" : "")\(hoursFromGMT))")
                                .foregroundStyle(.secondary)
                        )
                        .font(.caption2)
                    }
                    .padding()
                }
                .tabItem { Label("Stats", systemImage: "circlebadge.fill") }
                .tag(4)

                // MARK: Tab 5 - About
                ScrollView {
                    VStack(spacing: 8) {
                        Text("About")
                            .font(.title3)
                            .foregroundStyle(.primary)

                        Divider()

                        (
                            Text("Tip\n")
                                .foregroundStyle(.orange)
                            +
                            Text("""
TAP the app Title to refresh calculations.

Accuracy is within a few degrees/minutes considered suitable for field use.
GPS location is required to calculate events.
""")
                                .foregroundStyle(.white.opacity(0.7))
                        )
                        .font(.caption2)
                        .multilineTextAlignment(.center)

                        Divider()

                        VStack(spacing: 1) {
                            Text("V2.0 • Build 3 • 12 Feb 2026")
                            Text("© 2026 Peter Bleakley")
                            Text("Made in Cumbria")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                .tabItem { Label("About", systemImage: "circlebadge.fill") }
                .tag(5)

                // MARK: Tab 6 - Credits
                ScrollView {
                    VStack(spacing: 6) {
                        Text("Credits")
                            .font(.title3)
                            .foregroundStyle(.primary)

                        Divider()

                        Text("""
This app implements astronomical algorithms inspired by published references.

SunCalc project
© 2011–2015 Vladimir Agafonkin
Released under the MIT License

Jean Meeus
Astronomical Algorithms, 2nd Edition
""")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                }
                .tabItem { Label("Copyright", systemImage: "circlebadge.fill") }
                .tag(6)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .automatic))
            .onAppear {
                refreshNow()
            }
            .onReceive(timer) { _ in
                currentDate = Date()
                updateSunEvents()
            }
            .sheet(isPresented: $showSettings) {
                VStack {
                    Toggle("Rise & Set", isOn: $showRiseSetLines)
                        .font(.footnote)
                        .padding()

                    Toggle("NESW labels", isOn: $showCompassGrid)
                        .font(.footnote)
                        .padding()

                    Button("Done") { showSettings = false }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 6)
                }
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Refresh / Events

    private func refreshFromTitleTap() {
        currentDate = Date()

        showRefreshFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showRefreshFlash = false
        }

        // Ask CoreLocation for a fresh fix
        locationManager.refreshLocation()

        // Recompute now...
        updateSunEvents()

        // ...and again shortly after (GPS fix arrives async)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            updateSunEvents()
        }

        WKInterfaceDevice.current().play(.success)
    }

    private func refreshNow() {
        currentDate = Date()
        updateSunEvents()
        WKInterfaceDevice.current().play(.success)
    }

    private func updateSunEvents() {
        let tz = TimeZone.current

        let rs = computeSunRiseSet(
            for: currentDate,
            latitude: locationManager.latitude,
            longitude: locationManager.longitude,
            in: tz
        )

        sunrise = rs.rise.map { formattedTimeString(for: $0, in: tz) } ?? "–"
        sunset  = rs.set.map  { formattedTimeString(for: $0, in: tz) } ?? "–"

        sunriseAzimuth = rs.riseAz
        sunsetAzimuth  = rs.setAz
    }

    // MARK: - Formatting helpers

    func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yy HH:mm"
        f.timeZone = .current
        return f.string(from: date)
    }

    func shortFormattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "E HH:mm"
        f.timeZone = .current
        return f.string(from: date)
    }

    func formattedHHMM(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = .current
        return f.string(from: date)
    }

    func formattedTimeString(for date: Date, in timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.timeZone = timeZone
        return f.string(from: date)
    }

    // MARK: - Visibility

    func isSunVisible(altitude: Int) -> Bool {
        altitude > 0
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}

// MARK: - SunDirectionView (same look/feel as your Moon graphic)
struct SunDirectionView: View {
    var sunAzimuth: Int
    var sunriseAzimuth: Int
    var sunsetAzimuth: Int
    var showSunriseSetLines: Bool
    var showCompassGrid: Bool

    var body: some View {
        GeometryReader { geo in

            // 🔥 Dynamic scaling based on screen size
            let size = min(geo.size.width, geo.size.height)
            let radius = size * 0.35
            let labelOffset = radius * 0.35
            let crosshair = radius * 1.45
            let compassOffset = radius * 0.9

            let radians = Angle(degrees: Double(sunAzimuth)).radians
            let center = CGPoint(x: geo.size.width / 2,
                                 y: geo.size.height / 2)

            let endX = center.x + radius * CGFloat(sin(radians))
            let endY = center.y - radius * CGFloat(cos(radians))

            let labelX = center.x + (radius + labelOffset) * CGFloat(sin(radians))
            let labelY = center.y - (radius + labelOffset) * CGFloat(cos(radians))

            ZStack {

                // Sunrise / sunset lines
                if showSunriseSetLines {
                    let riseRadians = Angle(degrees: Double(sunriseAzimuth)).radians
                    let setRadians  = Angle(degrees: Double(sunsetAzimuth)).radians

                    Path { path in
                        path.move(to: center)
                        path.addLine(to: CGPoint(
                            x: center.x + radius * CGFloat(sin(riseRadians)),
                            y: center.y - radius * CGFloat(cos(riseRadians))
                        ))
                    }
                    .stroke(Color.green.opacity(0.5), lineWidth: 1.5)

                    Path { path in
                        path.move(to: center)
                        path.addLine(to: CGPoint(
                            x: center.x + radius * CGFloat(sin(setRadians)),
                            y: center.y - radius * CGFloat(cos(setRadians))
                        ))
                    }
                    .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                }

                // Current sun needle
                Path { path in
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: endX, y: endY))
                }
                .stroke(.white, lineWidth: 2)

                HStack(spacing: 2) {
                    Text("\(sunAzimuth)°")
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.orange)
                }
                .font(.caption)
                .position(x: labelX, y: labelY)

                // Crosshair (scaled)
                Rectangle()
                    .frame(width: 1, height: crosshair)
                    .foregroundColor(.gray)
                    .position(center)

                Rectangle()
                    .frame(width: crosshair, height: 1)
                    .foregroundColor(.gray)
                    .position(center)

                // Compass labels
                if showCompassGrid {
                    Group {
                        Text("N").font(.caption2)
                            .foregroundColor(.gray)
                            .position(x: center.x,
                                      y: center.y - compassOffset)

                        Text("S").font(.caption2)
                            .foregroundColor(.gray)
                            .position(x: center.x,
                                      y: center.y + compassOffset)

                        Text("E").font(.caption2)
                            .foregroundColor(.gray)
                            .position(x: center.x + compassOffset,
                                      y: center.y)

                        Text("W").font(.caption2)
                            .foregroundColor(.gray)
                            .position(x: center.x - compassOffset,
                                      y: center.y)
                    }
                }
            }
        }
    }
}
