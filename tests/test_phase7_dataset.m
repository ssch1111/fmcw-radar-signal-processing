%% TEST -- Phase 7 real-data validation
%
% This test is CONDITIONAL on the RaDICaL sample data file being present
% locally (it is not committed to Git -- see .gitignore and
% docs/dataset_notes.md). If the file is absent, the test SKIPS with a clear
% message rather than failing or fabricating a pass -- consistent with this
% project's "do not pretend a phase passed when it did not" rule.

addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

data_path = fullfile(fileparts(mfilename('fullpath')), '..', 'data', 'radical', 'indoor_sample_50.h5');

if ~isfile(data_path)
    fprintf(['test_phase7_dataset: SKIPPED -- RaDICaL sample data file not found at %s.\n' ...
        'See docs/dataset_notes.md for the download link and licence. This is not a failure:\n' ...
        'the data file is intentionally not committed to this repository.\n'], data_path);
    return;
end

rparams = get_radical_dataset_params();

% Basic parameter self-consistency (does not require the data file, but is
% only exercised here since the whole test is otherwise a no-op without it)
assert(rparams.wave.T_CRI > rparams.wave.Tchirp_active, ...
    'Phase 7 FAIL: chirp repetition interval must exceed the active ramp duration');
assert(rparams.derived.R_max > 0 && rparams.derived.v_max > 0, ...
    'Phase 7 FAIL: derived range/velocity limits must be positive');
assert(rparams.adc.Fs / 2 > 0, 'Phase 7 FAIL: Nyquist check placeholder');

info = h5info(data_path);
assert(any(strcmp({info.Datasets.Name}, 'adc')), ...
    'Phase 7 FAIL: expected an ''adc'' (raw ADC) stream in the HDF5 file, found: %s', ...
    strjoin({info.Datasets.Name}, ', '));

fprintf('test_phase7_dataset: PASS (data file present, ''adc'' stream confirmed, parameters self-consistent)\n');
fprintf('Run src/phase7_dataset_validation.m for the full range/Doppler/CFAR validation against this data.\n');
