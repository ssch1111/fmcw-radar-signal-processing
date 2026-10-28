function [P, eigvals] = music_spectrum(R_hat, Nsources, theta_grid, Nrx, d, lambda_)
%MUSIC_SPECTRUM MUSIC pseudo-spectrum from an estimated spatial covariance matrix.
%
%   [P, eigvals] = MUSIC_SPECTRUM(R_hat, Nsources, theta_grid, Nrx, d, lambda_)
%   eigen-decomposes R_hat (Nrx x Nrx), separates the noise subspace (the
%   Nrx-Nsources eigenvectors with the SMALLEST eigenvalues), and evaluates
%
%       P(theta) = 1 / (a(theta)^H * En * En^H * a(theta))
%
%   over the candidate angle grid `theta_grid` [rad].
%
%   Inputs:
%       R_hat      - Nrx x Nrx estimated spatial covariance (see
%                    build_array_covariance.m for how it is formed -- decision D7)
%       Nsources   - assumed number of signal sources (known a priori in this
%                    project's test scenarios; automatic source-count estimation,
%                    e.g. via an eigenvalue-gap/AIC/MDL test, is out of scope)
%       theta_grid - 1 x M candidate angles [rad]
%       Nrx, d, lambda_ - array geometry (see steering_vector.m)
%   Outputs:
%       P       - 1 x M MUSIC pseudo-spectrum (not normalized)
%       eigvals - Nrx x 1 eigenvalues of R_hat, DESCENDING order (returned for
%                 diagnostic inspection -- e.g. confirming Nsources dominant
%                 eigenvalues are actually present before trusting the result)

    [V, D] = eig(R_hat);
    eigvals_all = diag(D);
    [eigvals, order] = sort(eigvals_all, 'descend');
    V = V(:, order);

    En = V(:, Nsources+1:end);   % noise subspace

    M = numel(theta_grid);
    P = zeros(1, M);
    for i = 1:M
        a = steering_vector(theta_grid(i), Nrx, d, lambda_);
        denom = abs(a' * (En*En') * a);
        P(i) = 1 / max(denom, 1e-12);
    end

end
