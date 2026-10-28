function y = add_awgn(x, snr_db, ref_power)
%ADD_AWGN Add complex circular AWGN at a stated SNR, relative to a stated reference power.
%
%   y = ADD_AWGN(x, snr_db, ref_power) adds zero-mean complex Gaussian noise to x such
%   that E[|noise|^2] = ref_power / 10^(snr_db/10), split equally between the I and Q
%   components. `ref_power` is deliberately an explicit input, not derived from x itself:
%   per docs/engineering_decisions.md decision D11, "SNR" must always be stated relative to
%   a NAMED reference (here, a caller-chosen reference target/amplitude), never silently
%   redefined relative to whatever signal happens to be passed in -- otherwise the noise
%   floor would (unphysically) track each target's own amplitude instead of being a fixed
%   receiver property.
%
%   Hand-rolled rather than MATLAB's `awgn` (Communications Toolbox) to avoid an
%   unnecessary toolbox dependency (decision D12).
%
%   Inputs:
%       x         - input signal (any shape)
%       snr_db    - desired SNR in dB, defined as ref_power / noise_power
%       ref_power - reference signal power used to define the SNR (linear units)
%   Outputs:
%       y - x + complex AWGN

    noise_power = ref_power / (10^(snr_db/10));
    sigma = sqrt(noise_power/2);   % split equally between I and Q
    noise = sigma*(randn(size(x)) + 1j*randn(size(x)));
    y = x + noise;

end
