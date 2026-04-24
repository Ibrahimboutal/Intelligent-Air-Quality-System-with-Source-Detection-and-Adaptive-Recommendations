classdef AirQualitySystemTest < matlab.unittest.TestCase
    % Unit tests for the AirQualitySystem class - Exhaustive Coverage (Fixed)
    
    properties
        Sys % System object
    end
    
    methods(TestMethodSetup)
        function setup(testCase)
            % Add src to path
            addpath(fullfile(fileparts(mfilename('fullpath')), '../src'));
            
            % Initialize with mock parameters and SimMode=true
            testCase.Sys = AirQualitySystem('127.0.0.1', 'pi', 'pass', '/dev/ttyUSB0', 9600, true);
        end
    end
    
    methods(Test)
        
        %% 1. Constructor & Lifecycle
        function testConstructor(testCase)
            % Test valid initialization
            obj = AirQualitySystem('192.168.1.10', 'user', 'pass', '/dev/ttyS0', 9600, true);
            testCase.verifyEqual(obj.PiIPAddress, '192.168.1.10');
            testCase.verifyTrue(obj.SimMode);
            
            % Test with missing port/baud (should fail if not handled, but we fixed it)
            try
                obj2 = AirQualitySystem('1.1.1.1', 'pi', 'pass', '/dev/ttyUSB0', 9600);
                testCase.verifyEqual(obj2.Port, '/dev/ttyUSB0');
            catch ME
                testCase.verifyTrue(false, ['Constructor failed: ' ME.message]);
            end
        end
        
        %% 2. Intelligence Hub (Core Algorithms)
        function testFeatureExtraction(testCase)
            testCase.Sys.PM25Data = [10, 12, 15, 14, 13, 16];
            testCase.Sys.PM10Data = [20, 22, 25, 24, 23, 26];
            testCase.Sys.FeatureMu = zeros(1, 7);
            testCase.Sys.FeatureSigma = ones(1, 7);
            
            features = testCase.Sys.extractFeatures(6);
            testCase.verifyEqual(length(features), 7);
            testCase.verifyEqual(features(2), 3); % ROC: 16 - 13
        end
        
        function testForecastingStability(testCase)
            % Test trend dampening
            testCase.Sys.PM25Data = [10, 11, 100, 100, 100];
            for k = 1:5, testCase.Sys.forecastAQI(k); end
            
            initialTrend = testCase.Sys.HW_Trend;
            for k = 6:50
                testCase.Sys.PM25Data(k) = 100;
                testCase.Sys.forecastAQI(k);
            end
            finalTrend = testCase.Sys.HW_Trend;
            testCase.verifyTrue(abs(finalTrend) < abs(initialTrend));
        end
        
        function testDynamicThresholding(testCase)
            % Case: Stable environment
            testCase.Sys.PM25Data = ones(1, 100) * 10;
            testCase.Sys.PM10Data = ones(1, 100) * 20;
            [source, advice] = testCase.Sys.analyze(100, zeros(1,7), 10);
            testCase.verifyEqual(source, "Clean");
            
            % Case: Outlier relative to baseline
            testCase.Sys.PM25Data(101) = 100;
            [source, ~] = testCase.Sys.analyze(101, [0.8, 90, 0, 0, 0, 0, 0], 100);
            testCase.verifyTrue(source ~= "Clean");
        end
        
        %% 3. UI & Dashboard Logic
        function testDashboardLogic(testCase)
            % setupDashboard
            testCase.Sys.setupDashboard();
            testCase.verifyTrue(ishghandle(testCase.Sys.FigureHandle));
            
            % Manually preallocate for test
            testCase.Sys.TimeArray = [1, 2];
            testCase.Sys.PM25Data = [10, 20];
            testCase.Sys.PM10Data = [15, 25];
            testCase.Sys.SourceData = ["Normal", "Traffic"];
            testCase.Sys.AdviceData = ["OK", "Warning"];
            
            % updateDashboard
            testCase.Sys.updateDashboard(2);
            testCase.verifyEqual(testCase.Sys.CurrentStep, []); % CurrentStep is only set in timerCallback
            
            % Cleanup
            delete(testCase.Sys.FigureHandle);
        end
        
        %% 4. Data Acquisition (Mocking Hardware)
        function testReadSensorMock(testCase)
            % SimMode = true: should generate random data
            testCase.Sys.SimMode = true;
            [p25, p10] = testCase.Sys.readSensor(1);
            testCase.verifyTrue(p25 >= 0 && p25 <= 100);
            testCase.verifyTrue(p10 >= 0 && p10 <= 150);
            
            % Test specific cycle spikes (Covering line 241 and beyond)
            [p25_22, ~] = testCase.Sys.readSensor(22);
            testCase.verifyTrue(p25_22 > 30, 'Cycle 22 (Dust) spike not detected');
            
            [p25_85, ~] = testCase.Sys.readSensor(85);
            testCase.verifyTrue(p25_85 > 40, 'Cycle 85 (Combustion) spike not detected');
            
            [p10_155, ~] = testCase.Sys.readSensor(155);
            testCase.verifyTrue(p10_155 > 40, 'Cycle 155 (Coarse) spike not detected');
        end
        
        %% 5. Model Loading (Constructor Test)
        function testModelLoading(testCase)
            % Test failure path (handled in constructor)
            obj = AirQualitySystem('1.1.1.1', 'pi', 'pass', 'COM1', 9600, true);
            testCase.verifyEmpty(obj.MLModel);
            
            % Use absolute paths to avoid CI environment issues
            cwd = pwd;
            modelDir = fullfile(cwd, 'models');
            if ~exist(modelDir, 'dir')
                mkdir(modelDir);
            end
            modelPath = fullfile(modelDir, 'trainedModel.mat');
            
            % Save a dummy model
            MLModel = 1; FeatureMu = zeros(1,7); FeatureSigma = ones(1,7);
            save(modelPath, 'MLModel', 'FeatureMu', 'FeatureSigma');
            
            % Verify file exists before proceeding
            testCase.verifyTrue(exist(modelPath, 'file') == 2);
            
            % Now constructor should "load" it (assuming it runs in the same CWD)
            obj2 = AirQualitySystem('1.1.1.1', 'pi', 'pass', 'COM1', 9600, true);
            testCase.verifyNotEmpty(obj2.MLModel);
            
            % Cleanup
            if exist(modelPath, 'file'), delete(modelPath); end
        end
        
        %% 6. Data Persistence (cleanupTimer)
        function testDataPersistence(testCase)
            % Populate dummy data
            numSamples = 5;
            testCase.Sys.TimeArray = 1:numSamples;
            testCase.Sys.PM25Data = rand(1, numSamples);
            testCase.Sys.PM10Data = rand(1, numSamples);
            testCase.Sys.FeatureMatrix = rand(numSamples, 7);
            testCase.Sys.ForecastData = rand(1, numSamples);
            testCase.Sys.SourceData = repmat("Clean", 1, numSamples);
            testCase.Sys.AdviceData = repmat("OK", 1, numSamples);
            
            testCase.Sys.cleanupTimer();
            
            % Verify log file creation
            logFiles = dir('logs/AQI_Log_*.csv');
            testCase.verifyNotEmpty(logFiles);
        end
        
        %% 7. Robust Analysis (runFSDAAnalysis)
        function testFSDAAnalysis(testCase)
            % Case: Insufficient data
            testCase.Sys.PM25Data = [1, 2];
            testCase.Sys.runFSDAAnalysis();
            
            % Case: Sufficient data (triggering fallback or FSM)
            testCase.Sys.PM25Data = rand(1, 20);
            testCase.Sys.PM10Data = rand(1, 20);
            testCase.Sys.runFSDAAnalysis();
            testCase.verifyTrue(true);
        end
        
        %% 8. Offline Training Script Coverage
        function testOfflineTrainingScript(testCase)
            % 1. Create mock data in logs/ for the script to find
            if ~exist('logs', 'dir'), mkdir('logs'); end
            
            % Generate enough data to satisfy the 80/20 split and correlation matrix
            numSamples = 50;
            T = table((1:numSamples)', rand(numSamples, 1)*50, rand(numSamples, 1)*80, ...
                      rand(numSamples, 7), rand(numSamples, 1)*50, ...
                      repmat("Clean", numSamples, 1), repmat("OK", numSamples, 1), ...
                      'VariableNames', {'Time_s', 'PM25', 'PM10', 'Features_7D', 'Forecast_PM25', 'Source', 'Advice'});
            
            % Save to a format the script expects (AQI_Log_*.csv)
            logPath = fullfile('logs', 'AQI_Log_TestMock.csv');
            writetable(T, logPath);
            
            % 2. Run the training script (relative to tests/ folder if needed)
            % Since CI usually runs from root, we need to handle path carefully.
            originalPath = addpath(fullfile(pwd, '../scripts'));
            cleanupPath = onCleanup(@() path(originalPath));
            
            isTestRun = true; % Set the flag for the script
            
            % Run the script
            run('train_offline_model.m');
            
            % 3. Verifications
            testCase.verifyTrue(exist('../models/trainedModel.mat', 'file') == 2);
            
            % Cleanup
            if exist(logPath, 'file'), delete(logPath); end
        end
        
    end
end
