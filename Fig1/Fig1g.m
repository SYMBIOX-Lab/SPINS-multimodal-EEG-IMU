% =========================================================================
% FIGURE 1G: THREE CHANNEL NEONATAL DATA
% =========================================================================

% Define the three channels
file1 = '/neonatal/p004/aEEG_68.csv';
file2 = '/neonatal/p004/aEEG_69.csv';
file3 = '/neonatal/p004/aEEG_70.csv';

% The names of the columns as they appear on the headers
timeCol = 'timestamp';
valueCol = 'value';

% Load data using readtable() function
opts = detectImportOptions(file1);
table1 = readtable(file1, opts);
table2 = readtable(file2, opts);
table3 = readtable(file3, opts);

% Extract data and convert timezone. Local timezone is America/Chicago
time1 = table1.(timeCol);
time1.TimeZone = 'local'; 
value1 = table1.(valueCol);

time2 = table2.(timeCol);
time2.TimeZone = 'local';
value2 = table2.(valueCol);

time3 = table3.(timeCol);
time3.TimeZone = 'local';
value3 = table3.(valueCol);

% Plotting Parameters
figure('Color', 'white');
t = tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% Defining custom color matrix directly
colors = [0.7 0.4 0.4;  % Muted red
          0.4 0.7 0.4;  % Muted green
          0.4 0.4 0.7]; % Muted blue

% Plot 1 (Top)
ax1 = nexttile; 
plot(time1, value1, 'Color', colors(1,:)); 
box(ax1, 'off');
ax1.TickDir = 'out'; 
ax1.YAxis.Color = 'none'; 
ax1.XAxis.Color = 'none'; 

% Plot 2 (Middle)
ax2 = nexttile; 
plot(time2, value2, 'Color', colors(2,:));
box(ax2, 'off');
ax2.TickDir = 'out';
ax2.YAxis.Color = 'none'; 
ax2.XAxis.Color = 'none';

% Plot 3 (Bottom)
ax3 = nexttile;
plot(time3, value3, 'Color', colors(3,:)); 
box(ax3, 'off');
ax3.TickDir = 'out';
ax3.YAxis.Color = 'none';
xlabel('Time (Local)');

% Link axes and set x axis limit.
linkaxes([ax1, ax2, ax3], 'x');

% Defining start and end times
d = time1(1); 
startTime = datetime(d.Year, d.Month, d.Day, 15, 1, 0, 'TimeZone', 'local');
endTime = datetime(d.Year, d.Month, d.Day, 15, 8, 0, 'TimeZone', 'local');

% Set the limits (this affects all linked axes)
xlim(ax1, [startTime, endTime]);

disp('Plotting complete with requested time window.');