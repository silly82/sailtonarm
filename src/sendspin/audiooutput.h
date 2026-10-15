#ifndef AUDIOOUTPUT_H
#define AUDIOOUTPUT_H

#include <QByteArray>
#include <QString>

#include <atomic>
#include <deque>
#include <mutex>
#include <thread>

struct pa_simple;

// Gibt PCM (16 Bit, little-endian, verschachtelt) zeitgenau über PulseAudio
// aus, Stufe 5c (KONZEPT-ENDPOINT.md). Jeder Chunk trägt die lokale Zeit
// (CLOCK_MONOTONIC, µs), zu der sein erstes Sample erklingen soll. Ein eigener
// Thread schreibt Blöcke zu 10 ms und korrigiert die Lage nach der Vorlage der
// Spezifikation ("Sample deletion and insertion"): kleine Abweichungen um
// einzelne Frames, grosse einmalig durch Stille oder Überspringen.
class AudioOutput
{
public:
    struct Stats {
        qint64 errorUs = 0;     // geglättete Abweichung, + heisst zu früh
        qint64 latencyUs = 0;   // von PulseAudio gemeldet
        int dropped = 0;        // einzeln entfernte Frames
        int duplicated = 0;     // einzeln wiederholte Frames
        int resyncs = 0;        // einmalige Korrekturen
        int underruns = 0;
        int late = 0;           // ganz verspätete, verworfene Chunks
        int queued = 0;         // gepufferte Chunks
    };

    AudioOutput();
    ~AudioOutput();

    bool start(int sampleRate, int channels, QString *error);
    void stop();
    bool isRunning() const { return m_running; }
    int sampleRate() const { return m_rate; }
    int channels() const { return m_channels; }

    void push(qint64 localUs, const QByteArray &pcm);
    void clear();
    // Verstärkung 0..1, bereits als Amplitude.
    void setGain(double gain) { m_gain = gain; }
    Stats stats();

    static qint64 nowUs();

private:
    struct Chunk {
        qint64 localUs;
        QByteArray pcm;
    };

    void run();
    // Füllt out mit frames Frames; verlangt m_mutex.
    void fill(qint16 *out, int frames, qint64 playAtUs);
    qint64 scheduledUs() const;

    pa_simple *m_pa = nullptr;
    std::thread m_thread;
    std::atomic<bool> m_running { false };
    std::atomic<double> m_gain { 1.0 };
    int m_rate = 0;
    int m_channels = 0;

    std::mutex m_mutex;
    std::deque<Chunk> m_queue;
    int m_pos = 0;           // Frames, die vom vordersten Chunk schon weg sind
    bool m_synced = false;   // Lage nach Start/Leerlauf schon festgelegt?
    bool m_flush = false;
    double m_smoothedError = 0.0;
    Stats m_stats;
};

#endif // AUDIOOUTPUT_H
