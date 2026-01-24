//  Created by Peter Bleakley on 16/06/2025.
//  SunCalculator.swift



import Foundation

func solarPosition(date: Date, latitude: Double, longitude: Double) -> (azimuth: Double, altitude: Double) {
    // Basic NOAA-based approximation for azimuth and altitude
    let calendar = Calendar(identifier: .gregorian)
    let components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)

    let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
    let hour = Double(components.hour ?? 12)
    let minute = Double(components.minute ?? 0)
    let second = Double(components.second ?? 0)
    let decimalHours = hour + minute / 60 + second / 3600

    // Declination of the sun (simplified)
    let decl = -23.44 * cos(.pi * 2 * (dayOfYear + 10) / 365)
    let latRad = latitude * .pi / 180
    let declRad = decl * .pi / 180
    let hourAngle = (decimalHours - 12) * 15 * .pi / 180

    // Altitude angle
    let altitudeRad = asin(sin(latRad) * sin(declRad) + cos(latRad) * cos(declRad) * cos(hourAngle))
    let altitude = altitudeRad * 180 / .pi

    // Azimuth angle from true north
    var azimuthRad = atan2(sin(hourAngle), cos(hourAngle) * sin(latRad) - tan(declRad) * cos(latRad))
    var azimuth = azimuthRad * 180 / .pi
    if azimuth < 0 { azimuth += 360 }

    return (azimuth, altitude)
}

func computeSunEvent(_ event: SunEvent, on date: Date, coords: (lat: Double, lon: Double)) -> Date? {
    let calendar = Calendar(identifier: .gregorian)
    let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
    let lngHour = coords.lon / 15

    let t = (event == .sunrise ? dayOfYear + ((6 - lngHour) / 24) : dayOfYear + ((18 - lngHour) / 24))
    let M = (0.9856 * t) - 3.289

    let L = M + (1.916 * sin(M * .pi / 180)) + (0.020 * sin(2 * M * .pi / 180)) + 282.634
    let RA = atan(0.91764 * tan(L * .pi / 180)) * 180 / .pi
    let sinDec = 0.39782 * sin(L * .pi / 180)
    let cosDec = cos(asin(sinDec))
    let cosH = (cos(90.833 * .pi / 180) - (sinDec * sin(coords.lat * .pi / 180))) / (cosDec * cos(coords.lat * .pi / 180))

    guard abs(cosH) <= 1 else { return nil }

    let H = (event == .sunrise ? 360 - acos(cosH) * 180 / .pi : acos(cosH) * 180 / .pi) / 15
    let T = H + RA / 15 - (0.06571 * t) - 6.622
    let UT = (T - lngHour).truncatingRemainder(dividingBy: 24)

    var components = calendar.dateComponents([.year, .month, .day], from: date)
    components.hour = Int(UT)
    components.minute = Int((UT - Double(Int(UT))) * 60)

    return calendar.date(from: components)
}

enum SunEvent {
    case sunrise
    case sunset
}
// Returns sunrise/sunset times and azimuths for the given date and location.
func calculateSunriseSunsetAzimuths(date: Date, latitude: Double, longitude: Double) -> (sunriseTime: Date?, sunriseAzimuth: Double?, sunsetTime: Date?, sunsetAzimuth: Double?) {
    let calendar = Calendar(identifier: .gregorian)
    var components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
    components.hour = 0
    components.minute = 0
    components.second = 0

    guard let dayStart = calendar.date(from: components) else {
        return (nil, nil, nil, nil)
    }

    let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: dayStart) ?? 1)

    // Latitude and declination in radians
    let latRad = latitude * .pi / 180
    let declDeg = -23.44 * cos((360 / 365) * (.pi / 180) * (dayOfYear + 10))
    let declRad = declDeg * .pi / 180

    // Altitude at sunrise/sunset including refraction and solar radius
    let h0 = -0.833 * .pi / 180

    // Cosine of hour angle
    let cosH = (sin(h0) - sin(latRad) * sin(declRad)) / (cos(latRad) * cos(declRad))
    guard abs(cosH) <= 1 else {
        return (nil, nil, nil, nil) // Sun does not rise or set
    }

    let H = acos(cosH) // in radians
    let Hdeg = H * 180 / .pi

    // Solar noon in fractional UTC hours
    let solarNoonUTC = 12.0 - longitude / 15.0
    let deltaT = Hdeg / 15.0

    // Sunrise and sunset UTC
    let sunriseUTC = solarNoonUTC - deltaT
    let sunsetUTC  = solarNoonUTC + deltaT

    // Azimuths at horizon crossing
    let sunriseAzimuth = 360 - acos((sin(declRad) - sin(latRad) * sin(h0)) / (cos(latRad) * cos(h0))) * 180 / .pi
    let sunsetAzimuth  = acos((sin(declRad) - sin(latRad) * sin(h0)) / (cos(latRad) * cos(h0))) * 180 / .pi

    // Convert fractional hours to Date
    func timeFromUTCHours(_ hours: Double) -> Date? {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        var comp = components
        comp.hour = h
        comp.minute = m
        return calendar.date(from: comp)
    }

    return (
        sunriseTime: timeFromUTCHours(sunriseUTC),
        sunriseAzimuth: sunriseAzimuth,
        sunsetTime: timeFromUTCHours(sunsetUTC),
        sunsetAzimuth: sunsetAzimuth
    )
}
