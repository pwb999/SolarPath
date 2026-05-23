//  SunCalculator.swift
//  SunPathV1 Watch App
//
//  Pure-math SunCalc-style Sun calculations (offline; no JSON)
//  watchOS 11+
//
//  Public API:
//   - computeRealSunDataPrecise(for:latitude:longitude:)
//   - computeRealSunData(for:latitude:longitude:)
//   - computeSunRiseSet(for:latitude:longitude:in:)
//   - computeSolarTransit(for:latitude:longitude:)
//

import Foundation

// MARK: - Tuning

/// Apparent sunrise/sunset altitude threshold (deg).
/// -0.833° is the common standard: refraction (~34') + solar radius (~16').


public let sunRiseSetAltitudeThresholdDeg: Double = -0.833



// MARK: - Public API (position / rise-set / transit)

/// Returns Sun azimuth (deg True, 0..360, N=0 E=90) and altitude (deg).
public func computeRealSunDataPrecise(
    for date: Date,
    latitude: Double,
    longitude: Double
) -> (azimuthDeg: Double, altitudeDeg: Double) {

    // 1) Sun RA/Dec (approx; SunCalc-style)
    let d = daysSinceJ2000(date)
    let sunEq = sunEquatorial(d: d)

    // 2) Convert to horizontal for observer
    let horiz = horizontal(
        raRad: sunEq.raRad,
        decRad: sunEq.decRad,
        date: date,
        latDeg: latitude,
        lonDeg: longitude
    )

    return (
        azimuthDeg: wrap360(rad2deg(horiz.azRad)),
        altitudeDeg: rad2deg(horiz.altRad)
    )
}

/// Int-rounded wrapper for UI display.
public func computeRealSunData(
    for date: Date,
    latitude: Double,
    longitude: Double
) -> (azimuthDeg: Int, altitudeDeg: Int) {
    let p = computeRealSunDataPrecise(for: date, latitude: latitude, longitude: longitude)
    return (Int(p.azimuthDeg.rounded()), Int(p.altitudeDeg.rounded()))
}

/// Sunrise/sunset for the LOCAL DAY containing `date` in the given timezone.
/// Coarse scan (10 min) + bisection refinement to ~1 minute.
public func computeSunRiseSet(
    for date: Date,
    latitude: Double,
    longitude: Double,
    in timeZone: TimeZone
) -> (rise: Date?, set: Date?, riseAz: Int, setAz: Int) {

    let cal = Calendar(identifier: .gregorian)

    // Define the local day window [startLocal, endLocal)
    let startLocal = startOfDay(for: date, timeZone: timeZone)
    guard let endLocal = cal.date(byAdding: .day, value: 1, to: startLocal) else {
        return (nil, nil, 0, 0)
    }

    // Altitude function (minus threshold)
    func altMinusThreshold(_ t: Date) -> Double {
        let alt = computeRealSunDataPrecise(for: t, latitude: latitude, longitude: longitude).altitudeDeg
        return alt - sunRiseSetAltitudeThresholdDeg
    }

    // Bisection refinement within [a,b]
    func refineCrossing(a: Date, b: Date) -> Date {
        var left = a
        var right = b
        var yl = altMinusThreshold(left)

        for _ in 0..<14 {
            let mid = Date(timeIntervalSince1970: (left.timeIntervalSince1970 + right.timeIntervalSince1970) / 2)
            let ym = altMinusThreshold(mid)

            // Keep the half-interval that contains the sign change
            if (yl <= 0 && ym <= 0) || (yl >= 0 && ym >= 0) {
                left = mid
                yl = ym
            } else {
                right = mid
            }
        }
        return right
    }

    // Coarse scan every 10 minutes
    let stepMinutes = 10
    let steps = Int(endLocal.timeIntervalSince(startLocal) / Double(stepMinutes * 60))

    var rise: Date? = nil
    var set: Date? = nil
    var riseAz: Int = 0
    var setAz: Int = 0

    var t0 = startLocal
    var y0 = altMinusThreshold(t0)

    for i in 1...steps {
        guard let t1 = cal.date(byAdding: .minute, value: i * stepMinutes, to: startLocal) else { continue }
        let y1 = altMinusThreshold(t1)

        // rise: below -> above
        if rise == nil, y0 < 0, y1 >= 0 {
            let refined = refineCrossing(a: t0, b: t1)
            rise = refined
            let az = computeRealSunDataPrecise(for: refined, latitude: latitude, longitude: longitude).azimuthDeg
            riseAz = Int(az.rounded())
        }

        // set: above -> below
        if set == nil, y0 >= 0, y1 < 0 {
            let refined = refineCrossing(a: t0, b: t1)
            set = refined
            let az = computeRealSunDataPrecise(for: refined, latitude: latitude, longitude: longitude).azimuthDeg
            setAz = Int(az.rounded())
        }

        if rise != nil && set != nil { break }

        t0 = t1
        y0 = y1
    }

    return (rise, set, riseAz, setAz)
}

/// Solar transit (meridian passage / “solar noon”): time of minimum |hour angle|.
public func computeSolarTransit(
    for date: Date,
    latitude: Double,
    longitude: Double
) -> Date? {

    let cal = Calendar(identifier: .gregorian)
    let base = cal.startOfDay(for: date)

    func absHourAngleDeg(at t: Date) -> Double {
        let d = daysSinceJ2000(t)
        let sun = sunEquatorial(d: d)
        let lst = localSiderealTimeRad(date: t, lonDeg: longitude)
        let ha = normalizePi(lst - sun.raRad) // (-π, +π]
        return abs(rad2deg(ha))
    }

    // Coarse scan every 10 minutes
    var bestT: Date? = nil
    var best = Double.greatestFiniteMagnitude

    for m in stride(from: 0, to: 1440, by: 10) {
        guard let t = cal.date(byAdding: .minute, value: m, to: base) else { continue }
        let v = absHourAngleDeg(at: t)
        if v < best {
            best = v
            bestT = t
        }
    }
    guard let coarse = bestT else { return nil }

    // Refine ±15 minutes by 1 minute
    let start = cal.date(byAdding: .minute, value: -15, to: coarse) ?? coarse
    var refinedBestT = coarse
    var refinedBest = absHourAngleDeg(at: coarse)

    for m in 0...30 {
        guard let t = cal.date(byAdding: .minute, value: m, to: start) else { continue }
        let v = absHourAngleDeg(at: t)
        if v < refinedBest {
            refinedBest = v
            refinedBestT = t
        }
    }

    return refinedBestT
}

// MARK: - Core astronomy (SunCalc-style)

private let eclipticObliquityRad: Double = deg2rad(23.4397) // adequate for watch use

private struct Equatorial {
    let raRad: Double
    let decRad: Double
}

/// Sun RA/Dec (approx).
/// This is the same “SunCalc-style” model you already used: mean anomaly + equation of center.
private func sunEquatorial(d: Double) -> Equatorial {
    // Mean anomaly
    let M = deg2rad(357.5291 + 0.98560028 * d)

    // Equation of center (approx)
    let C = deg2rad(1.9148) * sin(M)
          + deg2rad(0.02)   * sin(2 * M)
          + deg2rad(0.0003) * sin(3 * M)

    // Perihelion and ecliptic longitude
    let P = deg2rad(102.9372)
    let L = M + C + P + .pi  // ecliptic longitude

    // Ecliptic -> equatorial
    let sinL = sin(L), cosL = cos(L)
    let sinE = sin(eclipticObliquityRad), cosE = cos(eclipticObliquityRad)

    var ra = atan2(sinL * cosE, cosL)
    if ra < 0 { ra += 2 * .pi }
    let dec = asin(sinL * sinE)

    return Equatorial(raRad: ra, decRad: dec)
}

private struct Horizontal {
    let azRad: Double
    let altRad: Double
}

/// Converts equatorial RA/Dec to horizontal az/alt for the observer.
/// Azimuth is measured from North, increasing towards East (0..360).
private func horizontal(raRad: Double, decRad: Double, date: Date, latDeg: Double, lonDeg: Double) -> Horizontal {
    let lat = deg2rad(latDeg)
    let lst = localSiderealTimeRad(date: date, lonDeg: lonDeg)
    let H = normalizePi(lst - raRad)

    let sinAlt = sin(lat) * sin(decRad) + cos(lat) * cos(decRad) * cos(H)
    let alt = asin(sinAlt)

    // Azimuth (North=0, East=90)
    let az = atan2(
        sin(H),
        cos(H) * sin(lat) - tan(decRad) * cos(lat)
    ) + .pi

    return Horizontal(azRad: normalize2Pi(az), altRad: alt)
}

// MARK: - Sidereal time

private func localSiderealTimeRad(date: Date, lonDeg: Double) -> Double {
    let jd = julianDay(date)
    let T = (jd - 2451545.0) / 36525.0

    // GMST in degrees (adequate)
    var gmst = 280.46061837
        + 360.98564736629 * (jd - 2451545.0)
        + 0.000387933 * T * T
        - (T * T * T) / 38710000.0

    gmst = gmst.truncatingRemainder(dividingBy: 360)
    if gmst < 0 { gmst += 360 }

    let lstDeg = gmst + lonDeg
    return deg2rad(wrap360(lstDeg))
}

// MARK: - Time base

// days since J2000.0 (2000-01-01 12:00 UTC)
private func daysSinceJ2000(_ date: Date) -> Double {
    julianDay(date) - 2451545.0
}

private func julianDay(_ date: Date) -> Double {
    let cal = Calendar(identifier: .gregorian)
    let tz = TimeZone(secondsFromGMT: 0)!
    let c = cal.dateComponents(in: tz, from: date)

    let Y = c.year ?? 2000
    let M = c.month ?? 1
    let D = Double(c.day ?? 1)
        + Double(c.hour ?? 0) / 24.0
        + Double(c.minute ?? 0) / 1440.0
        + Double(c.second ?? 0) / 86400.0

    var y = Y
    var m = M
    if m <= 2 { y -= 1; m += 12 }

    let A = y / 100
    let B = 2 - A + (A / 4)

    let jd = floor(365.25 * Double(y + 4716))
        + floor(30.6001 * Double(m + 1))
        + D + Double(B) - 1524.5

    return jd
}

// MARK: - Date helpers (local day)

private func startOfDay(for date: Date, timeZone: TimeZone) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timeZone
    return cal.startOfDay(for: date)
}

// MARK: - Small helpers

private func deg2rad(_ d: Double) -> Double { d * .pi / 180.0 }
private func rad2deg(_ r: Double) -> Double { r * 180.0 / .pi }

public func wrap360(_ deg: Double) -> Double {
    var x = deg.truncatingRemainder(dividingBy: 360.0)
    if x < 0 { x += 360.0 }
    return x
}

private func normalize2Pi(_ r: Double) -> Double {
    var v = r.truncatingRemainder(dividingBy: 2 * .pi)
    if v < 0 { v += 2 * .pi }
    return v
}

// normalize to (-π, +π]
private func normalizePi(_ r: Double) -> Double {
    var v = r.truncatingRemainder(dividingBy: 2 * .pi)
    if v <= -Double.pi { v += 2 * .pi }
    if v > Double.pi { v -= 2 * .pi }
    return v
}
