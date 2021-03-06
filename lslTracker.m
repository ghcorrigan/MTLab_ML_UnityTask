% In MonkeyLogic a tracker is the object responsible with interfacing with
% the data collection hardware/software. It receives calls to acquire
% samples and holds the tracer pointer to display on screen. 

% In this case it holds the pointers to the LSL frame inlet to receive
% frame data, time differences between the clocks and properly timestamps
% everything in monkeylogic time. 


classdef lslTracker < mltracker
    properties
        Frame_Inlet  % LSL inlet for Unity Frame data
        Trial_Inlet
        Lib  % lsl_lib
    end
    properties (SetAccess = protected)
        Counter = 1  % position within the pre-allocated memory arrays

        % current frame data has 22 x sample data where each sample is: 
        %   1: Position X
        %   2: Position Y
        %   3: Position Z
        %   4: Rotation
        %   5: Joystick Position X
        %   6: Joystick Position Y
        %   7: Player State (Collider ID)        
        %   8: Gaze Position X
        %   9: Gaze Position Y
        %                                     
        %   10-14: Gaze Targets ID             
        %   15-19: Gaze Targets Number of rays 
        %                                     
        %   20: Trial State
        %   21: PhotoDiodeIntensity
        %   22: Unity LSL Time
        % To this we add: 
        %   23: Time Correction between the two LSL clocks
        %   24: Sample TimeStamp
        %   25: Local LSL TimeStamp
        %   26: MonkeyLogic Trial Time.
        Frame_Data = NaN(26, 120 * 100); % 120 sec @ 100Hz
        Trial_Data = struct()
    end
    
    methods
        function obj = lslTracker(frame_inlet, trial_inlet, MLConfig)
            obj = obj@mltracker(MLConfig,[],[],[]);
            obj.Frame_Inlet = frame_inlet;
            obj.Trial_Inlet = trial_inlet;
            obj.Signal = 'LSL';
        end
        
        function tracker_init(obj,~)
            %Clear data
            obj.Counter = 1;
        end
        function tracker_fini(~,~)
           
        end
        function acquire(obj, p)
            % Trial data acquisition
            if ~isempty(obj.Trial_Inlet)
                [sample, timestamp] = obj.Trial_Inlet.pull_sample(0);
                if ~isempty(sample)
                    obj.Trial_Data = obj.ProcessTrial(sample{1}, timestamp, p.trialtime());
                end
            end
            
            % Frame Data acquisition for tracker execution
            if ~isempty(obj.Frame_Inlet)
                % ~ .036 ms to acquire. 
                % stamps are on the remote (sender) clock time
                % To get proper time: 
                %   Local clock + time correction = remote clock;
                [sample, timestamp] = obj.Frame_Inlet.pull_sample(0);
                if ~isempty(sample)
                    temp_array = obj.ProcessSample(sample, timestamp, lsl_local_clock(obj.Lib), p.trialtime());
                    obj.Frame_Data(:, obj.Counter) = temp_array;
                    obj.Counter = obj.Counter + 1;

                    % make sure we have all the available samples
                    has_buffer = true;
                    while has_buffer
                        [sample, timestamp] = obj.Frame_Inlet.pull_sample(0);
                        if isempty(sample)
                            has_buffer = false;
                            continue
                        end
                        temp_array = obj.ProcessSample(sample, timestamp, lsl_local_clock(obj.Lib), p.trialtime());
                        obj.Frame_Data(:, obj.Counter) = temp_array;
                    obj.Counter = obj.Counter + 1;
                    end
                    obj.Success = true;
                else
                    obj.Success = false;
                end
            end
        end
        
        function temp_array = ProcessSample(obj, sample, timestamp, lsl_clock, trialtime)
            Time_Corr = obj.Frame_Inlet.time_correction();
            temp_array = [sample'; % is a (1,22) then -> (22,1)
                Time_Corr;
                timestamp;
                lsl_clock;
                trialtime];
        end
        
        function temp_struct = ProcessTrial(obj, sample, timestamp, trialtime)
            Time_Corr = obj.Trial_Inlet.time_correction();
            temp_struct = jsondecode(sample);
            temp_struct.Time_Corr = Time_Corr;
            temp_struct.ML_Sample_Time = timestamp;
            temp_struct.ML_Local_Time = lsl_local_clock(obj.Lib);
            temp_struct.ML_Trial_Time = trialtime;
        end
        
        function sample = GetLastSample(obj)
            if obj.Counter > 1
                sample = obj.Frame_Data(:,obj.Counter-1);
            else
                sample = [];
            end
        end
        
        function sample = GetLastState(obj)
            if obj.Counter > 1
                sample = obj.Frame_Data(7, obj.Counter-1);
            else
                sample = [];
            end
        end
        
        function sample = GetOutcome(obj)
            if isfield(obj.Trial_Data, 'Outcome')
                sample = obj.Trial_Data.Outcome;
            else
                sample = [];  % defaults to aborted when no data. 
            end
        end
        
        function [frame_data, trial_data, xml_data] = GetTrialData(obj, p)
            % get remaining frame samples in lsl stream
%             obj.acquire(p)
            
            % remove nan columns
            frame_data = obj.Frame_Data(:, sum(isnan(obj.Frame_Data),1)==0);
            trial_data = obj.Trial_Data;
            xml_data = obj.Trial_Inlet.info().as_xml();
        end
    end
    
end
