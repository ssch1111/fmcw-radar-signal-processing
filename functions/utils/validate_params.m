function validate_params(params, test_targets)
%VALIDATE_PARAMS Cross-phase invariant checks (see docs/parameter_reference.md #7).
%
%   VALIDATE_PARAMS(params) checks internal parameter consistency.
%   VALIDATE_PARAMS(params, test_targets) additionally checks that every target in
%   test_targets (a struct array with fields .range and, optionally, .velocity) is
%   within the valid unambiguous range/velocity limits for the configured params.
%
%   Every phase script calls this before generating any signal, so that a later
%   parameter tweak cannot silently violate an assumption another phase relies on.

    tol = 1e-9;

    % 1. T_CRI must exceed the active ramp duration (decision D2)
    assert(params.wave.T_CRI > params.wave.Tchirp_active, ...
        'validate_params:T_CRI', 'T_CRI must be greater than Tchirp_active.');

    % 3. Array spacing must not exceed half a wavelength (grating-lobe-free), small tolerance
    if isfield(params, 'array')
        assert(params.array.d <= params.wave.lambda/2 * (1+1e-3), ...
            'validate_params:spacing', 'Array spacing exceeds lambda/2; grating lobes possible.');
    end

    % 4. Ns must match the actual configured Fs*Tchirp_active (catches config drift)
    Ns_expected = round(params.adc.Fs * params.wave.Tchirp_active);
    assert(params.adc.Ns == Ns_expected, ...
        'validate_params:Ns', 'params.adc.Ns does not match round(Fs*Tchirp_active).');

    % 7. Range FFT length must not truncate the raw samples
    assert(params.adc.Nfft_range >= params.adc.Ns, ...
        'validate_params:Nfft', 'Nfft_range must be >= Ns (zero-padding only, never truncation).');

    if nargin > 1 && ~isempty(test_targets)
        for k = 1:numel(test_targets)
            R = test_targets(k).range;
            % 6. Range must be within the unambiguous range limit
            assert(R < params.derived.R_max, ...
                'validate_params:Rmax', ...
                sprintf('Target %d range %.2f m exceeds R_max = %.2f m.', k, R, params.derived.R_max));
            % 2. Nyquist check on beat frequency for this target range
            f_beat = 2*R*params.wave.S/params.c;
            assert(params.adc.Fs >= 2*f_beat - tol, ...
                'validate_params:Nyquist', ...
                sprintf('Target %d beat frequency %.3e Hz violates Nyquist at Fs=%.3e Hz.', k, f_beat, params.adc.Fs));
            % 5. Velocity ambiguity guard (only checked if a velocity field is present)
            if isfield(test_targets, 'velocity') && ~isempty(test_targets(k).velocity)
                v = test_targets(k).velocity;
                assert(abs(v) < params.derived.v_max, ...
                    'validate_params:vmax', ...
                    sprintf('Target %d velocity %.2f m/s exceeds v_max = %.2f m/s.', k, v, params.derived.v_max));
            end
        end
    end

end
