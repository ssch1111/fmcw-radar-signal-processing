function [tx, t] = generate_chirp(params)
%GENERATE_CHIRP Generate one complex-baseband sawtooth linear FMCW chirp.
%
%   [tx, t] = GENERATE_CHIRP(params) returns the complex-baseband representation
%   of a single up-chirp of duration params.wave.Tchirp_active, sampled at
%   params.adc.Fs, with instantaneous frequency sweeping linearly from 0 to
%   params.wave.B (baseband equivalent of fc to fc+B).
%
%   Complex baseband (I/Q) is used throughout this project (see
%   docs/engineering_decisions.md, decision D3) so that Doppler sign is preserved
%   in later phases. The carrier fc itself is not simulated explicitly -- only its
%   effect on array steering (Phase 5+) and on beat-frequency scaling matters here;
%   representing the chirp at baseband is mathematically equivalent for a
%   dechirped/stretch-processing receiver and is the standard simulation shortcut.
%
%   Inputs:
%       params - struct from get_radar_params()
%   Outputs:
%       tx - 1 x Ns complex row vector, the transmitted chirp samples
%       t  - 1 x Ns row vector of sample times [s], t(1) = 0

    Fs = params.adc.Fs;
    Ns = params.adc.Ns;
    S  = params.wave.S;

    t = (0:Ns-1) / Fs;                 % fast-time sample instants [s]
    phase = pi * S * t.^2;             % instantaneous phase of a linear chirp: phi(t) = pi*S*t^2
                                        % (so that d(phase)/dt / (2*pi) = S*t, the linear sweep)
    tx = exp(1j * 2*pi*0 + 1j*phase);  % complex baseband chirp, unit amplitude

end
