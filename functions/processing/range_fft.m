function [range_profile, range_axis] = range_fft(beat, params)
%RANGE_FFT Convert a fast-time beat signal into a range profile.
%
%   [range_profile, range_axis] = RANGE_FFT(beat, params) computes the FFT of the
%   (possibly zero-padded) beat signal along the fast-time dimension and converts
%   the frequency axis to a range axis via R = f*c/(2*S) (docs/architecture.md §3).
%
%   Only the first half of the FFT is returned: by the fixed dechirp convention
%   (decision D4), beat frequencies for real (positive-range) targets are positive,
%   so the range axis is one-sided (0 .. R_max) and the negative-frequency half of
%   the FFT carries no additional information for this signal model.
%
%   Inputs:
%       beat   - Ns x 1, 1 x Ns, or Ns x Nchirps matrix (fast-time along dim 1 if 2-D
%                with more than one row matching Ns... callers should pass fast-time
%                along the FIRST dimension for 2-D input, per the axis convention in
%                docs/architecture.md §5)
%       params - struct from get_radar_params()
%   Outputs:
%       range_profile - Nfft/2 x Nchirps (or Nfft/2 x 1) complex range-FFT output
%       range_axis    - 1 x Nfft/2 vector of range values [m]

    if isrow(beat)
        beat = beat(:);   % force fast-time along dim 1
    end

    Nfft = params.adc.Nfft_range;
    Fs   = params.adc.Fs;
    S    = params.wave.S;
    c    = params.c;

    X = fft(beat, Nfft, 1);
    half = 1:floor(Nfft/2);
    range_profile = X(half, :);

    freq_axis = (half-1) * (Fs/Nfft);
    range_axis = freq_axis * c / (2*S);

end
