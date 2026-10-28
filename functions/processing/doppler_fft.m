function [rd_map, velocity_axis] = doppler_fft(range_profile_matrix, params)
%DOPPLER_FFT Slow-time FFT across chirps, converted to a velocity axis.
%
%   [rd_map, velocity_axis] = DOPPLER_FFT(range_profile_matrix, params) computes the
%   FFT along the chirp (slow-time) dimension of a range-FFT output matrix, shifts
%   it so zero-Doppler is centered, and converts the Doppler-frequency axis to
%   velocity via v = f_d * lambda / 2 (two-way factor already absorbed into the
%   f_d = 2*v/lambda relationship used to derive the carrier phase term in
%   simulate_target_echo.m).
%
%   Inputs:
%       range_profile_matrix - Nrange x Nchirps complex matrix (output of range_fft)
%       params                - struct from get_radar_params()
%   Outputs:
%       rd_map        - Nrange x Nchirps complex Range-Doppler map (fftshift applied
%                       along the Doppler dimension)
%       velocity_axis - 1 x Nchirps vector of velocities [m/s], centered at 0

    Nchirps = params.frame.Nchirps;
    T_CRI = params.wave.T_CRI;
    lambda_ = params.wave.lambda;

    X = fft(range_profile_matrix, Nchirps, 2);
    rd_map = fftshift(X, 2);

    freq_axis = ((0:Nchirps-1) - floor(Nchirps/2)) * (1/(Nchirps*T_CRI));
    velocity_axis = freq_axis * lambda_ / 2;

end
