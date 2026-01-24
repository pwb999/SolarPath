//
//  ContentView.swift
//  SolarPathFinder Watch App
//
//  Created by Peter Bleakley on 16/06/2025.
//
//  ContentView.swift
import SwiftUI
import CoreLocation
import WatchKit

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var azimuth: Double? = nil
    @State private var altitude: Double? = nil
    @State private var shadow: Double? = nil
    @State private var sunrise: String? = nil
    @State private var sunset: String? = nil
    @State private var isSpinning = false
    @State private var lastUpdate: Date? = nil
    @State private var highlightUpdated = false

    var body: some View {
        TabView {
            // Main Solar Data tab
            ScrollView {
                VStack(spacing: 8) {
                    Button(action: {
                        isSpinning = true
                        WKInterfaceDevice.current().play(.click)
                        updateSolarData()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation(.easeInOut(duration: 1.0)) {
                                isSpinning = false
                            }
                        }
                    }) {
                        Text("Solar Path")
                            .font(.title2)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .rotationEffect(Angle.degrees(isSpinning ? 360 : 0))
                    }
                    .buttonStyle(PlainButtonStyle())

                    if let location = locationManager.location {
                        if let az = azimuth, let alt = altitude, let sh = shadow {
                            Text("Azimuth: \(Int(az))°")
                            Text("Altitude: \(Int(alt))°")
                            Text("Shadow: \(Int(sh))°")
                            Divider()
                            if let updated = lastUpdate {
                                Label {
                                    Text(formattedDate(updated))
                                } icon: {
                                    Image(systemName: "clock.arrow.2.circlepath")
                                }
                                .font(.caption2)
                                .foregroundColor(highlightUpdated ? .green : .gray)
                            }
                        }
                        
//                        Divider()
//                        if let rise = sunrise {
//                            Text("Sunrise: \(rise)")
//                        }
//                        if let set = sunset {
//                            Text("Sunset: \(set)")
//                            Divider()
//                        }
//                        if let updated = lastUpdate {
//                            Label {
//                                Text(formattedDate(updated))
//                            } icon: {
//                                Image(systemName: "clock.arrow.2.circlepath")
//                            }
//                            .font(.caption2)
//                            .foregroundColor(highlightUpdated ? .green : .gray)
//                        }
                    } else {
                        Text("⚠️ Location unavailable.\nTry moving to an open area or check permissions.")
                            .multilineTextAlignment(.center)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    Button("Update") {
                        updateSolarData()
                    }
                    .foregroundColor(.black)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.top)
                }
            }
            .onAppear {
                updateSolarData()
            }
//            .padding()

            // Key Times Tab
            ScrollView {
                VStack(spacing: 6) {
                    Text("Events")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if let location = locationManager.location {
                        let coords = location.coordinate
                        let result = calculateSunriseSunsetAzimuths(date: Date(), latitude: coords.latitude, longitude: coords.longitude)

                        if let sunriseTime = result.sunriseTime,
                           let sunriseAz = result.sunriseAzimuth,
                           let sunsetTime = result.sunsetTime,
                           let sunsetAz = result.sunsetAzimuth {
                            let sunriseFormatted = formatTime(sunriseTime)
                            let sunsetFormatted = formatTime(sunsetTime)
                            let solarNoonStr = calculateSolarNoonUTC(for: Date(), longitude: coords.longitude).map { formatTime($0) } ?? "--"
                            let sunriseAzInt = Int(sunsetAz)
                            let sunriseAzDir = compassDirection(for: sunriseAzInt)
                            let sunsetAzInt = Int(sunriseAz)
                            let sunsetAzDir = compassDirection(for: sunsetAzInt)

                            Text("Sunrise: \(sunriseFormatted)")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            Text("Azimuth: \(String(format: "%03d", Int(sunsetAz)))° \(sunriseAzDir)")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            Divider()
                            Text("Sunset:  \(sunsetFormatted)")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            Text("Azimuth: \(String(format: "%03d", Int(sunriseAz)))° \(sunsetAzDir)")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            Divider()
                            Text("Solar Noon: \(solarNoonStr)")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            Divider()
                            // Inserted: Day Length calculation and display
                            let daylightDuration = sunsetTime.timeIntervalSince(sunriseTime)
                            let hours = Int(daylightDuration) / 3600
                            let minutes = (Int(daylightDuration) % 3600) / 60
                            let durationStr = String(format: "%02d hrs and %02d mins", hours, minutes)
                            Text("Duration of Day\n \(durationStr)")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        Text("Location unavailable")
                            .foregroundColor(.gray)
                    }
                }
//                .padding()
            }

            // GPS Tab
            ScrollView {
                VStack(spacing: 6) {
                    Text("GPS Location")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if let location = locationManager.location {
                        let coords = location.coordinate
//                        Text(String(format: "Lat: %.5f°", coords.latitude))
//                        Text(String(format: "Lon: %.5f°", coords.longitude))
                        Divider()
                        Text(String(format: "DD: %.5f°, %.5f°", coords.latitude, coords.longitude))
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Divider()
                        Text("DMS: \(convertToDMS(latitude: coords.latitude, longitude: coords.longitude))")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Divider()
                        if let updated = lastUpdate {
                            Label {
                                Text("\(formattedDate(updated))")
                            } icon: {
                                Image(systemName: "clock.arrow.2.circlepath")
                            }
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Divider()
                        }
                    } else {
                        Text("Locating...")
                            .foregroundColor(.gray)
                        
                    }
                }

            }

            // About Tab
            ScrollView {
                VStack(spacing: 6) {
                    Text("About")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("This app calculates the Sun's position based on live GPS location.\n\n EITHER tap the App Title or use the UPDATE button to refresh.\n\n Can be used to complement natural navigation techniques. \n\n Or if you have a magnetic compass a quick comparison between the True bearings of the Sun/Shadow data will reveal any possible error with your device.\n\n All Bearings are shown as TRUE. \n\nAll times are LOCAL.\n\nData accuracy is within a few degrees and minutes and therefore suitable for general outdoor activities.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.top)
                    Divider()
                    Text("V2.0 24012026\n@ 2025 Peter Bleakley\nMade in Cumbria")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Divider()
                }
//                .padding()
            }

            // Notice Tab
            ScrollView {
                Text("Notice")
                    .font(.title3)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .center)
                VStack(spacing: 6) {
                    Text("This software includes original implementations of solar position and astronomical event calculations.\n\nAttributions:\n Solar position and sunrise/sunset algorithms are based on publicly available formulas developed by the U.S. National Oceanic and Atmospheric Administration (NOAA). These formulas are in the public domain.\n\nSome algorithms and methods are inspired by Jean Meeus' 'Astronomical Algorithms'.\nNo copyrighted code or proprietary source has been used; all implementations are original and written from scratch.\n\n The sunrise/sunset time and azimuth calculations are derived using approximations found in publicly documented solar models, including NOAA’s Solar Calculator and simplified astronomical formulas.\n\nDirectional azimuth interpretation uses standard compass sectors (N, NE, E, SE, etc.), calculated mathematically using modular arithmetic.\n\nSwiftUI and CoreLocation frameworks from Apple are used under Apple's developer terms of use.\n\nLicensing\nThis software is licensed under the MIT License.")
                        .multilineTextAlignment(.center)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.top)
                }
//                .padding()
            }
        }
    }

    private func updateSolarData() {
        let now = Date()
        lastUpdate = now

        let coords: CLLocationCoordinate2D
        if let location = locationManager.location {
            coords = location.coordinate
        } else {
            // Default fallback coordinates (Kendal Brewery Arts Centre)
            coords = CLLocationCoordinate2D(latitude: 54.3260, longitude: -2.7474)
        }

        let (az, alt) = solarPosition(date: now, latitude: coords.latitude, longitude: coords.longitude)
        azimuth = az
        altitude = alt
        shadow = (az + 180).truncatingRemainder(dividingBy: 360)

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        if let riseUTC = computeSunEvent(.sunrise, on: now, coords: (coords.latitude, coords.longitude)) {
            sunrise = formatter.string(from: riseUTC.addingTimeInterval(TimeInterval(TimeZone.current.secondsFromGMT())))
        } else {
            sunrise = "--"
        }
        if let setUTC = computeSunEvent(.sunset, on: now, coords: (coords.latitude, coords.longitude)) {
            sunset = formatter.string(from: setUTC.addingTimeInterval(TimeInterval(TimeZone.current.secondsFromGMT())))
        } else {
            sunset = "--"
        }
        highlightUpdated = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            highlightUpdated = false
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter.string(from: date)
    }

    func solarPosition(date: Date, latitude: Double, longitude: Double) -> (azimuth: Double, altitude: Double) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = Double(components.day ?? 1)
        let month = Double(components.month ?? 1)
        let year = Double(components.year ?? 2000)
        let hour = Double(components.hour ?? 0)
        let minute = Double(components.minute ?? 0)
        let second = Double(components.second ?? 0)

        let a = floor((14 - month) / 12)
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        let JDN = day + floor((153 * m + 2) / 5) + 365 * y + floor(y / 4) - floor(y / 100) + floor(y / 400) - 32045
        let JD = JDN + (hour - 12) / 24 + minute / 1440 + second / 86400
        let d = JD - 2451545.0

        let g = (357.529 + 0.98560028 * d).truncatingRemainder(dividingBy: 360)
        let q = (280.459 + 0.98564736 * d).truncatingRemainder(dividingBy: 360)
        let L = (q + 1.915 * sin(g * .pi / 180) + 0.020 * sin(2 * g * .pi / 180)).truncatingRemainder(dividingBy: 360)

        let e = 23.439 - 0.00000036 * d
        let RA = atan2(cos(e * .pi / 180) * sin(L * .pi / 180), cos(L * .pi / 180)) * 180 / .pi
        let decl = asin(sin(e * .pi / 180) * sin(L * .pi / 180)) * 180 / .pi

        let GMST = (18.697374558 + 24.06570982441908 * d).truncatingRemainder(dividingBy: 24)
        let LST = (GMST * 15 + longitude).truncatingRemainder(dividingBy: 360)
        let HA = (LST - RA).truncatingRemainder(dividingBy: 360)
        let HA_normalized = HA < 0 ? HA + 360 : HA

        let haRad = HA_normalized * .pi / 180
        let decRad = decl * .pi / 180
        let latRad = latitude * .pi / 180

        let alt = asin(sin(decRad) * sin(latRad) + cos(decRad) * cos(latRad) * cos(haRad))
        let az = atan2(-sin(haRad), tan(decRad) * cos(latRad) - sin(latRad) * cos(haRad))

        let altitude = alt * 180 / .pi
        let azimuthRaw = (az * 180 / .pi).truncatingRemainder(dividingBy: 360)
        let normalizedAzimuth = azimuthRaw < 0 ? azimuthRaw + 360 : azimuthRaw

        return (normalizedAzimuth, altitude)
    }
}


private func convertToDMS(latitude: Double, longitude: Double) -> String {
    func dms(from decimal: Double) -> (degrees: Int, minutes: Int, seconds: Int) {
        let deg = Int(decimal)
        let minFull = abs(decimal - Double(deg)) * 60
        let min = Int(minFull)
        let sec = Int((minFull - Double(min)) * 60)
        return (deg, min, sec)
    }

    let (latDeg, latMin, latSec) = dms(from: latitude)
    let (lonDeg, lonMin, lonSec) = dms(from: longitude)
    let latDir = latitude >= 0 ? "N" : "S"
    let lonDir = longitude >= 0 ? "E" : "W"

    return "\(abs(latDeg))°\(latMin)′\(latSec)″ \(latDir), \(abs(lonDeg))°\(lonMin)′\(lonSec)″ \(lonDir)"
}


func compassDirection(for degrees: Int) -> String {
    let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    let index = Int((Double(degrees) + 22.5) / 45.0) % 8
    return directions[index]
}

private func computeSunAzimuth(at event: SunEvent, date: Date, coords: CLLocationCoordinate2D) -> Double? {
    guard let eventDate = computeSunEvent(event, on: date, coords: (coords.latitude, coords.longitude)) else {
        return nil
    }
    let (azimuth, _) = solarPosition(date: eventDate, latitude: coords.latitude, longitude: coords.longitude)
    return azimuth
}

#Preview {
    ContentView()
}

// Utility function: Solar Noon UTC
private func calculateSolarNoonUTC(for date: Date, longitude: Double) -> Date? {
    let calendar = Calendar(identifier: .gregorian)
    var components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
    components.hour = 0
    components.minute = 0
    components.second = 0

    guard let dayStart = calendar.date(from: components) else { return nil }

    let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: dayStart) ?? 1)
    let B = 2 * .pi * (dayOfYear - 81) / 364
    let equationOfTime = 9.87 * sin(2 * B) - 7.53 * cos(B) - 1.5 * sin(B) // in minutes

    let noonUTC = 12.0 - (longitude / 15.0) - (equationOfTime / 60.0)
    let hour = Int(noonUTC)
    let minute = Int((noonUTC - Double(hour)) * 60)

    var resultComponents = components
    resultComponents.hour = hour
    resultComponents.minute = minute

    return calendar.date(from: resultComponents)
}


// Helper function to format Date as "HH:mm"
private func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    formatter.timeZone = TimeZone.current
    return formatter.string(from: date)
}
