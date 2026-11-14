#!/usr/bin/env python3
"""
STAR FALL — Background Music & Transition Audio Generator
Generates 16-bit 44.1kHz stereo/mono WAV music tracks and transition SFX for Phase 1.
Zero third-party dependencies: uses standard library (wave, struct, math, random).
"""

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44100
TWO_PI = 2.0 * math.pi

MUSIC_DIR = os.path.join("assets", "audio", "music")
SFX_DIR = os.path.join("assets", "audio", "sfx")
os.makedirs(MUSIC_DIR, exist_ok=True)
os.makedirs(SFX_DIR, exist_ok=True)


def clamp(val, low=-1.0, high=1.0):
    return max(low, min(high, val))


def write_wav(filepath, left_samples, right_samples=None, sample_rate=SAMPLE_RATE):
    """Writes 16-bit PCM WAV (mono or stereo)."""
    is_stereo = right_samples is not None
    num_channels = 2 if is_stereo else 1
    total_frames = len(left_samples)

    with wave.open(filepath, "wb") as wav_file:
        wav_file.setnchannels(num_channels)
        wav_file.setsampwidth(2)  # 16-bit
        wav_file.setframerate(sample_rate)
        wav_file.setnframes(total_frames)

        packed = bytearray()
        for i in range(total_frames):
            l = int(clamp(left_samples[i]) * 32767.0)
            if is_stereo:
                r = int(clamp(right_samples[i]) * 32767.0)
                packed.extend(struct.pack("<hh", l, r))
            else:
                packed.extend(struct.pack("<h", l))
        wav_file.writeframes(packed)
    print(f"Generated: {filepath} ({total_frames / sample_rate:.2f}s, {'stereo' if is_stereo else 'mono'})")


# ---------------------------------------------------------------- Synth primitives

def note_freq(semitone_offset, root_freq=440.0):
    """Convert semitone offset from A4 (440Hz) to frequency."""
    return root_freq * (2.0 ** (semitone_offset / 12.0))


def synth_osc(phase, wave_type="sine"):
    norm_phase = phase % 1.0
    if wave_type == "sine":
        return math.sin(norm_phase * TWO_PI)
    elif wave_type == "tri":
        return 1.0 - 4.0 * abs(norm_phase - 0.5)
    elif wave_type == "saw":
        return norm_phase * 2.0 - 1.0
    elif wave_type == "square":
        return 1.0 if norm_phase < 0.5 else -1.0
    elif wave_type == "warm":
        # Rich detuned dual sine with 2nd harmonic
        s1 = math.sin(norm_phase * TWO_PI)
        s2 = math.sin(norm_phase * TWO_PI * 2.0) * 0.35
        return s1 + s2
    return math.sin(norm_phase * TWO_PI)


# ---------------------------------------------------------------- 1. TITLE THEME
# Atmospheric, mysterious, slow space arpeggio in D minor (D3, F3, A3, C4, D4, E4)
def generate_music_title():
    duration = 16.0
    num_samples = int(duration * SAMPLE_RATE)
    left = [0.0] * num_samples
    right = [0.0] * num_samples

    # Chord progression: Dm -> Bb -> F -> C (4 seconds each)
    chords = [
        # Dm: D3, F3, A3, C4
        [146.83, 174.61, 220.0, 261.63],
        # Bb: Bb2, D3, F3, A3
        [116.54, 146.83, 174.61, 220.0],
        # F: F2, C3, F3, A3
        [87.31, 130.81, 174.61, 220.0],
        # C: C3, G3, C4, E4
        [130.81, 196.0, 261.63, 329.63]
    ]

    arpeggio_pattern = [0, 1, 2, 3, 2, 1, 0, 2]  # 8 notes per 4s chord (0.5s per note)
    note_dur = 0.5

    for c_idx, chord in enumerate(chords):
        chord_start = c_idx * 4.0
        # Pad chord
        for note in chord:
            for i in range(int(4.0 * SAMPLE_RATE)):
                idx = int((chord_start * SAMPLE_RATE) + i)
                if idx >= num_samples:
                    break
                t_chord = i / SAMPLE_RATE
                env = math.sin(t_chord / 4.0 * math.pi) ** 1.5
                sig_l = synth_osc(t_chord * note, "warm") * 0.08 * env
                sig_r = synth_osc(t_chord * (note * 1.003) + 0.1, "warm") * 0.08 * env
                left[idx] += sig_l
                right[idx] += sig_r

        # Arpeggiator line
        for a_step, p_idx in enumerate(arpeggio_pattern):
            note_freq_val = chord[p_idx] * 2.0  # One octave up
            step_start = chord_start + (a_step * note_dur)
            step_samples = int(note_dur * 1.6 * SAMPLE_RATE)  # slight overlap/reverb tail

            pan = 0.3 + 0.4 * (a_step % 2)  # subtle stereo ping-pong
            for s in range(step_samples):
                idx = int((step_start * SAMPLE_RATE) + s)
                if idx >= num_samples:
                    break
                t_note = s / SAMPLE_RATE
                env = math.exp(-t_note * 3.5)
                osc = (synth_osc(t_note * note_freq_val, "sine") * 0.6 +
                       synth_osc(t_note * note_freq_val * 2.0, "tri") * 0.25)
                val = osc * env * 0.14
                left[idx] += val * (1.0 - pan)
                right[idx] += val * pan

    # Low space rumble sub-bass
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        sub = math.sin(t * 43.65 * TWO_PI) * 0.06  # Low F1
        left[i] += sub
        right[i] += sub

    # Seamless boundary envelope
    for i in range(int(0.2 * SAMPLE_RATE)):
        fade = i / (0.2 * SAMPLE_RATE)
        left[i] *= fade
        right[i] *= fade
        left[num_samples - 1 - i] *= fade
        right[num_samples - 1 - i] *= fade

    filepath = os.path.join(MUSIC_DIR, "music_title.wav")
    write_wav(filepath, left, right)


# ---------------------------------------------------------------- 2. EARTH / SPACEPORT THEME
# Warm, optimistic, peaceful retro sci-fi synth with bright major arpeggios
def generate_music_earth():
    duration = 16.0
    num_samples = int(duration * SAMPLE_RATE)
    left = [0.0] * num_samples
    right = [0.0] * num_samples

    # Progressions in C Major: C -> G/B -> Am -> F (4s each)
    chords = [
        # C: C3 (130.81), E3 (164.81), G3 (196.00), B3 (246.94)
        [130.81, 164.81, 196.00, 246.94],
        # G: B2 (123.47), D3 (146.83), G3 (196.00), D4 (293.66)
        [123.47, 146.83, 196.00, 293.66],
        # Am: A2 (110.00), C3 (130.81), E3 (164.81), A3 (220.00)
        [110.00, 130.81, 164.81, 220.00],
        # F: F2 (87.31), C3 (130.81), F3 (174.61), A3 (220.00)
        [87.31, 130.81, 174.61, 220.00]
    ]

    melody_pattern = [
        # Measure 1 (C)
        [(0.0, 523.25), (0.75, 659.25), (1.5, 783.99), (2.5, 659.25), (3.25, 587.33)],
        # Measure 2 (G)
        [(0.0, 587.33), (0.75, 493.88), (1.5, 587.33), (2.5, 783.99), (3.25, 659.25)],
        # Measure 3 (Am)
        [(0.0, 440.00), (0.75, 523.25), (1.5, 659.25), (2.5, 523.25), (3.25, 440.00)],
        # Measure 4 (F)
        [(0.0, 349.23), (0.75, 440.00), (1.5, 523.25), (2.5, 587.33), (3.25, 659.25)],
    ]

    for m_idx, chord in enumerate(chords):
        m_start = m_idx * 4.0
        # Gentle acoustic synth pads
        for note in chord:
            for i in range(int(4.0 * SAMPLE_RATE)):
                idx = int(m_start * SAMPLE_RATE + i)
                if idx >= num_samples:
                    break
                t = i / SAMPLE_RATE
                env = math.sin(t / 4.0 * math.pi) ** 1.3
                sig_l = (synth_osc(t * note, "warm") * 0.05 + synth_osc(t * note * 0.5, "sine") * 0.04) * env
                sig_r = (synth_osc(t * note * 1.002, "warm") * 0.05 + synth_osc(t * note * 0.5, "sine") * 0.04) * env
                left[idx] += sig_l
                right[idx] += sig_r

        # Bright bell-like melody
        for note_time, freq in melody_pattern[m_idx]:
            n_start = m_start + note_time
            n_samples = int(1.4 * SAMPLE_RATE)
            for s in range(n_samples):
                idx = int(n_start * SAMPLE_RATE + s)
                if idx >= num_samples:
                    break
                t_note = s / SAMPLE_RATE
                env = math.exp(-t_note * 2.8)
                bell = (synth_osc(t_note * freq, "sine") * 0.7 +
                        synth_osc(t_note * freq * 2.0, "sine") * 0.2 +
                        synth_osc(t_note * freq * 3.0, "tri") * 0.1) * env * 0.12
                left[idx] += bell * 0.45
                right[idx] += bell * 0.55

    # Gentle boundary fade
    for i in range(int(0.2 * SAMPLE_RATE)):
        fade = i / (0.2 * SAMPLE_RATE)
        left[i] *= fade
        right[i] *= fade
        left[num_samples - 1 - i] *= fade
        right[num_samples - 1 - i] *= fade

    filepath = os.path.join(MUSIC_DIR, "music_earth.wav")
    write_wav(filepath, left, right)


# ---------------------------------------------------------------- 3. CONSTRUCTION HANGAR THEME
# Technological, focused, analytical pulse with clean synth bass and sequencer clicks
def generate_music_construction():
    duration = 16.0
    num_samples = int(duration * SAMPLE_RATE)
    left = [0.0] * num_samples
    right = [0.0] * num_samples

    # 16th note sequencing loop at 120 BPM (0.125s per 16th note)
    step_time = 0.125
    total_steps = int(duration / step_time)

    # Bassline notes (F2, G#2, C3, D#3)
    bass_notes = [87.31, 87.31, 103.83, 103.83, 130.81, 130.81, 155.56, 130.81] * 16

    for step in range(total_steps):
        s_time = step * step_time
        # Bass pluck
        freq = bass_notes[step % len(bass_notes)]
        step_len = int(step_time * 1.2 * SAMPLE_RATE)
        for i in range(step_len):
            idx = int(s_time * SAMPLE_RATE + i)
            if idx >= num_samples:
                break
            t = i / SAMPLE_RATE
            env = math.exp(-t * 18.0)
            sig = (synth_osc(t * freq, "saw") * 0.5 + synth_osc(t * freq * 0.5, "tri") * 0.5) * env * 0.16
            left[idx] += sig * 0.5
            right[idx] += sig * 0.5

        # Hi-tech tick / clock click on every 8th note
        if step % 2 == 0:
            click_len = int(0.02 * SAMPLE_RATE)
            for i in range(click_len):
                idx = int(s_time * SAMPLE_RATE + i)
                if idx >= num_samples:
                    break
                t = i / SAMPLE_RATE
                click = (random.random() * 2.0 - 1.0) * math.exp(-t * 220.0) * 0.035
                left[idx] += click * 0.7
                right[idx] += click * 0.3

    # Warm pad chords floating above (Cm9 -> Abmaj7 -> Fm9 -> Gsus4)
    pads = [
        (0.0, [130.81, 155.56, 196.00, 233.08]),
        (4.0, [103.83, 155.56, 196.00, 261.63]),
        (8.0, [87.31, 130.81, 174.61, 233.08]),
        (12.0, [98.00, 146.83, 196.00, 261.63])
    ]

    for p_start, chord in pads:
        p_samples = int(4.0 * SAMPLE_RATE)
        for note in chord:
            for i in range(p_samples):
                idx = int(p_start * SAMPLE_RATE + i)
                if idx >= num_samples:
                    break
                t = i / SAMPLE_RATE
                env = math.sin(t / 4.0 * math.pi) ** 1.5
                sig_l = synth_osc(t * note, "warm") * env * 0.045
                sig_r = synth_osc(t * note * 1.003, "warm") * env * 0.045
                left[idx] += sig_l
                right[idx] += sig_r

    # Fade edges
    for i in range(int(0.2 * SAMPLE_RATE)):
        fade = i / (0.2 * SAMPLE_RATE)
        left[i] *= fade
        right[i] *= fade
        left[num_samples - 1 - i] *= fade
        right[num_samples - 1 - i] *= fade

    filepath = os.path.join(MUSIC_DIR, "music_construction.wav")
    write_wav(filepath, left, right)


# ---------------------------------------------------------------- 4. FLIGHT / ASCENT THEME
# Soaring, tense, cosmic synth arpeggios that build energy toward the signal investigation
def generate_music_flight():
    duration = 16.0
    num_samples = int(duration * SAMPLE_RATE)
    left = [0.0] * num_samples
    right = [0.0] * num_samples

    # Fast 8th note driving arpeggio (140 BPM)
    arp_notes = [220.0, 261.63, 329.63, 440.0, 523.25, 440.0, 329.63, 261.63]
    step_time = 60.0 / 140.0 / 2.0  # ~0.214s

    for i in range(num_samples):
        t = i / SAMPLE_RATE
        # Progressive crescendo
        build = 0.5 + 0.5 * (t / duration)

        # Low thruster pulse
        sub = math.sin(t * 55.0 * TWO_PI) * 0.08 * build

        # Arpeggio
        step = int(t / step_time)
        note_freq = arp_notes[step % len(arp_notes)]
        step_phase = (t % step_time) / step_time
        env = math.exp(-step_phase * 4.0)

        lead = (synth_osc(t * note_freq, "saw") * 0.4 +
                synth_osc(t * note_freq * 2.0, "tri") * 0.3) * env * 0.10 * build

        left[i] += sub + lead * 0.6
        right[i] += sub + lead * 0.4

    filepath = os.path.join(MUSIC_DIR, "music_flight.wav")
    write_wav(filepath, left, right)


# ---------------------------------------------------------------- 5. CRASH SITE / RUIN THEME
# Desolate, dark, sorrowful post-apocalyptic drone with slow mournful melodic lines
def generate_music_ruin():
    duration = 18.0
    num_samples = int(duration * SAMPLE_RATE)
    left = [0.0] * num_samples
    right = [0.0] * num_samples

    # Deep sub drone (D1 ~ 36.71 Hz, A1 ~ 55.0 Hz)
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        drone1 = math.sin(t * 36.71 * TWO_PI) * 0.09
        drone2 = math.sin(t * 55.0 * TWO_PI + 0.5) * 0.06
        # Slow modulation filter
        mod = 0.6 + 0.4 * math.sin(t * 0.3)
        left[i] += (drone1 + drone2) * mod
        right[i] += (drone1 + drone2) * mod

    # Haunting, distant high chime melody (D5, C5, Bb4, A4, F4)
    sorrow_notes = [
        (1.0, 587.33, 2.5),  # D5
        (4.5, 523.25, 2.5),  # C5
        (8.0, 466.16, 3.0),  # Bb4
        (12.0, 440.00, 2.0), # A4
        (14.5, 349.23, 3.0), # F4
    ]

    for start_t, freq, dur in sorrow_notes:
        n_samples = int(dur * SAMPLE_RATE)
        for s in range(n_samples):
            idx = int(start_t * SAMPLE_RATE + s)
            if idx >= num_samples:
                break
            t_note = s / SAMPLE_RATE
            env = math.sin(t_note / dur * math.pi) ** 1.8
            chime = (synth_osc(t_note * freq, "sine") * 0.7 +
                     synth_osc(t_note * (freq * 1.004), "sine") * 0.3) * env * 0.09
            # Wide stereo pan with delay
            left[idx] += chime * 0.65
            right[idx] += chime * 0.35

    # Boundary fade
    for i in range(int(0.3 * SAMPLE_RATE)):
        fade = i / (0.3 * SAMPLE_RATE)
        left[i] *= fade
        right[i] *= fade
        left[num_samples - 1 - i] *= fade
        right[num_samples - 1 - i] *= fade

    filepath = os.path.join(MUSIC_DIR, "music_ruin.wav")
    write_wav(filepath, left, right)


# ---------------------------------------------------------------- 6. HOLOGRAPHIC MEMORY THEME
# Ethereal, gentle music box / Rhodes chords conveying lost beauty (The Green City)
def generate_music_memory():
    duration = 14.0
    num_samples = int(duration * SAMPLE_RATE)
    left = [0.0] * num_samples
    right = [0.0] * num_samples

    # Nostalgic progression: Gmaj7 -> Em9 -> Cmaj7 -> Dsus4
    chords = [
        (0.0, [196.00, 246.94, 293.66, 369.99]),   # Gmaj7
        (3.5, [164.81, 196.00, 246.94, 329.63]),   # Em9
        (7.0, [130.81, 164.81, 196.00, 246.94]),   # Cmaj7
        (10.5, [146.83, 196.00, 220.00, 293.66]),  # Dsus4
    ]

    for start_t, chord in chords:
        c_samples = int(3.5 * 1.4 * SAMPLE_RATE)
        for note in chord:
            for s in range(c_samples):
                idx = int(start_t * SAMPLE_RATE + s)
                if idx >= num_samples:
                    break
                t_n = s / SAMPLE_RATE
                env = math.exp(-t_n * 1.5)
                # Shimmering high harmonics
                sig = (synth_osc(t_n * note, "sine") * 0.6 +
                       synth_osc(t_n * note * 2.0, "tri") * 0.25 +
                       synth_osc(t_n * note * 4.0, "sine") * 0.15) * env * 0.10
                left[idx] += sig * 0.45
                right[idx] += sig * 0.55

    filepath = os.path.join(MUSIC_DIR, "music_memory.wav")
    write_wav(filepath, left, right)


# ---------------------------------------------------------------- 7. CHECKPOINT THEME
# Triumphant resolution fanfare celebrating Phase 1 survival & progress
def generate_music_checkpoint():
    duration = 6.0
    num_samples = int(duration * SAMPLE_RATE)
    left = [0.0] * num_samples
    right = [0.0] * num_samples

    # Fanfare notes: C4 -> E4 -> G4 -> C5 (sustained triumphal major chord)
    notes = [
        (0.0, 261.63, 0.4),
        (0.4, 329.63, 0.4),
        (0.8, 392.00, 0.5),
        (1.3, 523.25, 4.0),
        (1.3, 392.00, 4.0),
        (1.3, 329.63, 4.0),
    ]

    for start_t, freq, dur in notes:
        n_samples = int(dur * SAMPLE_RATE)
        for s in range(n_samples):
            idx = int(start_t * SAMPLE_RATE + s)
            if idx >= num_samples:
                break
            t_n = s / SAMPLE_RATE
            env = math.exp(-t_n * 0.8) if dur > 1.0 else math.sin(t_n / dur * math.pi)
            sig = (synth_osc(t_n * freq, "warm") * 0.7 +
                   synth_osc(t_n * freq * 2.0, "tri") * 0.3) * env * 0.16
            left[idx] += sig * 0.5
            right[idx] += sig * 0.5

    filepath = os.path.join(MUSIC_DIR, "music_checkpoint.wav")
    write_wav(filepath, left, right)


# ---------------------------------------------------------------- 8. SCENE TRANSITION SFX
# Smooth low-frequency atmospheric shutter/whoosh for visual scene transitions
def generate_sfx_transition():
    duration = 0.5
    num_samples = int(duration * SAMPLE_RATE)
    left = [0.0] * num_samples
    right = [0.0] * num_samples

    for i in range(num_samples):
        t = i / SAMPLE_RATE
        prog = t / duration
        # Pitch descends then rises (swish)
        freq = 340.0 - 180.0 * math.sin(prog * math.pi)
        env = math.sin(prog * math.pi) ** 1.4
        noise = (random.random() * 2.0 - 1.0) * 0.3
        osc = synth_osc(t * freq, "saw") * 0.7 + noise
        val = osc * env * 0.16
        pan = prog  # pan left to right
        left[i] = val * (1.0 - pan)
        right[i] = val * pan

    filepath = os.path.join(SFX_DIR, "sfx_transition.wav")
    write_wav(filepath, left, right)


def main():
    print("=== Generating Background Music & Transition Assets for Phase 1 ===")
    generate_music_title()
    generate_music_earth()
    generate_music_construction()
    generate_music_flight()
    generate_music_ruin()
    generate_music_memory()
    generate_music_checkpoint()
    generate_sfx_transition()
    print("All music tracks and transition audio successfully generated!")


if __name__ == "__main__":
    main()
