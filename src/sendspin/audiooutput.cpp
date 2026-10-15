#include "audiooutput.h"

#include <pulse/error.h>
#include <pulse/simple.h>

#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <vector>

namespace {

const int BlockMs = 10;
// Innerhalb dieses Bands bleibt die Ausgabe unverändert. Die Vorlage nimmt
// ~100 µs; hier pendelte die geglättete Abweichung dann ständig über die
// Grenze und es wurde rund 50-mal je Sekunde ein Frame korrigiert.
const double DeadBandUs = 1000.0;
// Liegt die geglättete Abweichung darüber, wird nicht mehr Frame für Frame
// korrigiert, sondern einmalig neu ausgerichtet (mit hörbarem Sprung).
const double ResyncUs = 50000.0;
// Glättung der gemessenen Abweichung, je Block (Zeitkonstante etwa 10 s).
// Auf sink.deep_buffer driftet die von PulseAudio gemeldete Latenz um etwa
// 2 ms/s und springt alle paar Sekunden um rund 13 ms zurück; der Lautsprecher
// selbst läuft gleichmäßig. Erst über mehrere solcher Zyklen gemittelt
// bleibt die echte Abweichung übrig.
const double Smoothing = 0.001;

// Mit SENDSPIN_AUDIO_TRACE=1 schreibt die Ausgabe je Block eine Zeile nach
// stderr (nur für die Probe, zur Fehlersuche).
const bool Trace = std::getenv("SENDSPIN_AUDIO_TRACE") != nullptr;

} // namespace

AudioOutput::AudioOutput() = default;

AudioOutput::~AudioOutput()
{
    stop();
}

qint64 AudioOutput::nowUs()
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return qint64(ts.tv_sec) * 1000000 + ts.tv_nsec / 1000;
}

bool AudioOutput::start(int sampleRate, int channels, QString *error)
{
    stop();
    pa_sample_spec spec;
    spec.format = PA_SAMPLE_S16LE;
    spec.rate = uint32_t(sampleRate);
    spec.channels = uint8_t(channels);
    const uint32_t frameBytes = uint32_t(2 * channels);
    const uint32_t blockBytes = uint32_t(sampleRate / 1000 * BlockMs) * frameBytes;

    pa_buffer_attr attr;
    attr.maxlength = uint32_t(-1);
    attr.tlength = blockBytes * 8;   // etwa 80 ms bei PulseAudio
    attr.prebuf = uint32_t(-1);
    attr.minreq = blockBytes;
    attr.fragsize = uint32_t(-1);

    // Die Audio-Richtlinie von Sailfish ordnet Ströme nach media.role.
    setenv("PULSE_PROP_media.role", "music", 0);
    int err = 0;
    m_pa = pa_simple_new(nullptr, "Tonarm", PA_STREAM_PLAYBACK, nullptr, "Sendspin", &spec,
                         nullptr, &attr, &err);
    if (!m_pa) {
        if (error)
            *error = QString::fromUtf8(pa_strerror(err));
        return false;
    }
    m_rate = sampleRate;
    m_channels = channels;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_queue.clear();
        m_pos = 0;
        m_synced = false;
        m_smoothedError = 0.0;
        m_stats = Stats();
    }
    m_running = true;
    m_thread = std::thread(&AudioOutput::run, this);
    return true;
}

void AudioOutput::stop()
{
    if (!m_running && !m_pa)
        return;
    m_running = false;
    if (m_thread.joinable())
        m_thread.join();
    if (m_pa) {
        int err = 0;
        pa_simple_flush(m_pa, &err);
        pa_simple_free(m_pa);
        m_pa = nullptr;
    }
    std::lock_guard<std::mutex> lock(m_mutex);
    m_queue.clear();
    m_pos = 0;
    m_synced = false;
}

void AudioOutput::push(qint64 localUs, const QByteArray &pcm)
{
    if (!m_running || pcm.isEmpty())
        return;
    std::lock_guard<std::mutex> lock(m_mutex);
    m_queue.push_back(Chunk { localUs, pcm });
}

void AudioOutput::clear()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_queue.clear();
    m_pos = 0;
    m_synced = false;
    m_flush = true;
}

AudioOutput::Stats AudioOutput::stats()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    Stats s = m_stats;
    s.errorUs = qint64(m_smoothedError);
    s.queued = int(m_queue.size());
    return s;
}

qint64 AudioOutput::scheduledUs() const
{
    const Chunk &c = m_queue.front();
    return c.localUs + qint64(m_pos) * 1000000 / m_rate;
}

void AudioOutput::run()
{
    const int frames = m_rate / 1000 * BlockMs;
    std::vector<qint16> block(size_t(frames * m_channels));
    while (m_running) {
        int err = 0;
        bool flush = false;
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            flush = m_flush;
            m_flush = false;
        }
        if (flush)
            pa_simple_flush(m_pa, &err);
        const pa_usec_t latency = pa_simple_get_latency(m_pa, &err);
        const qint64 playAt = nowUs() + qint64(latency);
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_stats.latencyUs = qint64(latency);
            fill(block.data(), frames, playAt);
        }
        const double gain = m_gain;
        if (gain < 0.9999) {
            for (qint16 &s : block)
                s = qint16(std::lround(s * gain));
        }
        if (pa_simple_write(m_pa, block.data(), block.size() * sizeof(qint16), &err) < 0)
            break;
    }
}

void AudioOutput::fill(qint16 *out, int frames, qint64 playAtUs)
{
    const int ch = m_channels;
    std::memset(out, 0, size_t(frames * ch) * sizeof(qint16));
    int written = 0;
    bool measured = false;

    // Frame-Zeit in µs, für die Umrechnung von Abweichungen in Frames.
    auto usToFrames = [this](double us) { return int(std::llround(us * m_rate / 1000000.0)); };

    while (written < frames) {
        // Ganz verspätete Chunks verwerfen.
        while (!m_queue.empty()) {
            const Chunk &c = m_queue.front();
            const int chunkFrames = c.pcm.size() / (2 * ch);
            const qint64 endUs = c.localUs + qint64(chunkFrames) * 1000000 / m_rate;
            const qint64 here = playAtUs + qint64(written) * 1000000 / m_rate;
            if (m_pos >= chunkFrames || (!m_synced && endUs <= here)) {
                if (m_pos < chunkFrames)
                    ++m_stats.late;
                m_queue.pop_front();
                m_pos = 0;
                continue;
            }
            break;
        }
        if (m_queue.empty()) {
            if (m_synced)
                ++m_stats.underruns;
            m_synced = false;
            return; // Rest bleibt Stille
        }

        const qint64 here = playAtUs + qint64(written) * 1000000 / m_rate;
        const double error = double(scheduledUs() - here); // + zu früh
        if (m_synced && !measured) {
            // Einmal je Block messen und höchstens um einen Frame korrigieren:
            // 0,2 %, unter der Grenze von 0,5 % aus der Spezifikation.
            measured = true;
            m_smoothedError += Smoothing * (error - m_smoothedError);
            if (Trace)
                std::fprintf(stderr, "T %lld lat=%lld err=%.0f sm=%.0f q=%d\n",
                             (long long)nowUs(), (long long)(playAtUs - nowUs()), error,
                             m_smoothedError, int(m_queue.size()));
            if (std::fabs(m_smoothedError) > ResyncUs) {
                ++m_stats.resyncs;
                m_synced = false;
            } else if (m_smoothedError < -DeadBandUs) {
                ++m_pos;            // zu spät: einen Frame weglassen
                ++m_stats.dropped;
                m_smoothedError += 1000000.0 / m_rate;
                continue;
            } else if (m_smoothedError > DeadBandUs) {
                // zu früh: den nächsten Frame doppelt ausgeben
                const qint16 *src = reinterpret_cast<const qint16 *>(m_queue.front().pcm.constData())
                        + m_pos * ch;
                std::memcpy(out + written * ch, src, size_t(ch) * sizeof(qint16));
                ++written;
                ++m_stats.duplicated;
                m_smoothedError -= 1000000.0 / m_rate;
            }
        }
        if (!m_synced) {
            // Nach Start, Leerlauf oder großer Abweichung: Lage neu festlegen.
            if (Trace)
                std::fprintf(stderr, "R %lld err=%.0f\n", (long long)nowUs(), error);
            const int skip = usToFrames(-error);
            if (skip > 0) {
                // Zu spät: vorne überspringen, dann neu messen.
                m_pos += skip;
                continue;
            }
            const int silence = usToFrames(error);
            if (silence > 0) {
                // Zu früh: Stille bis zum Termin. Reicht der Block dafür nicht,
                // bleibt die Lage offen und der nächste Block misst neu.
                const int n = std::min(frames - written, silence);
                written += n;
                if (n < silence)
                    return;
            }
            m_synced = true;
            m_smoothedError = 0.0;
            measured = true;
        }

        const Chunk &c = m_queue.front();
        const int chunkFrames = c.pcm.size() / (2 * ch);
        const int n = std::min(frames - written, chunkFrames - m_pos);
        if (n > 0) {
            std::memcpy(out + written * ch, c.pcm.constData() + m_pos * 2 * ch, size_t(n * ch) * sizeof(qint16));
            written += n;
            m_pos += n;
        }
    }
}
