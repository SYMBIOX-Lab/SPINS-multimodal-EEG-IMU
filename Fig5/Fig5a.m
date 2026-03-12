% =========================================================================
% FIGURE 5A: SPINS VS NATUS EEG NEONATAL
% =========================================================================
% clear, close all, clc;

% Note: You can dynamically zoom into plots or set hard time limits.

% Define File Paths and Plotting Window/Timezone
edfFilePath = 'RightEeg_0001_new.edf';
csvFilePath = 'converted_sensor_data_patient5right.csv';

cropStartTimeStr = '2024-11-25 14:00:30';
cropEndTimeStr   = '2024-11-25 14:04:30';
targetTimezone = 'America/Chicago';

% Manual Time Shift Adjustment
manual_offset_seconds = -19.38;

% Filter Cutoff Frequency
% A lower number makes the plot smoother.
filter_cutoff_hz = 10; % Hz

% Load EEG EDF Data
try
    info = edfinfo(edfFilePath);
    originalChannelName = 'EEG Right-Ref';
    channelName = 'EEGRight_Ref';
    if isprop(info, 'VariableNames')
        channelLabels = info.VariableNames;
    else
        channelLabels = info.SignalLabels;
    end
    channelIndex = find(strcmp(channelLabels, originalChannelName));
    if isempty(channelIndex)
        channelIndex = find(strcmp(channelLabels, channelName));
    end
    if isempty(channelIndex)
        error('Could not find the channel index.');
    end
    if isprop(info, 'SampleRate')
        eeg_fs = info.SampleRate(channelIndex);
    elseif isprop(info, 'SignalFrequencies')
        eeg_fs = info.SignalFrequencies(channelIndex);
    else
        eeg_fs = info.NumSamples(channelIndex) / seconds(info.DataRecordDuration);
    end
    startTimeString = strcat(info.StartDate, {' '}, info.StartTime);
    eeg_start_time_naive = datetime(startTimeString, 'InputFormat', 'dd.MM.yy HH.mm.ss');
    eeg_start_time_local = eeg_start_time_naive;
    eeg_start_time_local.TimeZone = targetTimezone;
    all_data_edf = edfread(edfFilePath);
    signal_in_cells = all_data_edf.(channelName);
    eeg_signal = vertcat(signal_in_cells{:});
    eeg_signal = double(eeg_signal);
catch ME
    fprintf('Error loading EDF file: %s\n', ME.message);
    return;
end

% Load Sensor CSV Data
try
    csv_table = readtable(csvFilePath);
    sensor_timestamp_text = csv_table.timestamp;
    sensor_data = csv_table.value;
    sensor_time_vector_utc = datetime(sensor_timestamp_text, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSSSSS', 'TimeZone', 'UTC');
catch ME
    fprintf('Error loading CSV file: %s\n', ME.message);
    return;
end

% Create Full Time Vectors and Apply Offset

num_eeg_samples = length(eeg_signal);
eeg_time_vector_local = eeg_start_time_local + seconds((0:num_eeg_samples-1)' / eeg_fs);
eeg_time_vector_local = eeg_time_vector_local + seconds(manual_offset_seconds);
sensor_time_vector_local = sensor_time_vector_utc;
sensor_time_vector_local.TimeZone = targetTimezone;

% Crop Data and Display Sampling Rates
cropStartTime = datetime(cropStartTimeStr, 'TimeZone', targetTimezone);
cropEndTime   = datetime(cropEndTimeStr, 'TimeZone', targetTimezone);

% Crop EEG Data
eeg_crop_idx = (eeg_time_vector_local >= cropStartTime & eeg_time_vector_local <= cropEndTime);
eeg_time_cropped = eeg_time_vector_local(eeg_crop_idx);
eeg_signal_cropped = eeg_signal(eeg_crop_idx);

% Crop Sensor Data
sensor_crop_idx = (sensor_time_vector_local >= cropStartTime & sensor_time_vector_local <= cropEndTime);
sensor_time_cropped = sensor_time_vector_local(sensor_crop_idx);
sensor_data_cropped = sensor_data(sensor_crop_idx);

% Calculate and Display Sampling Rates
fprintf('--------------------------------------------------\n');
fprintf('Original EEG (Red Line) Sampling Rate: %.2f Hz\n', eeg_fs);

% Calculate sensor sampling rate from the timestamps
sensor_time_diffs = diff(datenum(sensor_time_cropped)) * 24 * 3600; % in seconds
sensor_fs_original = 1 / mean(sensor_time_diffs);
fprintf('Original Sensor (Blue Line) Sampling Rate: %.2f Hz\n', sensor_fs_original);
fprintf('--------------------------------------------------\n');

% Downsample Sensor Data to Match EEG Sampling Rate
fprintf('Downsampling sensor data to match EEG sampling rate...\n');

% Using resample function, it applies an anti-aliasing filter before resampling.
sensor_data_downsampled = resample(sensor_data_cropped, round(eeg_fs), round(sensor_fs_original));

% Create a new time vector for the downsampled sensor data
num_sensor_samples_new = length(sensor_data_downsampled);
sensor_time_downsampled = linspace(sensor_time_cropped(1), sensor_time_cropped(end), num_sensor_samples_new)';

% Apply low-pass filter to both signals
fprintf('Filtering signals with a %.1f Hz cutoff...\n', filter_cutoff_hz);
lpFilter = designfilt('lowpassiir', 'FilterOrder', 4, 'HalfPowerFrequency', filter_cutoff_hz, 'SampleRate', eeg_fs);
eeg_signal_filtered = filtfilt(lpFilter, eeg_signal_cropped);

% Now filter the *downsampled* sensor data
sensor_signal_filtered = filtfilt(lpFilter, sensor_data_downsampled);

% Prepare filtered data for plotting
% Invert the filtered sensor signal
sensor_signal_filtered = -sensor_signal_filtered;

% Center both filtered signals by removing their mean value (DC offset)
fprintf('Centering signals around zero...\n');
eeg_to_plot = eeg_signal_filtered - mean(eeg_signal_filtered);
sensor_to_plot = sensor_signal_filtered - mean(sensor_signal_filtered);

% Scale the centered Sensor Data to Match the centered EEG Data Range
fprintf('Scaling sensor data to match EEG range...\n');
eeg_min = min(eeg_to_plot);
eeg_max = max(eeg_to_plot);
sensor_min = min(sensor_to_plot);
sensor_max = max(sensor_to_plot);

% Rescale the sensor data to fit within the EEG's min/max range
sensor_scaled = (eeg_max - eeg_min) * (sensor_to_plot - sensor_min) / (sensor_max - sensor_min) + eeg_min;

% Apply Manual Vertical Shift
% Adding shifts to align both signals
sensor_scaled = sensor_scaled + 8 - 225 + 150 + 95; 

% Calculate Correlation Coefficient
fprintf('Calculating correlation...\n');

% We use interp1 instead of resample to bypass the size limits
eeg_for_corr = interp1(datenum(eeg_time_cropped), eeg_to_plot, datenum(sensor_time_downsampled), 'linear', 'extrap');
correlation_matrix = corrcoef(eeg_for_corr, sensor_scaled);
r_value = correlation_matrix(2,1);

% Plot with visible y-axis and correlation annotation
fprintf('Plotting data...\n');
figure('Name', 'Final Scaled Plot', 'Color', 'w', 'Position', [100, 100, 800, 600]); 
hold on;

% Plot the scaled and downsampled sensor data (BLUE LINE) FIRST
plot(sensor_time_downsampled, sensor_scaled, 'LineStyle', '-', 'Color', [0, 0, 1, 0.5], 'LineWidth', 1);

% Plot the EEG signal (RED LINE) SECOND (sitting on top, but at 0.25 transparency)
plot(eeg_time_cropped, eeg_to_plot, 'LineStyle', '-', 'Color', [1, 0, 0, 0.25], 'LineWidth', 1.5);

hold off;

% Final Formatting
ax = gca; % Get current axes
box off;  % Remove top and right plot borders

corr_text = sprintf('r = %.4f', r_value);
annotation('textbox', [0.15, 0.8, 0.1, 0.1], 'String', corr_text, 'EdgeColor', 'none', 'FontSize', 12);

ylabel('Filtered, Centered & Scaled Amplitude');
xlabel(['Time (', targetTimezone, ')']);

% Legend order restored
legend('Sensor Data (Downsampled & Scaled)', 'EEG Signal', 'Location', 'NorthWest', 'Box', 'off');

% Y-axis limtis
axis tight;
ylim([-200 400]); 
fprintf('\nPlot generated successfully.\n');