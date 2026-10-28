function [detections, threshold] = ca_cfar_2d(power_map, Ntrain_r, Nguard_r, Ntrain_d, Nguard_d, Pfa)
%CA_CFAR_2D Cell-Averaging CFAR over a Range-Doppler power map.
%
%   [detections, threshold] = CA_CFAR_2D(power_map, Ntrain_r, Nguard_r, Ntrain_d,
%   Nguard_d, Pfa) applies 2-D CA-CFAR. Per decision D8:
%     - Range axis (dim 1): NON-PERIODIC -- shrinking/clipped window at edges.
%     - Doppler axis (dim 2): PERIODIC -- circular wraparound (matches the FFT's
%       own periodicity).
%
%   Implementation note: rather than a per-cell inner loop over the (small,
%   fixed) training-window offsets -- which would be equally correct but far
%   slower in MATLAB -- this loops over the offsets ONCE and accumulates
%   vectorized shifted copies of the whole map (circshift for the periodic
%   Doppler axis, with the range axis masked where a shift would wrap
%   incorrectly). This is a standard sliding-window-sum vectorization, not an
%   approximation: the accumulated sum/count at each cell equals exactly what
%   the naive per-cell loop would compute.
%
%   Inputs:
%       power_map - Nrange x Ndoppler power-domain Range-Doppler map
%       Ntrain_r, Nguard_r - training/guard cells per side, range axis
%       Ntrain_d, Nguard_d - training/guard cells per side, Doppler axis
%       Pfa                - design false-alarm probability
%   Outputs:
%       detections - Nrange x Ndoppler logical
%       threshold  - Nrange x Ndoppler

    [Nr, Nd] = size(power_map);
    sum_train = zeros(Nr, Nd);
    count_train = zeros(Nr, Nd);

    r_span = Nguard_r + Ntrain_r;
    d_span = Nguard_d + Ntrain_d;

    for ro = -r_span:r_span
        for do = -d_span:d_span
            if abs(ro) <= Nguard_r && abs(do) <= Nguard_d
                continue;   % inside guard+CUT region
            end
            shifted = circshift(power_map, [-ro, -do]);   % Doppler wrap is correct; range wrap must be masked
            valid = true(Nr, Nd);
            if ro > 0
                valid(Nr-ro+1:Nr, :) = false;   % source rows fell off the top edge (range, non-periodic)
            elseif ro < 0
                valid(1:-ro, :) = false;        % fell off the bottom edge
            end
            sum_train(valid) = sum_train(valid) + shifted(valid);
            count_train = count_train + valid;
        end
    end

    noise_level = zeros(Nr, Nd);
    alpha = zeros(Nr, Nd);
    has_train = count_train > 0;
    noise_level(has_train) = sum_train(has_train) ./ count_train(has_train);
    n = count_train(has_train);
    alpha(has_train) = n .* (Pfa.^(-1./n) - 1);

    threshold = alpha .* noise_level;
    detections = (power_map > threshold) & has_train;

end
