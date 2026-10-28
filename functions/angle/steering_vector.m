function a = steering_vector(theta, Nrx, d, lambda_)
%STEERING_VECTOR Uniform linear array (ULA) manifold vector.
%
%   a = STEERING_VECTOR(theta, Nrx, d, lambda_) returns the Nrx x 1 complex array
%   manifold vector for a plane wave arriving at angle `theta` (radians, measured
%   from broadside; positive = toward increasing element index), with element
%   spacing `d` [m] and wavelength `lambda_` [m]:
%
%       a_n = exp(j*2*pi*d*n*sin(theta)/lambda), n = 0..Nrx-1
%
%   NARROWBAND ASSUMPTION: this phase is evaluated at the CARRIER wavelength
%   (not at the instantaneous chirp frequency or beat frequency), which is valid
%   because array combining happens on the already-dechirped signal and because
%   the sweep bandwidth B is negligible compared to fc (no beam squint) -- see
%   docs/architecture.md §3.
%
%   This EXACT function is used both to (a) synthesize the per-element phase
%   applied to a simulated echo, and (b) scan candidate angles in MUSIC/DBF. Using
%   the same function for both keeps the sign/scaling convention self-consistent
%   by construction.
%
%   Inputs:
%       theta   - angle [rad], scalar
%       Nrx     - number of array elements
%       d       - element spacing [m]
%       lambda_ - carrier wavelength [m]
%   Outputs:
%       a - Nrx x 1 complex steering vector

    n = (0:Nrx-1).';
    a = exp(1j*2*pi*d*n*sin(theta)/lambda_);

end
