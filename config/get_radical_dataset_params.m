function rparams = get_radical_dataset_params()
%GET_RADICAL_DATASET_PARAMS Radar hardware/timing parameters for the RaDICaL
%dataset's "indoor" recording configuration (Phase 7 real-data validation).
%
%   rparams = GET_RADICAL_DATASET_PARAMS() returns a struct with the SAME field
%   names/structure as config/get_radar_params.m (params.c, params.wave.*,
%   params.adc.*, params.frame.*, params.derived.*), so that this project's
%   existing, already-verified processing functions (range_fft.m, doppler_fft.m,
%   ca_cfar_2d.m, ...) can be reused UNMODIFIED on real RaDICaL data -- see
%   src/phase7_dataset_validation.m. This is a DELIBERATE, DOCUMENTED departure
%   from "always call get_radar_params()" (which governs the SYNTHETIC Phases
%   1-6 scenario): Phase 7 validates against different, real hardware with its
%   own fixed timing, so a second, real-hardware parameter struct is the
%   correct design, not a violation of the "single source of truth" rule
%   (that rule is about not scattering magic numbers ad hoc, not about forcing
%   two different radars to share one config).
%
%   SOURCE OF THESE NUMBERS (primary source, not assumed):
%   RaDICaL dataset SDK documentation, "radar.config_v1" example page,
%   https://moodoki.github.io/radical_sdk/radarcfg_v1.html (accessed during
%   Phase 7 dataset research, 2026-09). This documents the actual TI mmWave
%   radar configuration file (`indoor_human_rcs.cfg`-class configuration) used
%   for the dataset's "indoor" recordings, including the 50-frame official
%   sample used by this project (see docs/dataset_notes.md).
%
%   VALUES TAKEN VERBATIM FROM THE DOCUMENTED CONFIG (not re-derived/guessed):
%       start_frequency   = 77e9        Hz   (77 GHz carrier)
%       freqSlopeConst    = 1e14        Hz/s (100 MHz/us chirp slope)
%       adcSampleRate     = 9.499e6     Hz
%       adcSamples        = 304              (samples per chirp)
%       idle              = 5.8e-5      s
%       rampEndTime       = 3.9999999999999996e-5 s (~40 us, i.e. 40e-6 s)
%       txStartTime       = 1e-6        s
%       numTx             = 2
%       numRx (enabled)   = 4                (rx1-rx4)
%       numChirps         = 64                (chirps per frame)
%       fps               = 30.00030000300003
%
%   UNVERIFIED / TO CONFIRM AT RUN TIME (deliberately not hardcoded as fact):
%   whether the raw 'adc' HDF5 stream's "antenna" axis already reflects a
%   TX-multiplexed virtual array (up to numTx*numRx = 8 virtual elements) or
%   only the numRx = 4 physical receive channels. src/phase7_dataset_validation.m
%   determines this from the ACTUAL array shape returned by the file at run
%   time (via size()), rather than assuming either answer here, and prints
%   what it found so this is checked, not assumed, every run.
%
%   See also: get_radar_params (the synthetic Phases 1-6 parameter set)

    rparams.c = 299792458;  % speed of light [m/s] -- same physical constant, not dataset-specific

    % ---------------------------------------------------------------
    % RF / waveform parameters (RaDICaL "indoor" config, see header)
    % ---------------------------------------------------------------
    rparams.wave.fc              = 77e9;                 % carrier frequency [Hz]
    rparams.wave.S                = 1e14;                 % chirp slope [Hz/s] (freqSlopeConst)
    rparams.wave.Tchirp_active    = 3.9999999999999996e-5; % ramp end time [s] (~40 us)
    rparams.wave.T_idle           = 5.8e-5;               % idle time [s]
    rparams.wave.T_CRI            = rparams.wave.Tchirp_active + rparams.wave.T_idle; % chirp repetition interval [s]
    rparams.wave.B                = rparams.wave.S * rparams.wave.Tchirp_active;      % swept bandwidth [Hz] (derived, not separately documented)
    rparams.wave.lambda           = rparams.c / rparams.wave.fc;                      % wavelength [m]

    % ---------------------------------------------------------------
    % ADC / fast-time sampling
    % ---------------------------------------------------------------
    rparams.adc.Fs         = 9.499e6;                                  % ADC sample rate [Hz]
    rparams.adc.Ns          = 304;                                     % samples per chirp (documented, not derived)
    rparams.adc.Nfft_range  = 2^nextpow2(rparams.adc.Ns);              % range-FFT length (zero-padded)

    rparams.derived.dR      = rparams.c / (2*rparams.wave.B);                                  % range resolution [m]
    rparams.derived.R_max   = rparams.adc.Fs * rparams.c / (4*rparams.wave.S);                  % max unambiguous range [m]

    % ---------------------------------------------------------------
    % Slow-time / Doppler
    % ---------------------------------------------------------------
    rparams.frame.Nchirps = 64;    % chirps per frame, per the generic radar.config_v1 doc page.
                                    % DECISION D21 (docs/engineering_decisions.md): this sample's
                                    % (indoor_sample_50.h5) ACTUAL per-frame chirp count, confirmed
                                    % by inspecting the real file, is 32, not 64 -- that page most
                                    % likely documents a different RaDICaL recording configuration.
                                    % src/phase7_dataset_validation.m detects this at run time and
                                    % overrides this default with the value it actually finds in
                                    % the file; this default is kept as the last-resort documented
                                    % value for any code path that cannot inspect the file first.

    rparams.derived.v_max = rparams.wave.lambda / (4*rparams.wave.T_CRI);                       % max unambiguous velocity [m/s]
    rparams.derived.dv    = rparams.wave.lambda / (2*rparams.frame.Nchirps*rparams.wave.T_CRI);  % velocity resolution [m/s]

    % ---------------------------------------------------------------
    % Array (numTx=2, numRx=4 documented; ACTUAL usable array size is
    % determined at run time from the file itself -- see
    % src/phase7_dataset_validation.m -- these are the documented HARDWARE
    % counts, not necessarily the array size the raw 'adc' stream exposes)
    % ---------------------------------------------------------------
    rparams.array.numTx_documented = 2;
    rparams.array.numRx_documented = 4;
    rparams.array.d = rparams.wave.lambda / 2;   % assumed half-wavelength RX spacing (TI mmWave-cascade-class
                                                  % convention; NOT independently confirmed for this specific
                                                  % antenna board layout -- see docs/dataset_notes.md caveat)

    % ---------------------------------------------------------------
    % Metadata (for reporting / reproducibility, not used in the maths)
    % ---------------------------------------------------------------
    rparams.meta.fps = 30.00030000300003;
    rparams.meta.source = 'RaDICaL dataset, "indoor" recording configuration';
    rparams.meta.source_url = 'https://moodoki.github.io/radical_sdk/radarcfg_v1.html';

end
