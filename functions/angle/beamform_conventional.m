function P = beamform_conventional(R_hat, theta_grid, Nrx, d, lambda_)
%BEAMFORM_CONVENTIONAL Conventional (Bartlett) digital beamforming spectrum.
%
%   P = BEAMFORM_CONVENTIONAL(R_hat, theta_grid, Nrx, d, lambda_) evaluates the
%   classic Bartlett beamformer response P(theta) = a(theta)^H * R_hat * a(theta)
%   over the candidate angle grid, using the SAME array covariance estimate and
%   the SAME steering_vector.m used by music_spectrum.m, so the comparison
%   between the two methods is apples-to-apples.
%
%   Inputs:
%       R_hat      - Nrx x Nrx estimated spatial covariance
%       theta_grid - 1 x M candidate angles [rad]
%       Nrx, d, lambda_ - array geometry
%   Outputs:
%       P - 1 x M beamformer power spectrum (not normalized)

    M = numel(theta_grid);
    P = zeros(1, M);
    for i = 1:M
        a = steering_vector(theta_grid(i), Nrx, d, lambda_);
        P(i) = real(a' * R_hat * a);
    end

end
