classdef AirQualitySystemTest < matlab.unittest.TestCase
    % Unit tests for the AirQualitySystem class
    
    properties
        Sys % System object
    end
    
    methods(TestMethodSetup)
        function setup(testCase)
            % Add src to path
            addpath(fullfile(fileparts(mfilename('fullpath')), '../src'));
            
            % Initialize with mock parameters
            testCase.Sys = AirQualitySystem('127.0.0.1', 'pi', 'pass', '/dev/ttyUSB0', 9600, true);
        end
    end
    
    methods(Test)
        
        function testFeatureExtraction(testCase)
            % 1. Verify Z-score normalization and 7D feature array extraction
            testCase.Sys.PM25Data = [10, 12, 15, 14, 13, 16];
            testCase.Sys.PM10Data = [20, 22, 25, 24, 23, 26];
            
            % Mock scaling parameters
            testCase.Sys.FeatureMu = zeros(1, 7);
            testCase.Sys.FeatureSigma = ones(1, 7);
            
            features = testCase.Sys.extractFeatures(6);
            
            % Check dimensions
            testCase.verifyEqual(length(features), 7, 'Feature vector must be 7D');
            
            % Check specific feature (ROC)
            roc = features(2);
            testCase.verifyEqual(roc, 16 - 13, 'ROC feature calculation incorrect');
        end
        
        function testForecastingStability(testCase)
            % 2. Test recursive Holt-Winters state updates and dampening
            % Simulate a spike followed by stabilization
            testCase.Sys.PM25Data = [10, 11, 100, 100, 100];
            
            % Run forecast through iterations
            for k = 1:5
                pred = testCase.Sys.forecastAQI(k);
            end
            
            initialTrend = testCase.Sys.HW_Trend;
            
            % Simulate many more stable steps to see if trend dampens
            for k = 6:100
                testCase.Sys.PM25Data(k) = 100;
                testCase.Sys.forecastAQI(k);
            end
            
            finalTrend = testCase.Sys.HW_Trend;
            
            % Verify that trend has dampened significantly (closer to 0)
            testCase.verifyTrue(abs(finalTrend) < abs(initialTrend), 'Trend should dampen over time');
            testCase.verifyTrue(abs(finalTrend) < 1, 'Dampening should bring trend close to zero');
        end
        
        function testDynamicThresholding(testCase)
            % 3. Validate dynamic thresholding and baseline environmental scaling
            
            % Case A: Clean environment
            testCase.Sys.PM25Data = ones(1, 100) * 10; % Baseline 10
            testCase.Sys.PM10Data = ones(1, 100) * 20;
            [~, advice] = testCase.Sys.analyze(100, zeros(1,7), 10);
            testCase.verifyTrue(contains(advice, 'clean') || contains(advice, 'acceptable'), 'Should report clean air');
            
            % Case B: Sudden spike relative to baseline
            testCase.Sys.PM25Data(101) = 60;
            testCase.Sys.PM10Data(101) = 80;
            [source, advice] = testCase.Sys.analyze(101, [0.75, 50, 0, 0, 0, 0, 0], 60);
            
            testCase.verifyTrue(contains(source, 'Dust') || contains(source, 'pollution'), 'Should detect pollution');
            testCase.verifyTrue(contains(advice, 'Unhealthy') || contains(advice, 'DANGER'), 'Should give warning');
        end
        
    end
end
