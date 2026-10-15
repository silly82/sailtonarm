// Übertragen aus aiosendspin (Apache License 2.0), siehe timefilter.h.

#include "timefilter.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace {

const double ProcessVariance = 0.0;                  // process_std_dev 0
const double DriftProcessVariance = 1e-11 * 1e-11;   // drift_process_std_dev
const double ForgetVarianceFactor = 2.0 * 2.0;       // forget_factor 2
const double AdaptiveForgettingCutoff = 3.0;
const double MaxErrorScale = 0.5;
const double DriftSignificanceThresholdSquared = 2.0 * 2.0;

} // namespace

void TimeFilter::update(qint64 measurement, qint64 maxError, qint64 timeAdded)
{
    if (timeAdded <= m_lastUpdate)
        return;
    const double dt = double(timeAdded - m_lastUpdate);
    m_lastUpdate = timeAdded;

    const double updateStdDev = double(maxError) * MaxErrorScale;
    const double measurementVariance = updateStdDev * updateStdDev;

    if (m_count <= 0) {
        // Erste Messung legt den Versatz fest.
        m_count = 1;
        m_offset = double(measurement);
        m_offsetCovariance = measurementVariance;
        m_drift = 0.0;
        m_elementLastUpdate = m_lastUpdate;
        m_elementOffset = m_offset;
        m_elementDrift = 0.0;
        m_elementUseDrift = false;
        return;
    }

    if (m_count == 1) {
        // Zweite Messung: erste Drift aus der Differenz.
        m_count = 2;
        m_drift = (double(measurement) - m_offset) / dt;
        m_offset = double(measurement);
        m_driftCovariance = (m_offsetCovariance + measurementVariance) / (dt * dt);
        m_offsetCovariance = measurementVariance;
        m_elementLastUpdate = m_lastUpdate;
        m_elementOffset = m_offset;
        m_elementDrift = m_drift;
        m_elementUseDrift = false;
        return;
    }

    // Vorhersage.
    const double offset = m_offset + m_drift * dt;
    double newDriftCovariance = m_driftCovariance + dt * DriftProcessVariance;
    double newOffsetDriftCovariance = m_offsetDriftCovariance + m_driftCovariance * dt;
    double newOffsetCovariance = m_offsetCovariance + 2 * m_offsetDriftCovariance * dt
            + m_driftCovariance * dt * dt + dt * ProcessVariance;

    // Innovation und adaptives Vergessen.
    const double residual = double(measurement) - offset;
    if (m_count < 100) {
        ++m_count;
    } else if (std::fabs(residual) > double(maxError) * AdaptiveForgettingCutoff) {
        newDriftCovariance *= ForgetVarianceFactor;
        newOffsetDriftCovariance *= ForgetVarianceFactor;
        newOffsetCovariance *= ForgetVarianceFactor;
    }

    // Korrektur.
    const double uncertainty = 1.0 / std::max(newOffsetCovariance + measurementVariance, 1e-9);
    const double offsetGain = newOffsetCovariance * uncertainty;
    const double driftGain = newOffsetDriftCovariance * uncertainty;
    m_offset = offset + offsetGain * residual;
    m_drift += driftGain * residual;
    m_driftCovariance = newDriftCovariance - driftGain * newOffsetDriftCovariance;
    m_offsetDriftCovariance = newOffsetDriftCovariance - driftGain * newOffsetCovariance;
    m_offsetCovariance = newOffsetCovariance - offsetGain * newOffsetCovariance;

    m_elementLastUpdate = m_lastUpdate;
    m_elementOffset = m_offset;
    m_elementDrift = m_drift;
    m_elementUseDrift = m_drift * m_drift > DriftSignificanceThresholdSquared * m_driftCovariance;
}

qint64 TimeFilter::computeServerTime(qint64 clientTime) const
{
    const double drift = m_elementUseDrift ? m_elementDrift : 0.0;
    const double dt = double(clientTime - m_elementLastUpdate);
    return clientTime + qint64(std::llround(m_elementOffset + drift * dt));
}

qint64 TimeFilter::computeClientTime(qint64 serverTime) const
{
    const double drift = m_elementUseDrift ? m_elementDrift : 0.0;
    return qint64(std::llround((double(serverTime) - m_elementOffset + drift * double(m_elementLastUpdate))
                               / (1.0 + drift)));
}

void TimeFilter::reset()
{
    *this = TimeFilter();
}

bool TimeFilter::isSynchronized() const
{
    return m_count >= 2 && std::isfinite(m_offsetCovariance);
}

qint64 TimeFilter::error() const
{
    if (m_count <= 0)
        return std::numeric_limits<qint64>::max();
    return qint64(std::llround(std::sqrt(m_offsetCovariance)));
}
