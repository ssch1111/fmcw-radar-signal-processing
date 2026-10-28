function [R_hat, range_axis] = build_array_covariance(params, t, tx, R0, v_list, atten_list, theta_list)
%BUILD_ARRAY_COVARIANCE Synthesize a multi-target array snapshot ensemble and
%estimate its spatial covariance at a given range bin.
%
%   [R_hat, range_axis] = BUILD_ARRAY_COVARIANCE(params, t, tx, R0, v_list,
%   atten_list, theta_list) builds an Ns x Nchirps x Nrx cube for one or more
%   targets sharing range R0 (each with its own velocity, attenuation, and
%   angle), adds AWGN, range-FFTs each element, extracts the Nrx-element
%   snapshot at the range bin nearest R0 for every chirp, and estimates the
%   spatial covariance via decision D7's outer-product averaging:
%
%       R_hat = (1/Nchirps) * sum_m x_m * x_m^H
%
%   IMPORTANT (see docs/engineering_decisions.md decision D7): this estimator relies on each source's
%   per-chirp phase progression to decorrelate it from the others across the
%   Nchirps-snapshot ensemble. Two or more STATIONARY targets sharing a range
%   bin produce IDENTICAL per-chirp snapshots (no decorrelation), collapsing
%   what should be a multi-source covariance into an effectively rank-1
%   estimate -- confirmed the hard way during Phase 5 development. Callers
%   testing multiple co-range-bin sources MUST give them distinct velocities
%   (even small ones) for this estimator to work as intended; a single-source
%   scenario (v=0 is fine) is unaffected.
%
%   Inputs:
%       params      - struct from get_radar_params()
%       t           - 1 x Ns fast-time vector (from generate_chirp)
%       tx          - 1 x Ns transmit chirp (from generate_chirp)
%       R0          - nominal range of all targets in this scenario [m]
%       v_list      - 1 x K velocities [m/s], one per target
%       atten_list  - 1 x K attenuations, one per target
%       theta_list  - 1 x K angles [rad], one per target
%   Outputs:
%       R_hat      - Nrx x Nrx estimated spatial covariance
%       range_axis - range axis from the range FFT (for reference/plotting)

    Nrx = params.array.Nrx;
    d = params.array.d;
    lambda_ = params.wave.lambda;
    Nchirps = params.frame.Nchirps;

    beat_per_elem = zeros(params.adc.Ns, Nchirps, Nrx);
    for k = 1:numel(v_list)
        rx_cube = simulate_moving_target_echo(params, t, R0, v_list(k), atten_list(k));
        beat2d = dechirp_mix(tx, rx_cube);          % Ns x Nchirps, single "virtual element"
        a = steering_vector(theta_list(k), Nrx, d, lambda_);  % Nrx x 1
        for elem = 1:Nrx
            beat_per_elem(:,:,elem) = beat_per_elem(:,:,elem) + beat2d * a(elem);
        end
    end

    A0 = max(atten_list);   % SNR reference, consistent with Phase 2-4 convention
    for elem = 1:Nrx
        beat_per_elem(:,:,elem) = add_awgn(beat_per_elem(:,:,elem), params.sim.SNR_dB, A0^2);
    end

    snapshots = zeros(Nchirps, Nrx);
    for elem = 1:Nrx
        [rp, range_axis] = range_fft(beat_per_elem(:,:,elem), params);
        [~, r_idx] = min(abs(range_axis - R0));
        snapshots(:, elem) = rp(r_idx, :).';
    end

    % CORRECTED (decision D17): this used to compute R_hat = snapshots' * snapshots directly
    % (MATLAB conjugate-transpose-then-multiply), which -- because snapshots stores each
    % chirp's Nrx-element snapshot as a ROW, not a column -- is the full CONJUGATE of the
    % intended R_hat = (1/Nchirps)*sum_m x_m*x_m^H, and silently mirrored every downstream
    % MUSIC/DBF angle estimate about broadside. Now delegated to estimate_covariance.m, the
    % single shared implementation of the (corrected) formula -- see its header and
    % docs/engineering_decisions.md D17 for the full diagnosis.
    R_hat = estimate_covariance(snapshots);

end
