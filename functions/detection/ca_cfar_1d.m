function [detections, threshold] = ca_cfar_1d(power_profile, Ntrain, Nguard, Pfa)
%CA_CFAR_1D Cell-Averaging CFAR along a single (non-periodic) axis.
%
%   [detections, threshold] = CA_CFAR_1D(power_profile, Ntrain, Nguard, Pfa)
%   applies CA-CFAR to a power-domain (|X|^2) 1-D profile. The axis is treated as
%   NON-PERIODIC (e.g. range): near the edges, the training window SHRINKS rather
%   than wrapping around (decision D8) -- the threshold formula's Ntrain is
%   adjusted to the actual number of training cells available at each position.
%
%   Threshold: alpha = n*(Pfa^(-1/n) - 1), the standard CA-CFAR scaling for a
%   square-law (power-domain) detector under an exponential noise model, where n
%   is the ACTUAL number of training cells used at that position (n <= 2*Ntrain).
%
%   Inputs:
%       power_profile - 1 x N (or N x 1) power-domain profile
%       Ntrain        - training cells PER SIDE
%       Nguard        - guard cells PER SIDE
%       Pfa           - design false-alarm probability
%   Outputs:
%       detections - logical, same size as power_profile
%       threshold  - same size as power_profile

    power_profile = power_profile(:);
    N = numel(power_profile);
    threshold = zeros(N,1);
    detections = false(N,1);

    for i = 1:N
        lo = max(1, i-Nguard-Ntrain);
        hi = min(N, i+Nguard+Ntrain);
        idx = lo:hi;
        train_idx = idx(abs(idx-i) > Nguard);
        n = numel(train_idx);
        if n == 0
            continue;
        end
        noise_level = mean(power_profile(train_idx));
        alpha = n*(Pfa^(-1/n) - 1);
        threshold(i) = alpha*noise_level;
        detections(i) = power_profile(i) > threshold(i);
    end

end
