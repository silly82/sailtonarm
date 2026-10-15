// Zweidimensionaler Kalman-Filter für die Uhr des Sendspin-Servers (Versatz
// und Drift), wie ihn die Spezifikation verlangt ("Clock Synchronization").
//
// Übertragen aus SendspinTimeFilter in aiosendspin (client/time_sync.py),
// selbst eine Übertragung der ESPHome-Fassung.
// Urheber: Sendspin Protocol Authors (Open Home Foundation),
// Apache License 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
// Änderungen: nach C++/Qt übertragen, ohne Thread-Sicherheit.

#ifndef TIMEFILTER_H
#define TIMEFILTER_H

#include <QtGlobal>

class TimeFilter
{
public:
    // measurement: Versatz ((T2-T1)+(T3-T4))/2, maxError: halbe Laufzeit
    // ((T4-T1)-(T3-T2))/2, timeAdded: Empfangszeit T4, alles in µs.
    void update(qint64 measurement, qint64 maxError, qint64 timeAdded);
    qint64 computeServerTime(qint64 clientTime) const;
    qint64 computeClientTime(qint64 serverTime) const;
    void reset();

    bool isSynchronized() const;
    // Standardabweichung des Versatzes in µs.
    qint64 error() const;
    int count() const { return m_count; }

private:
    qint64 m_lastUpdate = 0;
    int m_count = 0;
    double m_offset = 0.0;
    double m_drift = 0.0;
    double m_offsetCovariance = 0.0; // gilt erst ab m_count > 0
    double m_offsetDriftCovariance = 0.0;
    double m_driftCovariance = 0.0;

    // Zuletzt gültige Umrechnung.
    qint64 m_elementLastUpdate = 0;
    double m_elementOffset = 0.0;
    double m_elementDrift = 0.0;
    bool m_elementUseDrift = false;
};

#endif // TIMEFILTER_H
