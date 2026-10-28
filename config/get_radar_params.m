function params = get_radar_params()
%   GET_RADAR_PARAMS: All FMCW radar simulation parameters.
%
%   params = GET_RADAR_PARAMS() returns a struct containing every parameter used
%   anywhere in this project. Phase scripts MUST call this function and override
%   only the fields relevant to their demonstration (e.g. a target list) — they
%   must never redefine fc, B, Tchirp_active, Fs, etc. locally. This is what makes
%   the "no duplicated magic numbers" requirement enforceable rather than aspirational.
%
%   Baseline values and rationale are recorded in docs/parameter_reference.md.
%   Once Phase 1 begins, these values are locked: a change is a new, dated entry
%   in docs/engineering_decisions.md, not a silent edit here.
%
%   See also: validate_params

    % ---------------------------------------------------------------
    % Physical constants
    % ---------------------------------------------------------------
    params.c = 299792458;              % speed of light [m/s]

    % ---------------------------------------------------------------
    % RF / waveform parameters
    % ---------------------------------------------------------------
    params.wave.fc              = 77e9;        % carrier frequency [Hz] (automotive/mmWave band)
    params.wave.B                = 1e9;         % sweep bandwidth [Hz]
    params.wave.Tchirp_active    = 40e-6;       % active linear-ramp duration [s] (NOT the repetition interval, see D2)
    params.wave.T_idle           = 20e-6;       % idle/retrace time between ramps [s]
    params.wave.T_CRI            = params.wave.Tchirp_active + params.wave.T_idle; % chirp repetition interval [s]
    params.wave.S                = params.wave.B / params.wave.Tchirp_active;      % chirp slope [Hz/s]
    params.wave.lambda           = params.c / params.wave.fc;                      % wavelength [m]

    % ---------------------------------------------------------------
    % ADC / fast-time sampling
    % ---------------------------------------------------------------
    params.adc.Fs          = 20e6;                                   % ADC sample rate on the dechirped beat signal [Hz]
    params.adc.Ns           = round(params.adc.Fs * params.wave.Tchirp_active); % samples per chirp (raw, no zero-padding)
    params.adc.Nfft_range   = 2^nextpow2(params.adc.Ns);              % range-FFT length (zero-padded for interpolation only)

    % Derived range limits (documented, not independently settable)
    params.derived.dR      = params.c / (2*params.wave.B);                                   % range resolution [m]
    params.derived.R_max   = params.adc.Fs * params.c / (4*params.wave.S);                    % max unambiguous range [m] (Nyquist on f_beat)

    % ---------------------------------------------------------------
    % Slow-time / Doppler
    % ---------------------------------------------------------------
    params.frame.Nchirps = 128;    % chirps per coherent processing frame

    % Derived Doppler limits
    params.derived.v_max = params.wave.lambda / (4*params.wave.T_CRI);                        % max unambiguous velocity [m/s]
    params.derived.dv    = params.wave.lambda / (2*params.frame.Nchirps*params.wave.T_CRI);   % Doppler (velocity) resolution [m/s]

    % ---------------------------------------------------------------
    % Array / angle
    % ---------------------------------------------------------------
    params.array.Nrx = 8;                          % receive elements (uniform linear array)
    params.array.d   = params.wave.lambda / 2;     % element spacing [m] (half-wavelength: no grating lobes)
    params.array.fov_deg = 60;                     % +/- angular field of view [deg]

    % ---------------------------------------------------------------
    % Detection (CA-CFAR)
    % ---------------------------------------------------------------
    params.cfar.Pfa               = 1e-4;  % design false-alarm probability
    params.cfar.range.Ntrain      = 8;     % training cells per side, range axis
    params.cfar.range.Nguard      = 2;     % guard cells per side, range axis
    params.cfar.doppler.Ntrain    = 4;     % training cells per side, Doppler axis
    params.cfar.doppler.Nguard    = 1;     % guard cells per side, Doppler axis

    % ---------------------------------------------------------------
    % Simulation / noise
    % ---------------------------------------------------------------
    params.sim.SNR_dB = 10;    % per-chirp, pre-FFT SNR at the beat-signal input (see D11 -- always state the stage!)
    params.sim.seed   = 42;    % fixed RNG seed for reproducibility

end
