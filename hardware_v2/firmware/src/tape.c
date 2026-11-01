// WAV tapes for IN 00 and OUT 20 (see tape.h and the MAME driver's port00_r
// and port20_w, which this follows).
#include "tape.h"

#include <string.h>

#include "comp80.h"

#define RATE 44100

static int state = TAPE_STOPPED;
static tape_file file;
static uint64_t start;          // Z80 time the tape started
static int level = 1;           // the Schmitt trigger's output, or the level being recorded

// playback
static uint32_t rate, frame_bytes, data_left;
static int bits, channels;
static uint8_t buf[512];
static int buf_len, buf_pos;
static uint64_t frame;          // index of the next frame in buf

// recording
static uint64_t written;        // frames written
static uint32_t data_start;

static uint32_t le32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t le16(const uint8_t *p) { return p[0] | p[1] << 8; }

static uint64_t frames_at(uint64_t now, uint32_t r) {
    return now < start ? 0 : (now - start) * r / comp80_cfg.clock;
}

bool tape_play(const tape_file *f, uint64_t now) {
    uint8_t h[12], ch[8];
    tape_stop(now);
    file = *f;
    if (file.read(h, 12) != 12 || memcmp(h, "RIFF", 4) || memcmp(h + 8, "WAVE", 4)) goto bad;
    rate = 0;
    for (;;) {
        if (file.read(ch, 8) != 8) goto bad;
        uint32_t size = le32(ch + 4);
        if (!memcmp(ch, "fmt ", 4)) {
            uint8_t fmt[16];
            if (size < 16 || file.read(fmt, 16) != 16) goto bad;
            if (le16(fmt) != 1) goto bad;                    // PCM only
            channels = le16(fmt + 2);
            rate = le32(fmt + 4);
            bits = le16(fmt + 14);
            if ((bits != 8 && bits != 16) || channels < 1 || rate == 0) goto bad;
            frame_bytes = channels * bits / 8;
            for (uint32_t skip = size - 16 + (size & 1); skip; skip--) file.read(fmt, 1);
        } else if (!memcmp(ch, "data", 4)) {
            if (!rate) goto bad;
            data_left = size;
            break;
        } else {
            uint8_t junk[64];
            for (uint32_t skip = size + (size & 1); skip;) {
                int n = skip > sizeof junk ? sizeof junk : skip;
                if (file.read(junk, n) != n) goto bad;
                skip -= n;
            }
        }
    }
    buf_len = buf_pos = 0;
    frame = 0;
    level = 1;
    start = now;
    state = TAPE_PLAYING;
    return true;
bad:
    file.close();
    return false;
}

// The sample of frame n, -32768..32767, or false past the end.
static bool sample(uint64_t n, int *v) {
    while (frame + (buf_len - buf_pos) / frame_bytes <= n) {     // skip forward
        frame += (buf_len - buf_pos) / frame_bytes;
        uint32_t want = sizeof buf - sizeof buf % frame_bytes;
        if (want > data_left) want = data_left;
        int got = want ? file.read(buf, want) : 0;
        if (got < (int)frame_bytes) return false;
        data_left -= got;
        buf_len = got - got % frame_bytes;
        buf_pos = 0;
    }
    const uint8_t *p = buf + buf_pos + (uint32_t)(n - frame) * frame_bytes;
    *v = bits == 8 ? (p[0] - 128) << 8 : (int16_t)le16(p);
    return true;
}

int tape_in(uint64_t now) {
    if (state != TAPE_PLAYING) return 1;
    int v;
    if (!sample(frames_at(now, rate), &v)) {        // end of the tape
        tape_stop(now);
        return 1;
    }
    // Schmitt trigger: only change on a clear crossing, so silence (blank tape,
    // the end of a recording) holds the last level
    if (v > 8192) level = 1;
    else if (v < -8192) level = 0;
    return level;
}

static void write_header(uint32_t frames) {
    uint8_t h[44];
    uint32_t data = frames * 2;
    memcpy(h, "RIFF", 4);
    uint32_t v[] = {36 + data};
    memcpy(h + 4, v, 4);                             // the RP2350 and the Mac are both little-endian
    memcpy(h + 8, "WAVEfmt ", 8);
    uint32_t fmt_size = 16, r = RATE, bps = RATE * 2;
    uint16_t pcm = 1, ch = 1, align = 2, b = 16;
    memcpy(h + 16, &fmt_size, 4);
    memcpy(h + 20, &pcm, 2);
    memcpy(h + 22, &ch, 2);
    memcpy(h + 24, &r, 4);
    memcpy(h + 28, &bps, 4);
    memcpy(h + 32, &align, 2);
    memcpy(h + 34, &b, 2);
    memcpy(h + 36, "data", 4);
    memcpy(h + 40, &data, 4);
    file.write(h, sizeof h);
}

void tape_record(const tape_file *f, uint64_t now) {
    tape_stop(now);
    file = *f;
    write_header(0);
    data_start = 44;
    written = 0;
    level = 1;
    start = now;
    state = TAPE_RECORDING;
}

// Write the current level up to time now.
static void fill(uint64_t now) {
    uint64_t upto = frames_at(now, RATE);
    int16_t s = level ? 16384 : -16384;
    int16_t out[128];
    for (int i = 0; i < 128; i++) out[i] = s;
    while (written < upto) {
        uint64_t n = upto - written > 128 ? 128 : upto - written;
        file.write(out, (int)n * 2);
        written += n;
    }
}

void tape_out(uint64_t now, int lv) {
    if (state != TAPE_RECORDING) return;
    fill(now);
    level = lv;
}

void tape_poll(uint64_t now) {
    if (state == TAPE_RECORDING) fill(now);
}

void tape_stop(uint64_t now) {
    if (state == TAPE_RECORDING) {
        fill(now);
        file.seek(0);
        write_header((uint32_t)written);
    }
    if (state != TAPE_STOPPED) file.close();
    state = TAPE_STOPPED;
    level = 1;
}

int tape_state(void) { return state; }

uint32_t tape_seconds(uint64_t now) {
    return state == TAPE_STOPPED ? 0 : (uint32_t)((now - start) / comp80_cfg.clock);
}
