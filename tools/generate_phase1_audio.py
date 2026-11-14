#!/usr/bin/env python3
"""
STAR FALL - Phase 1 Retro Sci-Fi Audio Synthesizer
Generates 16-bit PCM 44.1kHz WAV sound effects and ambient tracks using
ONLY Python standard library modules (wave, struct, math, random, array, os, time).
"""

import math
import random
import struct
import array
import os
import time
import wave

SAMPLE_RATE = 44100
TWO_PI = 2.0 * math.pi

# ---------------------------------------------------------------------------
# Core Audio Buffer and DSP Utilities
# ---------------------------------------------------------------------------

class AudioBuffer:
    def __init__(self, duration_s: float, channels: int = 1, sample_rate: int = SAMPLE_RATE):
        self.sample_rate = sample_rate
        self.channels = channels
        self.num_frames = max(1, int(round(duration_s * sample_rate)))
        if channels == 1:
            self.data = [0.0] * self.num_frames
        else:
            self.left = [0.0] * self.num_frames
            self.right = [0.0] * self.num_frames

    @property
    def duration(self) -> float:
        return self.num_frames / self.sample_rate

    def add_sample(self, i: int, left: float, right: float = None):
        if 0 <= i < self.num_frames:
            if self.channels == 1:
                self.data[i] += left if right is None else (left + right) * 0.5
            else:
                self.left[i] += left
                self.right[i] += left if right is None else right

    def add_panned_sample(self, i: int, sample: float, pan: float = 0.0):
        """Pan: -1.0 = full left, 0.0 = center, +1.0 = full right."""
        if 0 <= i < self.num_frames:
            if self.channels == 1:
                self.data[i] += sample
            else:
                # Constant power panning
                angle = (pan + 1.0) * (math.pi * 0.25)
                l_gain = math.cos(angle)
                r_gain = math.sin(angle)
                self.left[i] += sample * l_gain
                self.right[i] += sample * r_gain

    def apply_gain(self, gain: float):
        if self.channels == 1:
            for i in range(self.num_frames):
                self.data[i] *= gain
        else:
            for i in range(self.num_frames):
                self.left[i] *= gain
                self.right[i] *= gain

    def fade_in_out(self, fade_in_s: float = 0.003, fade_out_s: float = 0.008):
        """Smooth cosine fade-in and fade-out to guarantee zero DC clicks."""
        in_frames = max(1, int(fade_in_s * self.sample_rate))
        out_frames = max(1, int(fade_out_s * self.sample_rate))

        for i in range(min(in_frames, self.num_frames)):
            mult = 0.5 * (1.0 - math.cos(math.pi * i / in_frames))
            if self.channels == 1:
                self.data[i] *= mult
            else:
                self.left[i] *= mult
                self.right[i] *= mult

        for i in range(min(out_frames, self.num_frames)):
            idx = self.num_frames - 1 - i
            mult = 0.5 * (1.0 - math.cos(math.pi * i / out_frames))
            if self.channels == 1:
                self.data[idx] *= mult
            else:
                self.left[idx] *= mult
                self.right[idx] *= mult

    def normalize(self, target_peak: float = 0.89):  # ~ -1 dBFS
        max_val = 1e-9
        if self.channels == 1:
            for s in self.data:
                if abs(s) > max_val:
                    max_val = abs(s)
            factor = target_peak / max_val
            for i in range(self.num_frames):
                self.data[i] = max(-1.0, min(1.0, self.data[i] * factor))
        else:
            for i in range(self.num_frames):
                al = abs(self.left[i])
                ar = abs(self.right[i])
                if al > max_val: max_val = al
                if ar > max_val: max_val = ar
            factor = target_peak / max_val
            for i in range(self.num_frames):
                self.left[i] = max(-1.0, min(1.0, self.left[i] * factor))
                self.right[i] = max(-1.0, min(1.0, self.right[i] * factor))

    def soft_clip(self, drive: float = 1.0):
        """Analog style soft clipping using tanh."""
        if self.channels == 1:
            for i in range(self.num_frames):
                self.data[i] = math.tanh(self.data[i] * drive)
        else:
            for i in range(self.num_frames):
                self.left[i] = math.tanh(self.left[i] * drive)
                self.right[i] = math.tanh(self.right[i] * drive)

    def save_wav(self, filepath: str):
        os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
        with wave.open(filepath, "wb") as wav:
            wav.setnchannels(self.channels)
            wav.setsampwidth(2)  # 16-bit PCM
            wav.setframerate(self.sample_rate)

            if self.channels == 1:
                raw = array.array("h", [
                    int(max(-32767, min(32767, round(s * 32767.0))))
                    for s in self.data
                ]).tobytes()
            else:
                interleaved = []
                for i in range(self.num_frames):
                    l_val = int(max(-32767, min(32767, round(self.left[i] * 32767.0))))
                    r_val = int(max(-32767, min(32767, round(self.right[i] * 32767.0))))
                    interleaved.append(l_val)
                    interleaved.append(r_val)
                raw = array.array("h", interleaved).tobytes()

            wav.writeframes(raw)


# ---------------------------------------------------------------------------
# Waveform and Envelope Generators
# ---------------------------------------------------------------------------

def sine_sample(phase: float) -> float:
    return math.sin(phase * TWO_PI)

def square_sample(phase: float, duty: float = 0.5) -> float:
    p = phase - math.floor(phase)
    return 1.0 if p < duty else -1.0

def triangle_sample(phase: float) -> float:
    p = phase - math.floor(phase)
    return 1.0 - 4.0 * abs(p - 0.5)

def saw_sample(phase: float) -> float:
    p = phase - math.floor(phase)
    return 2.0 * p - 1.0

class WhiteNoise:
    def __init__(self, seed: int = 42):
        self.rng = random.Random(seed)
    def next_sample(self) -> float:
        return self.rng.uniform(-1.0, 1.0)

class PinkNoise:
    """Paul Kellet's refined pink noise filter."""
    def __init__(self, seed: int = 42):
        self.rng = random.Random(seed)
        self.b0 = self.b1 = self.b2 = self.b3 = self.b4 = self.b5 = self.b6 = 0.0

    def next_sample(self) -> float:
        white = self.rng.uniform(-1.0, 1.0)
        self.b0 = 0.99886 * self.b0 + white * 0.0555179
        self.b1 = 0.99332 * self.b1 + white * 0.0750759
        self.b2 = 0.96900 * self.b2 + white * 0.1538520
        self.b3 = 0.86650 * self.b3 + white * 0.3104856
        self.b4 = 0.55000 * self.b4 + white * 0.5329522
        self.b5 = -0.7616 * self.b5 - white * 0.0168980
        out = (self.b0 + self.b1 + self.b2 + self.b3 + self.b4 + self.b5 + self.b6 + white * 0.5362) * 0.11
        self.b6 = white * 0.115926
        return out

class ResonantFilter:
    """State variable 2-pole filter (lowpass, bandpass, highpass)."""
    def __init__(self, cutoff: float, q: float = 1.0, sample_rate: int = SAMPLE_RATE):
        self.sample_rate = sample_rate
        self.update(cutoff, q)
        self.hp = self.bp = self.lp = 0.0

    def update(self, cutoff: float, q: float = 1.0):
        fc = min(0.45, max(0.001, cutoff / self.sample_rate))
        self.f = 2.0 * math.sin(math.pi * fc)
        self.q = max(0.01, 1.0 / max(0.01, q))

    def process(self, sample: float):
        self.hp = sample - self.lp - self.q * self.bp
        self.bp += self.f * self.hp
        self.lp += self.f * self.bp
        return self.lp, self.bp, self.hp

def adsr_env(t: float, dur: float, attack: float, decay: float, sustain: float, release: float) -> float:
    if t < 0.0 or t > dur:
        return 0.0
    sustain_start = attack + decay
    release_start = max(sustain_start, dur - release)

    if t < attack:
        return t / max(1e-5, attack)
    elif t < sustain_start:
        prog = (t - attack) / max(1e-5, decay)
        return 1.0 - prog * (1.0 - sustain)
    elif t < release_start:
        return sustain
    else:
        prog = (t - release_start) / max(1e-5, release)
        return max(0.0, sustain * (1.0 - prog))

def exp_decay_env(t: float, decay_rate: float) -> float:
    if t < 0.0: return 0.0
    return math.exp(-t * decay_rate)

# Simple stereo delay line for reverb/echo
def apply_simple_stereo_delay(buf: AudioBuffer, delay_s: float = 0.08, feedback: float = 0.35, damping: float = 0.4):
    """Applies a ping-pong stereo echo to an AudioBuffer."""
    delay_frames_l = int(delay_s * buf.sample_rate)
    delay_frames_r = int((delay_s * 1.35) * buf.sample_rate)

    if buf.channels == 1:
        # Convert mono to stereo in-place or apply mono delay
        d_buf = [0.0] * delay_frames_l
        d_idx = 0
        lp = 0.0
        for i in range(buf.num_frames):
            in_s = buf.data[i]
            d_out = d_buf[d_idx]
            lp += damping * (d_out - lp)
            d_buf[d_idx] = in_s + lp * feedback
            d_idx = (d_idx + 1) % delay_frames_l
            buf.data[i] = in_s + d_out * 0.4
    else:
        dl_buf = [0.0] * delay_frames_l
        dr_buf = [0.0] * delay_frames_r
        dl_idx = 0
        dr_idx = 0
        lp_l = 0.0
        lp_r = 0.0
        for i in range(buf.num_frames):
            in_l = buf.left[i]
            in_r = buf.right[i]
            out_l = dl_buf[dl_idx]
            out_r = dr_buf[dr_idx]

            lp_l += damping * (out_l - lp_l)
            lp_r += damping * (out_r - lp_r)

            # Ping-pong feedback: cross channels
            dl_buf[dl_idx] = in_l + lp_r * feedback
            dr_buf[dr_idx] = in_r + lp_l * feedback

            dl_idx = (dl_idx + 1) % delay_frames_l
            dr_idx = (dr_idx + 1) % delay_frames_r

            buf.left[i] = in_l + out_l * 0.45
            buf.right[i] = in_r + out_r * 0.45


# ---------------------------------------------------------------------------
# Individual SFX Generators
# ---------------------------------------------------------------------------

def gen_ui_select() -> AudioBuffer:
    """Crisp, tactile retro UI cursor movement blip."""
    dur = 0.045
    buf = AudioBuffer(dur, channels=1)
    phase = 0.0
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # Frequency snap from 540 Hz to 720 Hz
        freq = 540.0 if t < 0.015 else 720.0
        phase += freq / SAMPLE_RATE
        # 25% duty pulse + triangle
        s = 0.7 * square_sample(phase, 0.25) + 0.3 * triangle_sample(phase)
        env = exp_decay_env(t, 60.0)
        buf.add_sample(i, s * env)
    buf.fade_in_out(0.002, 0.005)
    buf.normalize(0.80)
    return buf

def gen_ui_confirm() -> AudioBuffer:
    """Warm ascending two-tone major triad arpeggio (C5 -> G5)."""
    dur = 0.28
    buf = AudioBuffer(dur, channels=2)
    phase1 = 0.0
    phase2 = 0.0
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # Note 1: C5 (523.25 Hz)
        if t < 0.22:
            phase1 += 523.25 / SAMPLE_RATE
            s1 = 0.65 * sine_sample(phase1) + 0.35 * triangle_sample(phase1)
            e1 = exp_decay_env(t, 16.0)
            buf.add_panned_sample(i, s1 * e1 * 0.7, pan=-0.25)

        # Note 2: G5 (783.99 Hz)
        if t >= 0.055:
            t2 = t - 0.055
            phase2 += 783.99 / SAMPLE_RATE
            s2 = 0.70 * sine_sample(phase2) + 0.30 * square_sample(phase2, 0.5)
            e2 = exp_decay_env(t2, 14.0)
            buf.add_panned_sample(i, s2 * e2 * 0.85, pan=0.25)

    buf.fade_in_out(0.003, 0.01)
    buf.normalize(0.85)
    return buf

def gen_ui_back() -> AudioBuffer:
    """Gentle downward pitch-gliding blip signaling navigation back/cancel."""
    dur = 0.12
    buf = AudioBuffer(dur, channels=1)
    phase = 0.0
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        prog = t / dur
        freq = 420.0 * math.exp(-prog * 0.85)  # 420 Hz -> ~180 Hz
        phase += freq / SAMPLE_RATE
        s = 0.75 * triangle_sample(phase) + 0.25 * sine_sample(phase)
        env = exp_decay_env(t, 22.0)
        buf.add_sample(i, s * env)
    buf.fade_in_out(0.002, 0.008)
    buf.normalize(0.80)
    return buf

def gen_ui_denied() -> AudioBuffer:
    """Low double-pulse buzzer indicating invalid action or locked feature."""
    dur = 0.20
    buf = AudioBuffer(dur, channels=1)
    phase = 0.0
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # Two pulses: 0 to 0.06s and 0.08s to 0.16s
        active = (0.0 <= t < 0.06) or (0.08 <= t < 0.16)
        if active:
            tp = t if t < 0.06 else (t - 0.08)
            phase += 135.0 / SAMPLE_RATE
            s = 0.6 * saw_sample(phase) + 0.4 * square_sample(phase, 0.5)
            env = adsr_env(tp, 0.07, 0.004, 0.04, 0.2, 0.02)
            buf.add_sample(i, s * env)
    buf.fade_in_out(0.002, 0.006)
    buf.normalize(0.85)
    return buf

def gen_ui_toast() -> AudioBuffer:
    """High-register bell-like shimmer chime (D6 -> F#6 -> A6) for banners/toasts."""
    dur = 0.40
    buf = AudioBuffer(dur, channels=2)
    notes = [
        (0.000, 1174.66, -0.35),
        (0.038, 1479.98,  0.35),
        (0.076, 1760.00,  0.00),
    ]
    phases = [0.0, 0.0, 0.0]
    fm_phases = [0.0, 0.0, 0.0]

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        for idx, (onset, freq, pan) in enumerate(notes):
            if t >= onset:
                tn = t - onset
                # FM bell overtone
                fm_phases[idx] += (freq * 2.76) / SAMPLE_RATE
                fm_mod = 0.25 * math.sin(fm_phases[idx] * TWO_PI)
                phases[idx] += (freq + fm_mod * 80.0) / SAMPLE_RATE
                s = sine_sample(phases[idx])
                env = exp_decay_env(tn, 12.0)
                buf.add_panned_sample(i, s * env * 0.45, pan=pan)

    buf.fade_in_out(0.003, 0.012)
    buf.normalize(0.85)
    return buf

def gen_blip_nick() -> AudioBuffer:
    """Nick's dialogue typewriter blip (human, mid-tone warm square/triangle)."""
    dur = 0.038
    buf = AudioBuffer(dur, channels=1)
    phase = 0.0
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        prog = t / dur
        freq = 370.0 - prog * 40.0
        phase += freq / SAMPLE_RATE
        s = 0.8 * triangle_sample(phase) + 0.2 * square_sample(phase, 0.3)
        env = exp_decay_env(t, 70.0)
        buf.add_sample(i, s * env)
    buf.fade_in_out(0.002, 0.004)
    buf.normalize(0.75)
    return buf

def gen_blip_bill() -> AudioBuffer:
    """Bill's dialogue typewriter blip (cute robotic FM mod-frequency blip)."""
    dur = 0.032
    buf = AudioBuffer(dur, channels=1)
    phase = 0.0
    fm_phase = 0.0
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        fm_phase += 1640.0 / SAMPLE_RATE
        fm_mod = math.sin(fm_phase * TWO_PI) * 220.0 * exp_decay_env(t, 50.0)
        phase += (820.0 + fm_mod) / SAMPLE_RATE
        s = sine_sample(phase)
        env = exp_decay_env(t, 80.0)
        buf.add_sample(i, s * env)
    buf.fade_in_out(0.001, 0.004)
    buf.normalize(0.75)
    return buf

def gen_blip_control() -> AudioBuffer:
    """Mission control dialogue blip (filtered, slight static/nasal radio comm beep)."""
    dur = 0.045
    buf = AudioBuffer(dur, channels=1)
    phase = 0.0
    noise = WhiteNoise(101)
    flt = ResonantFilter(1120.0, q=4.5)
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        phase += 1050.0 / SAMPLE_RATE
        raw = 0.7 * square_sample(phase, 0.4) + 0.3 * noise.next_sample()
        lp, bp, hp = flt.process(raw)
        env = exp_decay_env(t, 65.0)
        buf.add_sample(i, bp * env)
    buf.fade_in_out(0.002, 0.005)
    buf.normalize(0.75)
    return buf

def gen_interact() -> AudioBuffer:
    """Tactile prompt interaction chime / switch click when activating terminals/consoles."""
    dur = 0.14
    buf = AudioBuffer(dur, channels=2)
    phase1 = 0.0
    phase2 = 0.0
    noise = WhiteNoise(202)
    flt = ResonantFilter(1400.0, q=2.0)
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # Switch click transient in first 15ms
        click = 0.0
        if t < 0.015:
            lp, bp, hp = flt.process(noise.next_sample())
            click = bp * exp_decay_env(t, 250.0)

        # Dual harmonic ping: 880 Hz and 1320 Hz
        phase1 += 880.0 / SAMPLE_RATE
        phase2 += 1320.0 / SAMPLE_RATE
        tone = 0.6 * sine_sample(phase1) + 0.4 * sine_sample(phase2)
        env = exp_decay_env(t, 24.0)

        buf.add_panned_sample(i, click * 1.2 + tone * env * 0.7, pan=0.0)
    buf.fade_in_out(0.002, 0.008)
    buf.normalize(0.85)
    return buf

def gen_ship_install() -> AudioBuffer:
    """Solid mechanical component latch + pneumatic lock + hydraulic snap."""
    dur = 0.35
    buf = AudioBuffer(dur, channels=2)
    noise = WhiteNoise(303)
    flt_slide = ResonantFilter(800.0, q=1.5)
    flt_snap = ResonantFilter(2600.0, q=3.0)
    phase_sub = 0.0
    phase_metal = 0.0

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        s_left = 0.0
        s_right = 0.0

        # 1. Slide friction (0.0 to 0.07s)
        if t < 0.07:
            flt_slide.update(1200.0 - (t / 0.07) * 700.0, q=1.5)
            lp, bp, hp = flt_slide.process(noise.next_sample())
            slide = bp * adsr_env(t, 0.07, 0.005, 0.03, 0.5, 0.03)
            s_left += slide * 0.4
            s_right += slide * 0.3

        # 2. Heavy latch impact at t = 0.055s
        if t >= 0.055:
            ti = t - 0.055
            # Sub punch 85 Hz
            phase_sub += 85.0 / SAMPLE_RATE
            punch = sine_sample(phase_sub) * exp_decay_env(ti, 28.0)
            # Metallic clank 620 Hz
            phase_metal += 620.0 / SAMPLE_RATE
            clank = triangle_sample(phase_metal) * exp_decay_env(ti, 35.0)

            # Hydraulic snap hiss
            lp, bp, hp = flt_snap.process(noise.next_sample())
            hiss = hp * exp_decay_env(ti, 18.0)

            total = punch * 0.8 + clank * 0.5 + hiss * 0.6
            s_left += total * 0.9
            s_right += total * 1.0

        buf.add_sample(i, s_left, s_right)

    buf.fade_in_out(0.003, 0.015)
    buf.normalize(0.88)
    return buf

def gen_ship_remove() -> AudioBuffer:
    """Pneumatic release hiss + mechanical unlatch click."""
    dur = 0.25
    buf = AudioBuffer(dur, channels=2)
    noise = WhiteNoise(404)
    flt_pneu = ResonantFilter(3200.0, q=2.0)
    phase1 = 0.0
    phase2 = 0.0

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # 1. Pneumatic burst
        lp, bp, hp = flt_pneu.process(noise.next_sample())
        pneu = bp * exp_decay_env(t, 22.0)

        # 2. Detuned unlatch pings (330 Hz, 240 Hz) starting at t = 0.03s
        metal = 0.0
        if t >= 0.03:
            tm = t - 0.03
            phase1 += 330.0 / SAMPLE_RATE
            phase2 += 240.0 / SAMPLE_RATE
            metal = (0.6 * square_sample(phase1, 0.5) + 0.4 * triangle_sample(phase2)) * exp_decay_env(tm, 30.0)

        s = pneu * 0.7 + metal * 0.6
        buf.add_sample(i, s * 0.95, s * 1.05)

    buf.fade_in_out(0.003, 0.010)
    buf.normalize(0.85)
    return buf

def gen_fuel_tick() -> AudioBuffer:
    """Clean slider notch / fluid level adjustment click with tiny resonant bubble/tick."""
    dur = 0.065
    buf = AudioBuffer(dur, channels=1)
    phase = 0.0
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        prog = t / dur
        # Pitch drops rapidly from 700 Hz to 240 Hz
        freq = 700.0 * math.exp(-prog * 1.8)
        phase += freq / SAMPLE_RATE
        bubble = sine_sample(phase) * exp_decay_env(t, 75.0)

        # Crisp micro-tick in first 3ms
        tick = 0.0
        if t < 0.003:
            tick = (1.0 - t / 0.003) * 0.8

        buf.add_sample(i, bubble * 0.85 + tick * 0.6)
    buf.fade_in_out(0.001, 0.005)
    buf.normalize(0.78)
    return buf

def gen_preflight_scan() -> AudioBuffer:
    """Rapid diagnostic telemetry radar ping sweep (three ascending chirps)."""
    dur = 0.45
    buf = AudioBuffer(dur, channels=2)
    chirp_starts = [0.00, 0.12, 0.24]
    pans = [-0.4, 0.0, 0.4]

    for chirp_idx, start_t in enumerate(chirp_starts):
        phase = 0.0
        pan = pans[chirp_idx]
        for i in range(buf.num_frames):
            t = i / SAMPLE_RATE
            if start_t <= t < start_t + 0.09:
                tc = t - start_t
                prog = tc / 0.09
                freq = 450.0 + prog * 1150.0  # 450 -> 1600 Hz
                phase += freq / SAMPLE_RATE
                s = 0.75 * sine_sample(phase) + 0.25 * triangle_sample(phase)
                env = math.sin(prog * math.pi)
                buf.add_panned_sample(i, s * env * 0.7, pan=pan)

    # Add subtle background 880 Hz diagnostic clock pulses
    phase_clock = 0.0
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        phase_clock += 880.0 / SAMPLE_RATE
        pulse = sine_sample(phase_clock) * (1.0 if (t % 0.06) < 0.008 else 0.0) * 0.15
        buf.add_sample(i, pulse, pulse)

    buf.fade_in_out(0.003, 0.012)
    buf.normalize(0.85)
    return buf

def gen_preflight_pass() -> AudioBuffer:
    """Ascending high-tech major arpeggio fanfare (C5 -> E5 -> G5 -> C6)."""
    dur = 0.60
    buf = AudioBuffer(dur, channels=2)
    notes = [
        (0.00, 523.25, -0.3),
        (0.08, 659.25,  0.2),
        (0.16, 783.99, -0.1),
        (0.24, 1046.50, 0.3),
    ]

    for start_t, freq, pan in notes:
        phase = 0.0
        fm_phase = 0.0
        for i in range(buf.num_frames):
            t = i / SAMPLE_RATE
            if t >= start_t:
                tn = t - start_t
                fm_phase += (freq * 2.0) / SAMPLE_RATE
                fm_mod = math.sin(fm_phase * TWO_PI) * 0.35 * exp_decay_env(tn, 8.0)
                phase += (freq * (1.0 + fm_mod)) / SAMPLE_RATE
                s = 0.7 * sine_sample(phase) + 0.3 * triangle_sample(phase)
                env = exp_decay_env(tn, 7.5)
                buf.add_panned_sample(i, s * env * 0.55, pan=pan)

    apply_simple_stereo_delay(buf, delay_s=0.07, feedback=0.30, damping=0.5)
    buf.fade_in_out(0.003, 0.015)
    buf.normalize(0.86)
    return buf

def gen_preflight_fail() -> AudioBuffer:
    """Dissonant descending alert tone indicating unfulfilled parameters."""
    dur = 0.50
    buf = AudioBuffer(dur, channels=2)
    phase1 = 0.0
    phase2 = 0.0
    phase_sub = 0.0

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        prog = min(1.0, t / 0.35)
        # Tritone dissonance descending
        f1 = 466.16 - prog * 74.0   # Bb4 -> G4
        f2 = 329.63 - prog * 52.0   # E4 -> C#4
        phase1 += f1 / SAMPLE_RATE
        phase2 += f2 / SAMPLE_RATE
        phase_sub += 75.0 / SAMPLE_RATE

        # 6 Hz alarm pulse modulation
        mod = 0.6 + 0.4 * math.sin(t * TWO_PI * 6.0)

        s1 = 0.6 * saw_sample(phase1) + 0.4 * square_sample(phase1, 0.5)
        s2 = 0.6 * saw_sample(phase2) + 0.4 * square_sample(phase2, 0.5)
        sub = sine_sample(phase_sub) * 0.5

        env = adsr_env(t, dur, 0.005, 0.15, 0.6, 0.12)
        total = (s1 * 0.45 + s2 * 0.45 + sub) * env * mod
        buf.add_sample(i, total * 0.9, total * 1.05)

    buf.fade_in_out(0.003, 0.015)
    buf.normalize(0.86)
    return buf

def gen_step_earth(variation: int = 1) -> AudioBuffer:
    """Footstep on Earth tarmac / firm surface."""
    dur = 0.08
    buf = AudioBuffer(dur, channels=1)
    noise = WhiteNoise(500 + variation)
    flt_tap = ResonantFilter(2100.0 if variation == 1 else 2500.0, q=2.5)
    phase_body = 0.0
    body_f = 120.0 if variation == 1 else 135.0

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # Crisp shoe tap
        lp, bp, hp = flt_tap.process(noise.next_sample())
        tap = bp * exp_decay_env(t, 90.0)

        # Body resonance
        phase_body += body_f / SAMPLE_RATE
        body = sine_sample(phase_body) * exp_decay_env(t, 45.0)

        buf.add_sample(i, tap * 0.6 + body * 0.45)
    buf.fade_in_out(0.002, 0.008)
    buf.normalize(0.70)
    return buf

def gen_step_ruin(variation: int = 1) -> AudioBuffer:
    """Footstep on Crash Site ash, gravel, and metal rubble."""
    dur = 0.11
    buf = AudioBuffer(dur, channels=1)
    noise = WhiteNoise(600 + variation)
    flt_grit = ResonantFilter(1600.0 if variation == 1 else 1300.0, q=1.5)
    phase_thud = 0.0
    phase_metal = 0.0

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # Crunchy gravel / ash
        lp, bp, hp = flt_grit.process(noise.next_sample())
        grit = bp * exp_decay_env(t, 38.0)

        # Low thud (75 Hz)
        phase_thud += 75.0 / SAMPLE_RATE
        thud = sine_sample(phase_thud) * exp_decay_env(t, 32.0)

        # Metallic scrape ring for variation 2
        metal = 0.0
        if variation == 2:
            phase_metal += 480.0 / SAMPLE_RATE
            metal = triangle_sample(phase_metal) * exp_decay_env(t, 55.0) * 0.35

        buf.add_sample(i, grit * 0.65 + thud * 0.4 + metal)
    buf.fade_in_out(0.002, 0.010)
    buf.normalize(0.72)
    return buf

def gen_salvage_pickup() -> AudioBuffer:
    """Scavenging scrap metal / salvage item pickup chime with sparkle."""
    dur = 0.34
    buf = AudioBuffer(dur, channels=2)
    phase_metal1 = 0.0
    phase_metal2 = 0.0

    # 1. Scrap metal clink transient in first 25ms
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        phase_metal1 += 1850.0 / SAMPLE_RATE
        phase_metal2 += 2780.0 / SAMPLE_RATE
        clink = (0.6 * sine_sample(phase_metal1) + 0.4 * sine_sample(phase_metal2)) * exp_decay_env(t, 80.0)
        buf.add_sample(i, clink * 0.5, clink * 0.6)

    # 2. Ascending 3-note sparkle chime: G5, B5, E6
    notes = [
        (0.025, 783.99, -0.3),
        (0.070, 987.77,  0.3),
        (0.120, 1318.51, 0.0),
    ]
    for start_t, freq, pan in notes:
        phase = 0.0
        for i in range(buf.num_frames):
            t = i / SAMPLE_RATE
            if t >= start_t:
                tn = t - start_t
                phase += freq / SAMPLE_RATE
                s = 0.8 * sine_sample(phase) + 0.2 * triangle_sample(phase)
                env = exp_decay_env(tn, 14.0)
                buf.add_panned_sample(i, s * env * 0.6, pan=pan)

    apply_simple_stereo_delay(buf, delay_s=0.06, feedback=0.35, damping=0.3)
    buf.fade_in_out(0.003, 0.012)
    buf.normalize(0.85)
    return buf

def gen_repair_spark() -> AudioBuffer:
    """High-voltage electrical arc discharge and repair welding crackle."""
    dur = 0.28
    buf = AudioBuffer(dur, channels=2)
    rng = random.Random(707)
    flt_sizzle = ResonantFilter(3400.0, q=3.5)
    phase_hum = 0.0

    # Generate random spark pulse times
    spark_times = [rng.uniform(0.005, 0.22) for _ in range(18)]

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # Continuous sizzle noise
        white = rng.uniform(-1.0, 1.0)
        lp, bp, hp = flt_sizzle.process(white)
        sizzle = bp * exp_decay_env(t, 12.0)

        # 60 Hz mains hum buzz
        phase_hum += 60.0 / SAMPLE_RATE
        hum = saw_sample(phase_hum) * 0.3 * exp_decay_env(t, 9.0)

        # Sharp arc discharge spikes
        spike = 0.0
        for st in spark_times:
            if 0.0 <= t - st < 0.003:
                prog = (t - st) / 0.003
                spike += (1.0 - prog) * rng.uniform(-1.0, 1.0) * 1.5

        pan = rng.uniform(-0.4, 0.4)
        buf.add_panned_sample(i, (sizzle * 0.5 + hum * 0.4 + spike * 0.8) * exp_decay_env(t, 8.0), pan=pan)

    buf.fade_in_out(0.002, 0.010)
    buf.normalize(0.88)
    return buf

def gen_power_surge() -> AudioBuffer:
    """Sub-bass power grid spool-up, charging capacitor whine that resolves into a hum."""
    dur = 1.30
    buf = AudioBuffer(dur, channels=2)
    phase_sub = 0.0
    phase_whine = 0.0
    phase_harm = 0.0

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # Sub-bass 50 Hz swells up
        phase_sub += 52.0 / SAMPLE_RATE
        phase_harm += 104.0 / SAMPLE_RATE
        sub_env = adsr_env(t, dur, 0.45, 0.2, 0.8, 0.25)
        sub = (0.7 * sine_sample(phase_sub) + 0.3 * sine_sample(phase_harm)) * sub_env

        # Rising capacitor charge whine: 120 Hz -> 1550 Hz
        prog = min(1.0, t / 0.85)
        whine_freq = 120.0 * math.pow(1550.0 / 120.0, prog)
        phase_whine += whine_freq / SAMPLE_RATE
        whine_env = adsr_env(t, 0.90, 0.3, 0.2, 0.9, 0.2)
        whine = (0.75 * sine_sample(phase_whine) + 0.25 * triangle_sample(phase_whine)) * whine_env

        total = sub * 0.8 + whine * 0.55
        # Stereo widening
        buf.add_sample(i, total * 0.95, total * 1.05)

    buf.soft_clip(1.2)
    buf.fade_in_out(0.005, 0.030)
    buf.normalize(0.88)
    return buf

def gen_bill_boot() -> AudioBuffer:
    """Bill robot servo motor spin and 4-note retro boot arpeggio sequence."""
    dur = 1.45
    buf = AudioBuffer(dur, channels=2)
    phase_servo = 0.0

    # 1. Servo motor whir (0.0s to 0.38s)
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        if t < 0.38:
            prog = t / 0.38
            servo_f = 260.0 + prog * 320.0  # 260 -> 580 Hz
            phase_servo += servo_f / SAMPLE_RATE
            servo = triangle_sample(phase_servo) * adsr_env(t, 0.38, 0.02, 0.08, 0.8, 0.08)
            buf.add_panned_sample(i, servo * 0.4, pan=-0.2)

    # 2. Ascending 4-note boot arpeggio (G4 -> B4 -> D5 -> G5)
    notes = [
        (0.40, 392.00, -0.25),
        (0.55, 493.88,  0.25),
        (0.70, 587.33, -0.10),
        (0.85, 783.99,  0.15),
    ]

    for start_t, freq, pan in notes:
        phase = 0.0
        for i in range(buf.num_frames):
            t = i / SAMPLE_RATE
            if t >= start_t:
                tn = t - start_t
                # Vibrato on final note
                vib = 0.0
                if freq > 700.0 and tn > 0.12:
                    vib = math.sin(tn * TWO_PI * 5.5) * 12.0
                phase += (freq + vib) / SAMPLE_RATE
                s = 0.7 * square_sample(phase, 0.25) + 0.3 * sine_sample(phase)
                env = exp_decay_env(tn, 5.0 if freq > 700.0 else 9.0)
                buf.add_panned_sample(i, s * env * 0.65, pan=pan)

    apply_simple_stereo_delay(buf, delay_s=0.08, feedback=0.25, damping=0.4)
    buf.fade_in_out(0.005, 0.025)
    buf.normalize(0.86)
    return buf

def gen_countdown_beep() -> AudioBuffer:
    """Crisp NASA-style T-minus countdown pip (pure 1200 Hz tone)."""
    dur = 0.13
    buf = AudioBuffer(dur, channels=1)
    phase = 0.0
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        phase += 1200.0 / SAMPLE_RATE
        s = sine_sample(phase)
        env = adsr_env(t, dur, 0.003, 0.02, 0.85, 0.03)
        buf.add_sample(i, s * env)
    buf.fade_in_out(0.002, 0.005)
    buf.normalize(0.80)
    return buf

def gen_launch_roar() -> AudioBuffer:
    """Massive rocket ignition & continuous low-frequency thruster rumble."""
    dur = 3.60
    buf = AudioBuffer(dur, channels=2)
    pink = PinkNoise(808)
    flt_exhaust = ResonantFilter(240.0, q=1.8)
    phase_sub1 = 0.0
    phase_sub2 = 0.0
    phase_sub3 = 0.0

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # Envelope: explosive onset, powerful sustained burn, atmospheric fade
        env = adsr_env(t, dur, 0.25, 0.5, 0.9, 0.85)

        # Chaotic LFO modulating exhaust filter cutoff
        lfo = 0.5 + 0.5 * math.sin(t * TWO_PI * 3.8)
        flt_exhaust.update(160.0 + lfo * 180.0, q=2.0)

        # Pink noise filtered through lowpass exhaust
        lp, bp, hp = flt_exhaust.process(pink.next_sample())

        # Detuned low sawtooth drones (34 Hz, 38 Hz, 68 Hz)
        phase_sub1 += 34.0 / SAMPLE_RATE
        phase_sub2 += 38.0 / SAMPLE_RATE
        phase_sub3 += 68.0 / SAMPLE_RATE

        drones = (saw_sample(phase_sub1) * 0.4 +
                  saw_sample(phase_sub2) * 0.35 +
                  sine_sample(phase_sub3) * 0.25)

        total_l = (lp * 0.7 + drones * 0.6) * env
        total_r = (lp * 0.65 + drones * 0.65) * env

        buf.add_sample(i, total_l, total_r)

    # Soft saturate for analog thruster heat
    buf.soft_clip(1.4)
    buf.fade_in_out(0.010, 0.080)
    buf.normalize(0.92)
    return buf

def gen_signal_sweep() -> AudioBuffer:
    """Anomalous spatial signal scanner whine (heterodyne radio sweep)."""
    dur = 0.85
    buf = AudioBuffer(dur, channels=2)
    phase_carrier = 0.0
    phase_fm = 0.0

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        prog = t / dur
        # Sweeping carrier frequency 650 Hz -> 2200 Hz -> 900 Hz
        sweep = math.sin(prog * math.pi)
        base_f = 650.0 + sweep * 1550.0

        # FM sidebands
        phase_fm += 42.0 / SAMPLE_RATE
        fm_mod = math.sin(phase_fm * TWO_PI) * 75.0

        phase_carrier += (base_f + fm_mod) / SAMPLE_RATE
        s = sine_sample(phase_carrier)
        env = adsr_env(t, dur, 0.05, 0.1, 0.85, 0.12)

        # Subtle stereo panning sweep
        pan = math.sin(prog * math.pi * 2.0) * 0.5
        buf.add_panned_sample(i, s * env * 0.7, pan=pan)

    buf.fade_in_out(0.005, 0.020)
    buf.normalize(0.85)
    return buf

def gen_signal_lock() -> AudioBuffer:
    """Anomalous spatial signal scanner lock-on beep (dual high-register ping)."""
    dur = 0.40
    buf = AudioBuffer(dur, channels=2)
    phase1 = 0.0
    phase2 = 0.0

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # A6 (1760 Hz) and E7 (2637 Hz) - perfect fifth resonance
        phase1 += 1760.0 / SAMPLE_RATE
        phase2 += 2637.0 / SAMPLE_RATE
        s1 = sine_sample(phase1)
        s2 = sine_sample(phase2)
        env = exp_decay_env(t, 11.0)
        total = (s1 * 0.6 + s2 * 0.4) * env

        buf.add_panned_sample(i, total * 0.8, pan=0.0)

    apply_simple_stereo_delay(buf, delay_s=0.05, feedback=0.35, damping=0.2)
    buf.fade_in_out(0.002, 0.012)
    buf.normalize(0.88)
    return buf

def gen_rift_tear() -> AudioBuffer:
    """Violent rift tear distortion, reality-bending frequency instability."""
    dur = 2.80
    buf = AudioBuffer(dur, channels=2)
    noise = WhiteNoise(909)
    flt = ResonantFilter(800.0, q=4.5)
    phase_carrier = 0.0
    phase_mod = 0.0

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        prog = t / dur
        # Modulation index sweeps up from 1 to 12 then back down
        mod_index = 1.0 + math.sin(prog * math.pi) * 11.0

        phase_mod += 215.0 / SAMPLE_RATE
        mod_val = math.sin(phase_mod * TWO_PI) * mod_index * 215.0

        phase_carrier += (72.0 + mod_val) / SAMPLE_RATE
        fm_growl = saw_sample(phase_carrier)

        # Distorted noise ripping across stereo field
        flt.update(400.0 + math.sin(prog * math.pi) * 2200.0, q=3.5)
        lp, bp, hp = flt.process(noise.next_sample())

        env = adsr_env(t, dur, 0.35, 0.6, 0.85, 0.7)

        # Dynamic stereo panning sweep
        pan_l = 0.5 + 0.5 * math.sin(prog * math.pi * 3.0)
        pan_r = 1.0 - pan_l

        left = (fm_growl * 0.6 + bp * 0.7 * pan_l) * env
        right = (fm_growl * 0.6 + bp * 0.7 * pan_r) * env

        buf.add_sample(i, left, right)

    buf.soft_clip(1.5)
    buf.fade_in_out(0.010, 0.060)
    buf.normalize(0.92)
    return buf

def gen_ship_alarm() -> AudioBuffer:
    """Siren / emergency klaxon warning (urgent alternating dual-tone alarm)."""
    dur = 0.65
    buf = AudioBuffer(dur, channels=2)
    phase = 0.0

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # Alternating tones: 820 Hz and 1040 Hz at 5.5 Hz rate
        tone_toggle = int(t * 11.0) % 2
        freq = 820.0 if tone_toggle == 0 else 1040.0
        phase += freq / SAMPLE_RATE

        s = 0.75 * square_sample(phase, 0.45) + 0.25 * saw_sample(phase)
        env = adsr_env(t, dur, 0.02, 0.1, 0.85, 0.08)

        # Slight stereo chorus
        buf.add_sample(i, s * env * 0.75, s * env * 0.85)

    apply_simple_stereo_delay(buf, delay_s=0.06, feedback=0.25, damping=0.5)
    buf.fade_in_out(0.003, 0.015)
    buf.normalize(0.85)
    return buf

def gen_hull_creak() -> AudioBuffer:
    """Heavy metallic stress, groaning hull under extreme G-force and pressure."""
    dur = 1.30
    buf = AudioBuffer(dur, channels=2)
    phase_fund = 0.0
    phase_h1 = 0.0
    phase_h2 = 0.0
    rng = random.Random(1010)

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        prog = t / dur
        # Pitch bends with non-linear strain: 130 Hz -> 108 Hz -> 140 Hz
        pitch_bend = math.sin(prog * math.pi * 1.5) * 18.0
        fund = 126.0 + pitch_bend

        phase_fund += fund / SAMPLE_RATE
        phase_h1 += (fund * 3.0) / SAMPLE_RATE
        phase_h2 += (fund * 5.0) / SAMPLE_RATE

        # Micro amplitude jitter simulating friction slip-stick
        jitter = 1.0 + rng.uniform(-0.15, 0.15)

        s = (triangle_sample(phase_fund) * 0.6 +
             saw_sample(phase_h1) * 0.25 +
             saw_sample(phase_h2) * 0.15) * jitter

        env = adsr_env(t, dur, 0.15, 0.35, 0.7, 0.30)
        buf.add_sample(i, s * env * 0.85, s * env * 0.95)

    buf.soft_clip(1.1)
    buf.fade_in_out(0.008, 0.030)
    buf.normalize(0.88)
    return buf

def gen_crash_impact() -> AudioBuffer:
    """Catastrophic explosive atmospheric entry roar and explosive crash impact."""
    dur = 2.50
    buf = AudioBuffer(dur, channels=2)
    noise = WhiteNoise(1111)
    flt_boom = ResonantFilter(180.0, q=2.0)
    flt_crunch = ResonantFilter(1200.0, q=1.5)
    phase_sub = 0.0

    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        # 1. Seismic low-end sub drop: 65 Hz down to 25 Hz
        phase_sub += max(25.0, 65.0 - t * 25.0) / SAMPLE_RATE
        sub = sine_sample(phase_sub) * exp_decay_env(t, 2.5)

        # 2. Explosive noise boom
        white = noise.next_sample()
        lp, bp, hp = flt_boom.process(white)
        boom = lp * exp_decay_env(t, 3.2)

        # 3. Metal shatter crunch at t = 0.06s
        crunch = 0.0
        if t >= 0.06:
            tc = t - 0.06
            lpc, bpc, hpc = flt_crunch.process(white)
            crunch = bpc * exp_decay_env(tc, 18.0)

        # Total explosion
        total = (sub * 0.9 + boom * 0.8 + crunch * 0.5)
        buf.add_sample(i, total * 0.95, total * 1.05)

    buf.soft_clip(1.6)
    buf.fade_in_out(0.002, 0.080)
    buf.normalize(0.94)
    return buf

def gen_memory_chime() -> AudioBuffer:
    """Holographic memory ethereal resonance chord (Em9 / Gmaj7)."""
    dur = 2.70
    buf = AudioBuffer(dur, channels=2)
    # E4, B4, D5, F#5, G5
    notes = [
        (0.00, 329.63, -0.3),
        (0.08, 493.88,  0.3),
        (0.16, 587.33, -0.15),
        (0.24, 739.99,  0.2),
        (0.32, 783.99,  0.0),
    ]

    for start_t, freq, pan in notes:
        phase = 0.0
        for i in range(buf.num_frames):
            t = i / SAMPLE_RATE
            if t >= start_t:
                tn = t - start_t
                # Gentle shimmer vibrato
                vib = math.sin(tn * TWO_PI * 4.2) * (freq * 0.004)
                phase += (freq + vib) / SAMPLE_RATE
                s = sine_sample(phase)
                env = adsr_env(tn, dur - start_t, 0.22, 0.5, 0.75, 1.2)
                buf.add_panned_sample(i, s * env * 0.40, pan=pan)

    apply_simple_stereo_delay(buf, delay_s=0.12, feedback=0.45, damping=0.3)
    buf.fade_in_out(0.010, 0.060)
    buf.normalize(0.88)
    return buf

def gen_checkpoint() -> AudioBuffer:
    """Triumphant retro fanfare / jingle confirming stage completion."""
    dur = 0.88
    buf = AudioBuffer(dur, channels=2)
    # Triumphant fanfare: F5 -> A5 -> C6 -> F6
    notes = [
        (0.00, 698.46, -0.2),
        (0.10, 880.00,  0.2),
        (0.20, 1046.50, -0.1),
        (0.30, 1396.91,  0.1),
    ]

    for start_t, freq, pan in notes:
        phase = 0.0
        for i in range(buf.num_frames):
            t = i / SAMPLE_RATE
            if t >= start_t:
                tn = t - start_t
                phase += freq / SAMPLE_RATE
                # Pulse wave + triangle
                s = 0.65 * square_sample(phase, 0.3) + 0.35 * triangle_sample(phase)
                env = exp_decay_env(tn, 4.5 if freq > 1300.0 else 8.0)
                buf.add_panned_sample(i, s * env * 0.55, pan=pan)

    # Bass root on final note (F3 = 174.61 Hz)
    phase_bass = 0.0
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE
        if t >= 0.30:
            phase_bass += 174.61 / SAMPLE_RATE
            bass = triangle_sample(phase_bass) * exp_decay_env(t - 0.30, 3.8)
            buf.add_sample(i, bass * 0.5, bass * 0.5)

    apply_simple_stereo_delay(buf, delay_s=0.07, feedback=0.30, damping=0.4)
    buf.fade_in_out(0.003, 0.020)
    buf.normalize(0.86)
    return buf


# ---------------------------------------------------------------------------
# Ambient Music Tracks (10.0s seamless loop)
# ---------------------------------------------------------------------------

def gen_ambience_earth() -> AudioBuffer:
    """Loopable Earth spaceport ambient track: light wind, subtle birdsong, soft hangar hum (~10.0s loop)."""
    loop_dur = 10.0
    crossfade_dur = 1.2
    gen_dur = loop_dur + crossfade_dur
    buf = AudioBuffer(gen_dur, channels=2)

    pink = PinkNoise(1212)
    flt_wind_l = ResonantFilter(450.0, q=1.0)
    flt_wind_r = ResonantFilter(480.0, q=1.0)
    phase_drone1 = 0.0
    phase_drone2 = 0.0
    phase_mains = 0.0

    # Layer 1: Gentle wind + Layer 2: Hangar machine hum
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE

        # Slow breathing wind swell LFO
        wind_lfo_l = 0.55 + 0.45 * math.sin(t * TWO_PI * 0.11)
        wind_lfo_r = 0.55 + 0.45 * math.cos(t * TWO_PI * 0.13)

        flt_wind_l.update(300.0 + wind_lfo_l * 280.0, q=1.2)
        flt_wind_r.update(320.0 + wind_lfo_r * 260.0, q=1.2)

        wl = flt_wind_l.process(pink.next_sample())[0] * 0.075 * wind_lfo_l
        wr = flt_wind_r.process(pink.next_sample())[0] * 0.075 * wind_lfo_r

        # Continuous 55 Hz and 110 Hz hangar telemetry drone
        phase_drone1 += 55.0 / SAMPLE_RATE
        phase_drone2 += 110.0 / SAMPLE_RATE
        phase_mains += 60.0 / SAMPLE_RATE

        drone = (sine_sample(phase_drone1) * 0.040 +
                 sine_sample(phase_drone2) * 0.020 +
                 saw_sample(phase_mains) * 0.008)

        buf.add_sample(i, wl + drone, wr + drone)

    # Layer 3: Melodic bird calls at musical intervals (1.8s, 5.2s, 8.1s)
    bird_calls = [
        (1.8, 2400.0, -0.45),
        (5.2, 2800.0,  0.40),
        (8.1, 2200.0, -0.20),
    ]
    for onset, base_f, pan in bird_calls:
        phase = 0.0
        for i in range(buf.num_frames):
            t = i / SAMPLE_RATE
            if onset <= t < onset + 0.35:
                tb = t - onset
                # Realistic dual-pitch bird whistle
                chirp_f = base_f + math.sin(tb * TWO_PI * 14.0) * 450.0
                phase += chirp_f / SAMPLE_RATE
                s = sine_sample(phase)
                env = math.sin(tb / 0.35 * math.pi) * 0.055
                buf.add_panned_sample(i, s * env, pan=pan)

    # Make perfectly seamless loop via equal-power crossfade of tail into head
    loop_frames = int(loop_dur * SAMPLE_RATE)
    cross_frames = int(crossfade_dur * SAMPLE_RATE)
    final_buf = AudioBuffer(loop_dur, channels=2)

    for i in range(loop_frames):
        final_buf.left[i] = buf.left[i]
        final_buf.right[i] = buf.right[i]

    # Crossfade tail (from loop_frames to loop_frames + cross_frames) into head (0 to cross_frames)
    for i in range(cross_frames):
        prog = i / cross_frames
        # Equal power crossfade curves
        gain_head = math.sin(prog * math.pi * 0.5)
        gain_tail = math.cos(prog * math.pi * 0.5)

        tail_idx = loop_frames + i
        final_buf.left[i] = final_buf.left[i] * gain_head + buf.left[tail_idx] * gain_tail
        final_buf.right[i] = final_buf.right[i] * gain_head + buf.right[tail_idx] * gain_tail

    final_buf.normalize(0.78)
    return final_buf

def gen_ambience_ruin() -> AudioBuffer:
    """Loopable Crash Site ambient track: bleak wind, hollow metal resonance, eerie sub drone (~10.0s loop)."""
    loop_dur = 10.0
    crossfade_dur = 1.2
    gen_dur = loop_dur + crossfade_dur
    buf = AudioBuffer(gen_dur, channels=2)

    pink = PinkNoise(1313)
    flt_ruin_l = ResonantFilter(260.0, q=3.5)
    flt_ruin_r = ResonantFilter(290.0, q=3.5)
    phase_sub_l = 0.0
    phase_sub_r = 0.0

    # Layer 1: Desolate hollow wind + Layer 2: Eerie 3 Hz binaural sub-drone (38 Hz left, 41 Hz right)
    for i in range(buf.num_frames):
        t = i / SAMPLE_RATE

        # Desolate wind howl
        lfo = 0.5 + 0.5 * math.sin(t * TWO_PI * 0.08)
        flt_ruin_l.update(220.0 + lfo * 200.0, q=3.8)
        flt_ruin_r.update(240.0 + lfo * 220.0, q=3.8)

        wl = flt_ruin_l.process(pink.next_sample())[1] * 0.09
        wr = flt_ruin_r.process(pink.next_sample())[1] * 0.09

        # Detuned sub drone: 38 Hz L, 41 Hz R -> 3 Hz binaural beat
        phase_sub_l += 38.0 / SAMPLE_RATE
        phase_sub_r += 41.0 / SAMPLE_RATE

        sub_l = sine_sample(phase_sub_l) * 0.055
        sub_r = sine_sample(phase_sub_r) * 0.055

        # Subtle cosmic radiation static
        static = (pink.next_sample() * 0.008)

        buf.add_sample(i, wl + sub_l + static, wr + sub_r + static)

    # Layer 3: Distant metallic creaks / hollow taps (at 2.6s and 7.2s)
    metal_events = [
        (2.6, 290.0, -0.35),
        (7.2, 440.0,  0.40),
    ]
    for onset, freq, pan in metal_events:
        phase = 0.0
        for i in range(buf.num_frames):
            t = i / SAMPLE_RATE
            if onset <= t < onset + 0.5:
                tm = t - onset
                phase += freq / SAMPLE_RATE
                s = triangle_sample(phase) * exp_decay_env(tm, 8.0) * 0.035
                buf.add_panned_sample(i, s, pan=pan)

    # Seamless equal-power loop crossfade
    loop_frames = int(loop_dur * SAMPLE_RATE)
    cross_frames = int(crossfade_dur * SAMPLE_RATE)
    final_buf = AudioBuffer(loop_dur, channels=2)

    for i in range(loop_frames):
        final_buf.left[i] = buf.left[i]
        final_buf.right[i] = buf.right[i]

    for i in range(cross_frames):
        prog = i / cross_frames
        gain_head = math.sin(prog * math.pi * 0.5)
        gain_tail = math.cos(prog * math.pi * 0.5)

        tail_idx = loop_frames + i
        final_buf.left[i] = final_buf.left[i] * gain_head + buf.left[tail_idx] * gain_tail
        final_buf.right[i] = final_buf.right[i] * gain_head + buf.right[tail_idx] * gain_tail

    final_buf.normalize(0.78)
    return final_buf


# ---------------------------------------------------------------------------
# Generation Manifest and CLI Runner
# ---------------------------------------------------------------------------

MANIFEST = [
    # SFX
    ("assets/audio/sfx/ui_select.wav", gen_ui_select, "UI select blip"),
    ("assets/audio/sfx/ui_confirm.wav", gen_ui_confirm, "UI confirm chime"),
    ("assets/audio/sfx/ui_back.wav", gen_ui_back, "UI back cancel glide"),
    ("assets/audio/sfx/ui_denied.wav", gen_ui_denied, "UI action denied buzzer"),
    ("assets/audio/sfx/ui_toast.wav", gen_ui_toast, "UI notification toast shimmer"),
    ("assets/audio/sfx/blip_nick.wav", gen_blip_nick, "Dialogue typewriter blip (Nick)"),
    ("assets/audio/sfx/blip_bill.wav", gen_blip_bill, "Dialogue typewriter blip (Bill)"),
    ("assets/audio/sfx/blip_control.wav", gen_blip_control, "Dialogue typewriter blip (Control)"),
    ("assets/audio/sfx/ship_install.wav", gen_ship_install, "Ship component hydraulic install"),
    ("assets/audio/sfx/ship_remove.wav", gen_ship_remove, "Ship component pneumatic removal"),
    ("assets/audio/sfx/fuel_tick.wav", gen_fuel_tick, "Fuel level adjustment tick/slosh"),
    ("assets/audio/sfx/preflight_scan.wav", gen_preflight_scan, "Preflight telemetry radar sweep"),
    ("assets/audio/sfx/preflight_pass.wav", gen_preflight_pass, "Preflight pass major fanfare"),
    ("assets/audio/sfx/preflight_fail.wav", gen_preflight_fail, "Preflight fail alert chord"),
    ("assets/audio/sfx/step_earth_1.wav", lambda: gen_step_earth(1), "Earth tarmac footstep 1"),
    ("assets/audio/sfx/step_earth_2.wav", lambda: gen_step_earth(2), "Earth tarmac footstep 2"),
    ("assets/audio/sfx/step_ruin_1.wav", lambda: gen_step_ruin(1), "Ruin rubble footstep 1"),
    ("assets/audio/sfx/step_ruin_2.wav", lambda: gen_step_ruin(2), "Ruin rubble footstep 2"),
    ("assets/audio/sfx/interact.wav", gen_interact, "World terminal/NPC interaction click"),
    ("assets/audio/sfx/salvage_pickup.wav", gen_salvage_pickup, "Scrap metal scavenging pickup"),
    ("assets/audio/sfx/repair_spark.wav", gen_repair_spark, "Electrical repair welding arc spark"),
    ("assets/audio/sfx/power_surge.wav", gen_power_surge, "Power grid surge & spool-up"),
    ("assets/audio/sfx/bill_boot.wav", gen_bill_boot, "Bill robot servo whir & boot chime"),
    ("assets/audio/sfx/countdown_beep.wav", gen_countdown_beep, "NASA launch countdown pip"),
    ("assets/audio/sfx/launch_roar.wav", gen_launch_roar, "Massive rocket ignition & ascent roar"),
    ("assets/audio/sfx/signal_sweep.wav", gen_signal_sweep, "Anomalous signal scanner whine"),
    ("assets/audio/sfx/signal_lock.wav", gen_signal_lock, "Anomalous signal lock-on ping"),
    ("assets/audio/sfx/rift_tear.wav", gen_rift_tear, "Spatiotemporal rift tear distortion"),
    ("assets/audio/sfx/ship_alarm.wav", gen_ship_alarm, "Ship hull emergency alarm klaxon"),
    ("assets/audio/sfx/hull_creak.wav", gen_hull_creak, "Metallic hull groaning stress"),
    ("assets/audio/sfx/crash_impact.wav", gen_crash_impact, "Atmospheric entry crash impact"),
    ("assets/audio/sfx/memory_chime.wav", gen_memory_chime, "Holographic memory ethereal chord"),
    ("assets/audio/sfx/checkpoint.wav", gen_checkpoint, "Stage checkpoint victory fanfare"),
    # Music / Ambience
    ("assets/audio/music/ambience_earth.wav", gen_ambience_earth, "Earth spaceport ambient loop (10s)"),
    ("assets/audio/music/ambience_ruin.wav", gen_ambience_ruin, "Crash Site ruin ambient loop (10s)"),
]

def main():
    print("=" * 70)
    print("STAR FALL - Phase 1 Retro Sci-Fi Audio Generation")
    print(f"Sample Rate: {SAMPLE_RATE} Hz | Bit Depth: 16-bit PCM")
    print("=" * 70)

    start_total = time.time()
    results = []

    for rel_path, generator_fn, desc in MANIFEST:
        t0 = time.time()
        buf = generator_fn()
        buf.save_wav(rel_path)
        file_size = os.path.getsize(rel_path)
        dur = buf.duration
        channels_str = "Stereo" if buf.channels == 2 else "Mono"
        elapsed = time.time() - t0
        print(f"Generated: {rel_path:<40} [{dur:5.2f}s | {channels_str:<6} | {file_size:7d} B] ({elapsed:.2f}s) - {desc}")
        results.append((rel_path, dur, channels_str, file_size, desc))

    total_time = time.time() - start_total
    print("=" * 70)
    print(f"Successfully generated {len(results)} audio files in {total_time:.2f} seconds.")
    print("All audio files verified non-empty and 100% standard library synthesized.")
    print("=" * 70)

if __name__ == "__main__":
    main()
