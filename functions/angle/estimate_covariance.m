function R_hat = estimate_covariance(snapshots)
%ESTIMATE_COVARIANCE Spatial covariance estimate from an array snapshot ensemble.
%
%   R_hat = ESTIMATE_COVARIANCE(snapshots) computes the sample spatial covariance
%
%       R_hat = (1/M) * sum_m x_m * x_m^H
%
%   from `snapshots`, an M x Nrx matrix whose m-th ROW is the m-th Nrx-element
%   array snapshot x_m (M snapshots total -- in this project, one per chirp in a
%   coherent processing frame; see build_array_covariance.m / decision D7).
%
%   CONVENTION WARNING (decision D17): with snapshots organized as ROWS, the
%   formula above is produced by
%
%       R_hat = snapshots.' * conj(snapshots)
%
%   i.e. a plain transpose (no conjugation) contracted against an elementwise
%   conjugate -- NOT by `snapshots' * snapshots` (MATLAB's conjugate-transpose-
%   then-multiply, the natural-looking but WRONG translation of "R = X*X^H" when
%   X's snapshots are rows rather than columns). The two differ by a full
%   conjugate of the whole matrix; because R_hat must be Hermitian, that
%   conjugate equals R_hat^T, and for this project's ULA steering vector
%   a(theta) = exp(j*2*pi*d*n*sin(theta)/lambda), using the wrong one silently
%   mirrors every downstream MUSIC/conventional-beamforming angle estimate about
%   broadside (theta -> -theta) -- with NO effect on eigenvalue magnitudes, range,
%   or velocity, which is exactly why it went unnoticed until angle estimates
%   were checked against known non-zero ground truth.
%
%   This exact bug shipped in build_array_covariance.m throughout Phase 5 and
%   was only caught during Phase 6 development, when re-deriving the
%   covariance formula from first principles and comparing it symbol-by-symbol
%   against the code reproduced a consistent angle-sign flip that had gone
%   undetected in Phase 5. See docs/engineering_decisions.md decision D17 for
%   the full diagnosis.
%
%   This function is now the SINGLE implementation of the covariance formula,
%   called from both build_array_covariance.m (Phase 5) and
%   phase6_full_pipeline.m (Phase 6), specifically so the formula cannot
%   silently diverge between call sites again.
%
%   Inputs:
%       snapshots - M x Nrx complex matrix, snapshot m stored as row m
%   Outputs:
%       R_hat - Nrx x Nrx Hermitian spatial covariance estimate

    M = size(snapshots, 1);
    R_hat = (snapshots.' * conj(snapshots)) / M;

end
