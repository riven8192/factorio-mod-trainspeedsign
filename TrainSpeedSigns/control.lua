require 'rivenmods-common-v0-1-1'

SPEEDCONTROL_THROTTLEFUEL='throttle_fuel'
SPEEDCONTROL_SETSPEED='set_speed'





function findNearbySpeedSignals(locomotive)
	return locomotive.surface.find_entities_filtered({
		area={
			{locomotive.position.x-2, locomotive.position.y-2},
			{locomotive.position.x+2, locomotive.position.y+2}
		},
		type={"rail-signal","rail-chain-signal"}
	});
end



function findSpeedSignalConfig(railSignal)
	local green = railSignal.get_circuit_network(defines.wire_type.green);
	local red   = railSignal.get_circuit_network(defines.wire_type.red);
	
	local speedValue = 0
	if green and speedValue == 0 then
		speedValue = green.get_signal({type="virtual", name="signal-V"});
	end
	if red and speedValue == 0 then
		speedValue = red.get_signal({type="virtual", name="signal-V"});
	end
	
	local speedControl = 0
	if green and speedControl == 0 then
		speedControl = green.get_signal({type="virtual", name="signal-R"});
	end
	if red and speedControl == 0 then
		speedControl = red.get_signal({type="virtual", name="signal-R"});
	end
	
	if speedControl ~= 7331 and (global.settings.defSpeedControl == SPEEDCONTROL_THROTTLEFUEL or speedControl == 1337) then
		speedControl = SPEEDCONTROL_THROTTLEFUEL
	else
		speedControl = SPEEDCONTROL_SETSPEED
	end
	
	return speedValue, speedControl
end



function findSpeedSignalConfigForTrain(train)
	local speedValue = 0;
	local speedControl = 0;
	
	local minDistance = 1000;
	
	for direction, locomotives in pairs(train.locomotives) do
		for idx, locomotive in ipairs(locomotives) do
			local railSignals = findNearbySpeedSignals(locomotive);
			
			for _idx2_, railSignal in ipairs(railSignals) do
				local xdiff = locomotive.position.x - railSignal.position.x;
				local ydiff = locomotive.position.y - railSignal.position.y;
				local distance = math.sqrt(xdiff*xdiff + ydiff*ydiff);
				if distance < minDistance then
					speedValue, speedControl = findSpeedSignalConfig(railSignal);
				end
			end
		end
	end
	
	return speedValue, speedControl
end




function applyBrakesForTrain(train, currSpeed, maxSpeed)
	local targetSpeed = math_sign(currSpeed) * maxSpeed;
	local speedDiff = currSpeed - targetSpeed;
	local brakingFactor = global.settings.brakingFactor;
	local multiples = math.abs(speedDiff) / brakingFactor;
	local intensity = math.log(10 + math.min(5, multiples));
	
	if math.abs(speedDiff) > 5.0 then
		addNiceSmokePuffsWhenBraking(train, intensity);
	end
	
	local deceleration = math_sign(currSpeed) * (brakingFactor / GAME_FRAMERATE) * intensity;
	local desiredSpeed = currSpeed - deceleration;
	setTrainSpeed(train, desiredSpeed);
	return desiredSpeed;
end


function respectTrainMaxSpeed(train)
	if not global.trainId2maxspeed[train.id] then
		if global.trainId2brakingspeed[train.id] then
			global.trainId2brakingspeed[train.id] = nil;
		end
		return
	end
	
	if global.trainId2maxspeed[train.id] and global.trainId2speedcontrol[train.id] then
		if global.trainId2speedcontrol[train.id] == SPEEDCONTROL_SETSPEED then
			respectTrainMaxSpeed__withTrainSetSpeed(train)
		elseif global.trainId2speedcontrol[train.id] == SPEEDCONTROL_THROTTLEFUEL then
			respectTrainMaxSpeed__withFuelToggle(train)
		end
	end
end



function respectTrainMaxSpeed__withTrainSetSpeed(train)
	-- we are braking, but the game keeps accelerating. if we remember that we were
	-- braking in the previous game-tick, we copy the previous speed, if we see that
	-- we accelerated. this way we get reliable braking, regardless of what the game
	-- or other mods, are going behind the scenes.
	local currSpeed = getTrainSpeed(train);
	if global.trainId2brakingspeed[train.id] then
		if math.abs(currSpeed) > math.abs(global.trainId2brakingspeed[train.id]) then
			currSpeed = global.trainId2brakingspeed[train.id]
		end
	end
	
	local maxSpeed = math.max(2, global.trainId2maxspeed[train.id]);
	
	local adjustment = 1; -- this makes it more accurate (as accurate as fuel-toggle)
	maxSpeed = maxSpeed - adjustment;
	
	if math.abs(currSpeed) > maxSpeed then
		local desiredSpeed = applyBrakesForTrain(train, currSpeed, maxSpeed);
		global.trainId2brakingspeed[train.id] = desiredSpeed;
	else
		global.trainId2brakingspeed[train.id] = nil;
	end
end



function respectTrainMaxSpeed__withFuelToggle(train)
	local currSpeed = getTrainSpeed(train);
	if currSpeed == 0.0 then
		return
	end
	
	local trainSpeed = math.abs(currSpeed);
	local maxSpeed = math.max(1, global.trainId2maxspeed[train.id]);
	
	
	
	local heuristic = global.settings.throttleRange;
	
	for direction, locomotives in pairs(train.locomotives) do
		for idx, locomotive in ipairs(locomotives) do
			if trainSpeed > maxSpeed + heuristic then
				if trainSpeed > maxSpeed + 2.5 then
					local desiredSpeed = applyBrakesForTrain(train, currSpeed, maxSpeed);
				end
			
				if locomotive.burner.remaining_burning_fuel ~= 0.0 then
					backupLocomotiveFuelConfig(locomotive)
					wipeLocomotiveFuelConfig(locomotive)
				end
			elseif trainSpeed < maxSpeed - heuristic then
				if locomotive.burner.remaining_burning_fuel == 0.0 then
					restoreLocomotiveFuelConfig(locomotive)
				end
			end
		end
	end
end

function restoreTrainFuelConfig(train)
	--mod_log('restoreTrainFuelConfig for train ' .. train.id .. ' [' .. global.rndm() .. ']');
	for direction, locomotives in pairs(train.locomotives) do
		for idx, locomotive in ipairs(locomotives) do
			restoreLocomotiveFuelConfig(locomotive);
		end
	end
end
		

function wipeLocomotiveFuelConfig(locomotive)
	--mod_log('wipeLocomotiveFuelConfig for locomotive ' .. locomotive.unit_number .. ' [' .. global.rndm() .. ']');
	
	locomotive.get_fuel_inventory().clear();
	locomotive.burner.currently_burning = nil;
	locomotive.burner.remaining_burning_fuel = 0.0;
end

function backupLocomotiveFuelConfig(locomotive)
	--mod_log('backupLocomotiveFuelConfig for locomotive ' .. locomotive.unit_number .. ' [' .. global.rndm() .. ']');
	
	if locomotive.burner.remaining_burning_fuel == 0.0 then
		--mod_log('backupLocomotiveFuelConfig WARNING: no fuel!! [' .. global.rndm() .. ']');
	end
	
	global.locomotiveId2fuelbackup[locomotive.unit_number] = {
		currently_burning = locomotive.burner.currently_burning,
		remaining_burning_fuel = locomotive.burner.remaining_burning_fuel,
		fuel_inventory_contents = locomotive.get_fuel_inventory().get_contents()
	}
end

function restoreLocomotiveFuelConfig(locomotive)
	--mod_log('restoreLocomotiveFuelConfig for locomotive ' .. locomotive.unit_number .. ' [' .. global.rndm() .. ']');
	
	if not global.locomotiveId2fuelbackup[locomotive.unit_number] then
		return
	end
	
	local backup = global.locomotiveId2fuelbackup[locomotive.unit_number];
	
	locomotive.get_fuel_inventory().clear()
	for itemname, itemcount in pairs(backup.fuel_inventory_contents) do
		locomotive.get_fuel_inventory().insert({name=itemname, count=itemcount})
	end

	locomotive.burner.currently_burning = backup.currently_burning
	locomotive.burner.remaining_burning_fuel = backup.remaining_burning_fuel
end


function monitorTrain(train)
	local speedValue, speedControl = findSpeedSignalConfigForTrain(train);
	if speedValue == 0.0 and global.settings.speedLimit ~= 0.0 then
		speedValue = global.settings.speedLimit
		speedControl = global.settings.defSpeedControl
	end
	
	if speedValue ~= 0.0 then
		configureTrainSpeedLimit(train, speedValue, speedControl);
	end
end

function configureTrainSpeedLimit(train, speedValue, speedControl)
	local isThrottlingFuel = map_value_equals(global.trainId2speedcontrol, train.id, SPEEDCONTROL_THROTTLEFUEL);

	if speedControl ~= SPEEDCONTROL_THROTTLEFUEL and isThrottlingFuel then
		mod_log('configureTrainSpeedLimit for train ' .. train.id .. ' [' .. global.rndm() .. ']');
		restoreTrainFuelConfig(train)
	end
	
	if speedValue < 0 or speedValue >= 1000 then
		if global.trainId2speedcontrol[train.id] then
			mod_log('removing speed-control for train #' .. train.id)
			global.trainId2speedcontrol[train.id] = nil;
			global.trainId2maxspeed[train.id] = nil;
			
			if isThrottlingFuel then
				restoreTrainFuelConfig(train)
			end
		end
	else
		if not map_value_equals(global.trainId2speedcontrol, train.id, speedControl) then
			mod_log('changing speed-control for train #' .. train.id .. '  to ' .. speedControl)
		end
		
		if not map_value_equals(global.trainId2maxspeed, train.id, speedValue) then
			mod_log('changing speed-limit for train #' .. train.id .. ' to ' .. speedValue)
		end
	
		global.trainId2speedcontrol[train.id] = speedControl;
		global.trainId2maxspeed[train.id] = speedValue;
	end
end



function addNiceSmokePuffsWhenBraking(train, intensity)
	for direction, locomotives in pairs(train.locomotives) do
		for idx, locomotive in ipairs(locomotives) do
			if global.rndm() / (intensity*intensity) < global.settings.brakingSmoke then
				locomotive.surface.create_trivial_smoke({name='fire-smoke', position=locomotive.position})
			end
		end
	end
end



function ensure_mod_context()
	ensure_global_rndm()
	ensure_global_mapping('trainId2train')	
	ensure_global_mapping('trainId2maxspeed')
	ensure_global_mapping('trainId2brakingspeed')
	ensure_global_mapping('trainId2speedcontrol')
	ensure_global_mapping('locomotiveId2fuelbackup')
end



function refresh_mod_settings()
	global.settings = {
		-- fixed
		defSpeedControl = settings.startup["modtrainspeedsigns-speed-control"].value,
		
		-- variable
		brakingFactor  = settings.global["modtrainspeedsigns-breaking-factor"].value,
		brakingSmoke   = settings.global["modtrainspeedsigns-breaking-smoke"].value,
		throttleRange  = settings.global["modtrainspeedsigns-throttle-range"].value,
		speedLimit     = settings.global["modtrainspeedsigns-speed-limit"].value,
	}
end

script.on_event({defines.events.on_tick},
	function (e)
		ensure_mod_context();
		refresh_mod_settings();
		
		if (e.tick % 120 == 0) then
			findTrains();
		end
		
		for trainId, train in pairs(global.trainId2train) do
			if train.valid then
				if (e.tick % 5 == trainId % 5) then
					monitorTrain(train);
				end
			end
		end
		
		if (e.tick % 1 == 0) then
			for trainId, train in pairs(global.trainId2train) do
				if train.valid then
					respectTrainMaxSpeed(train);
				end
			end
		end
	end
)
