function rx = simulate_target_echo(params, t, R, attenuation)
%SIMULATE_TARGET_ECHO Generate the received echo from a single point target.
%
%   rx = SIMULATE_TARGET_ECHO(params, t, R, attenuation) returns the complex
%   baseband received signal for a stationary point target at range R [m],
%   with a fixed linear amplitude attenuation factor `attenuation` (dimensionless,
%   applied to the field amplitude; see docs/engineering_decisions.md decision D10
%   for why a simplified reflectivity/attenuation scalar is used instead of a full
%   monostatic radar range equation at this stage of the project).
%
%   The round-trip delay tau = 2*R/c is applied analytically to the transmit
%   chirp's closed-form instantaneous phase, evaluated at (t - tau), rather than
%   by shifting the discrete transmit array by a rounded number of samples (see
%   decision D5). This avoids interpolation/quantization error in the delay itself,
%   so any beat-frequency error observed later is attributable only to FFT bin
%   quantization, not to delay-modeling error.
%
%   CARRIER ROUND-TRIP PHASE TERM (added during Phase 3 verification -- see the
%   dated correction note in docs/engineering_decisions.md): the returned echo includes the
%   factor exp(-j*2*pi*fc*tau) in addition to the baseband chirp phase term. This
%   term is what a real dechirp/stretch-processing receiver sees because the
%   transmitted and received signals differ by the delay tau AT THE CARRIER
%   frequency fc, not only in their baseband chirp envelope. It has NO EFFECT on
%   Phase 1/2 results (a magnitude-only peak search cannot see a per-chirp constant
%   phase factor), which is why its absence did not surface until Phase 3, where it
%   is in fact the DOMINANT source of the slow-time Doppler phase progression (fc is
%   ~4 orders of magnitude larger than the beat frequency, so a femtosecond-scale
%   per-chirp delay change from target motion still produces a significant carrier-
%   phase rotation across the frame). Without this term, a moving target produces
%   NO measurable Doppler shift at all -- confirmed the hard way during Phase 3's
%   first execution (see the report).
%
%   Inputs:
%       params      - struct from get_radar_params()
%       t           - 1 x Ns fast-time sample vector [s] (from generate_chirp)
%       R           - target range [m] (scalar, or 1 x Ns if range changes during
%                     the chirp -- not used in Phase 1/2, reserved for completeness)
%       attenuation - scalar linear amplitude attenuation factor (0 < attenuation <= 1)
%   Outputs:
%       rx - 1 x Ns complex row vector, the received echo aligned to the same
%            fast-time sample grid as the transmitted chirp

    c   = params.c;
    S   = params.wave.S;
    fc  = params.wave.fc;
    tau = 2*R/c;                        % round-trip delay [s]

    t_delayed = t - tau;                % evaluate the SAME chirp phase law at (t - tau)
    phase_chirp   = pi * S * (t_delayed).^2;     % analytic instantaneous phase of the delayed chirp
    phase_carrier = -2*pi*fc*tau;                % carrier round-trip phase (constant over one chirp,
                                                  % but varies chirp-to-chirp as R changes -- this is
                                                  % what carries the Doppler information; see note above)

    rx = attenuation * exp(1j*(phase_chirp + phase_carrier));

end
