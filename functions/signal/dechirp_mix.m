function beat = dechirp_mix(tx, rx)
%DECHIRP_MIX Mix (stretch-process) the received echo against the transmit replica.
%
%   beat = DECHIRP_MIX(tx, rx) returns the beat signal formed by multiplying the
%   transmitted chirp replica (the local-oscillator reference) by the CONJUGATE of
%   the received echo:
%
%       beat = tx .* conj(rx)
%
%   This sign convention (fixed project-wide, see docs/engineering_decisions.md
%   decision D4 -- CORRECTED during Phase 1 verification, see the dated correction
%   note there) yields a positive beat frequency for a positive target delay/range,
%   consistent with f_beat = 2*R*S/c as used throughout this project. The
%   originally documented convention (rx .* conj(tx)) was verified numerically
%   during Phase 1 to give the correct MAGNITUDE but the WRONG SIGN of f_beat for
%   an up-chirp; it has been corrected here and the sign was re-verified against
%   the closed-form instantaneous frequency of the mixed signal before being
%   accepted (not merely against the FFT, which is insensitive to sign for a
%   real-only spectrum check).
%
%   Two calling shapes are supported (see docs/engineering_decisions.md decision
%   D18 -- a broadcasting bug found and fixed during Phase 3 integration):
%     1. Single chirp:  tx is 1 x Ns, rx is 1 x Ns (same shape) -- Phases 1-2.
%        beat = tx .* conj(rx), unchanged, elementwise, 1 x Ns output.
%     2. Chirp train:   tx is 1 x Ns, rx is a Ns x Nchirps cube (fast-time along
%        rows, one column per chirp) -- Phases 3+. The 1 x Ns transmit replica
%        is broadcast (as a column) against every chirp's column, giving an
%        Ns x Nchirps beat cube.
%   The branch is selected by shape, not by an explicit flag, so every existing
%   call site needs no change; only this function's internal broadcasting was
%   fixed.
%
%   Inputs:
%       tx   - 1 x Ns transmitted chirp (from generate_chirp)
%       rx   - EITHER a 1 x Ns received echo, same length/sample grid, as tx
%              (from simulate_target_echo, or a sum of several such echoes for
%              multiple targets at the same time instant) OR an Ns x Nchirps
%              chirp-train cube (from simulate_moving_target_echo).
%   Outputs:
%       beat - 1 x Ns (single-chirp case) or Ns x Nchirps (chirp-train case)
%              complex beat signal, matching rx's shape.

    if isvector(rx) && isequal(size(rx), size(tx))
        % Single chirp: tx and rx are matched-shape (1 x Ns) row vectors, exactly
        % the Phase 1/2 case -- unchanged elementwise multiply.
        beat = tx .* conj(rx);
    else
        % Chirp train: rx is Ns x Nchirps (fast-time along rows, decision D2/D6).
        % tx is broadcast as a column (Ns x 1) against every chirp's column.
        % NOTE: plain `tx .* conj(rx)` here would error ("incompatible sizes")
        % because tx's second dimension (Ns) does not match rx's second
        % dimension (Nchirps) -- this is exactly the bug that surfaced when
        % Phase 3 was first run (see decision D18).
        beat = tx(:) .* conj(rx);
    end

end
