%% PHASE 1 -- FMCW SIGNAL MODEL
%
% Builds a single sawtooth linear FMCW chirp, a single stationary point-target
% echo, dechirps to form the beat signal, and verifies the FFT peak against the
% analytically predicted beat frequency (must land within one FFT bin).
%
% Reads all parameters from config/get_radar_params.m (single source of truth --
% no magic numbers are redefined here). See docs/architecture.md and
% docs/parameter_reference.md for the full parameter rationale.
%
% Deliverables: results/01_beat_signal_fft.png and printed/saved numeric verification
% (results/phase1_results.mat, git-ignored).

clear; clc; close all;

addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

params = get_radar_params();
rng(params.sim.seed);

%% Target definition (Phase 1: single stationary target)
target.range       = 30.0;   % [m] -- well inside R_max (~60 m), arbitrary but documented choice
target.attenuation = 0.30;   % [linear amplitude] -- fixed reflectivity scalar (decision D10)

validate_params(params, struct('range', target.range));

%% Generate transmit chirp and target echo, then dechirp
[tx, t] = generate_chirp(params);
rx      = simulate_target_echo(params, t, target.range, target.attenuation);
beat    = dechirp_mix(tx, rx);

%% Theoretical beat frequency
f_beat_theory = 2 * target.range * params.wave.S / params.c;

%% FFT of the beat signal
Nfft = params.adc.Nfft_range;
spectrum = fft(beat, Nfft);
spectrum_mag = abs(spectrum) / params.adc.Ns;
freq_axis = (0:Nfft-1) * (params.adc.Fs / Nfft);

% Beat frequency is one-sided/positive by the dechirp convention (D4); only the
% first half of the FFT (0 .. Fs/2) is physically meaningful for a positive-range target.
half = 1:floor(Nfft/2);
[peak_mag, peak_idx] = max(spectrum_mag(half));
f_beat_measured = freq_axis(peak_idx);

bin_width = params.adc.Fs / Nfft;
abs_error = abs(f_beat_measured - f_beat_theory);
pass = abs_error <= bin_width;

spectrum_db = 20*log10(spectrum_mag(half) / max(spectrum_mag(half)) + eps);

%% Report to console
fprintf('--- PHASE 1 VERIFICATION ---\n');
fprintf('Theoretical f_beat : %.6f MHz\n', f_beat_theory/1e6);
fprintf('Measured f_beat    : %.6f MHz\n', f_beat_measured/1e6);
fprintf('FFT bin width      : %.6f MHz\n', bin_width/1e6);
fprintf('Absolute error     : %.6f MHz\n', abs_error/1e6);
fprintf('PASS (<= 1 bin)    : %d\n', pass);

%% Figure
results_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'results');
if ~exist(results_dir, 'dir'); mkdir(results_dir); end
plot_beat_fft(freq_axis(half), spectrum_db, f_beat_theory, f_beat_measured, bin_width, ...
    fullfile(results_dir, '01_beat_signal_fft.png'));

%% Save numeric results for the tests
save(fullfile(fileparts(mfilename('fullpath')), '..', 'results', 'phase1_results.mat'), ...
    'f_beat_theory', 'f_beat_measured', 'bin_width', 'abs_error', 'pass', 'target', 'params');
