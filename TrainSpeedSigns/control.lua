require 'rivenmods-common-v0-1-0'



function findNearbySpeedSignals(locomotive)
	return locomotive.surface.find_entities_filtered({
		area={
			{locomotive.position.x-2, locomotive.position.y-2},
			{locomotive.position.x+2, locomotive.position.y+2}
		},
		type="rail-signal"
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
	
	if speedControl == 1337 then
		speedControl = 'throttle_fuel'
	else
		speedControl = 'set_speed'
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





function respectTrainMaxSpeed(train)
	local trainSpeed = getTrainSpeed(train);
	if global.trainId2speedcontrol[train.id] and global.trainId2speedcontrol[train.id] == 'throttle_fuel' then
		if trainSpeed == 0.0 then
			if global.trainId2prevspeed[train.id] and global.trainId2prevspeed[train.id] ~= 0.0 then
				restoreLocomotiveFuelConfig(train);
			end
		else
			if global.trainId2prevspeed[train.id] and global.trainId2prevspeed[train.id] == 0.0 then
				backupLocomotiveFuelConfig(train);
				wipeLocomotiveFuelConfig(train);
			end
		end
	end
	global.trainId2prevspeed[train.id] = trainSpeed;
	
	
	
	if not global.trainId2maxspeed[train.id] then
		if global.trainId2breakingspeed[train.id] then
			global.trainId2breakingspeed[train.id] = nil;
		end
		return
	end
	
	if global.trainId2maxspeed[train.id] and global.trainId2speedcontrol[train.id] then
		if global.trainId2speedcontrol[train.id] == 'set_speed' then
			respectTrainMaxSpeed__withTrainSetSpeed(train)
		elseif global.trainId2speedcontrol[train.id] == 'throttle_fuel' then
			respectTrainMaxSpeed__withFuelToggle(train)
		end
	end
end



function respectTrainMaxSpeed__withTrainSetSpeed(train)
	-- we are breaking, but the game keeps accelerating. if we remember that we were
	-- breaking in the previous game-tick, we copy the previous speed, if we see that
	-- we accelerated. this way we get reliable breaking, regardless of what the game
	-- or other mods, are going behind the scenes.
	local currSpeed = getTrainSpeed(train);
	if global.trainId2breakingspeed[train.id] then
		if math.abs(currSpeed) > math.abs(global.trainId2breakingspeed[train.id]) then
			currSpeed = global.trainId2breakingspeed[train.id]
		end
	end
	
	local maxSpeed = math.max(2, global.trainId2maxspeed[train.id]);
	
	local targetSpeed = math_sign(currSpeed) * maxSpeed;
	local speedDiff = currSpeed - targetSpeed;
	
	if math.abs(currSpeed) > maxSpeed then
		local breakingFactor = global.settings.breakingFactor;
		local multiples = math.abs(speedDiff) / breakingFactor;
		local intensity = math.log(10 + math.min(5, multiples));
		
		if math.abs(speedDiff) > 5.0 then
			addNiceSmokePuffsWhenBreaking(train, intensity);
		end
		
		local deceleration = math_sign(currSpeed) * (breakingFactor / GAME_FRAMERATE) * intensity;
		local desiredSpeed = currSpeed - deceleration;
		setTrainSpeed(train, desiredSpeed);
		global.trainId2breakingspeed[train.id] = desiredSpeed;
	else
		global.trainId2breakingspeed[train.id] = nil;
	end
end



function respectTrainMaxSpeed__withFuelToggle(train)
	local trainSpeed = math.abs(getTrainSpeed(train));
	local maxSpeed = math.max(1, global.trainId2maxspeed[train.id]);
	
	local heuristic = 0.025;
	local injectFuelAmount = 1*1000*1000;
	
	for direction, locomotives in pairs(train.locomotives) do
		for idx, locomotive in ipairs(locomotives) do
			if locomotive.burner.remaining_burning_fuel ~= 0.0 then
				-- we can only consume the fuel from the 'backup'
				--local burntFuel = injectFuelAmount - locomotive.burner.remaining_burning_fuel;
				--global.locomotiveId2fuelbackup[locomotive.unit_number].remaining_burning_fuel = math.max(0.0, global.locomotiveId2fuelbackup[locomotive.unit_number].remaining_burning_fuel - burntFuel)
				--mod_log('remainingFuel=' .. global.locomotiveId2fuelbackup[locomotive.unit_number].remaining_burning_fuel);
			end
				
			if trainSpeed > maxSpeed + heuristic then
				locomotive.get_fuel_inventory().clear();
				locomotive.burner.currently_burning = nil;
				locomotive.burner.remaining_burning_fuel = 0.0;
			elseif trainSpeed < maxSpeed - heuristic and trainSpeed ~= 0.0 then
				locomotive.burner.currently_burning = global.locomotiveId2fuelbackup[locomotive.unit_number].currently_burning;
				locomotive.burner.remaining_burning_fuel = injectFuelAmount;
			end
		end
	end
end

function wipeLocomotiveFuelConfig(train)
	mod_log('wipeLocomotiveFuelConfig for train ' .. train.id .. ' [' .. global.rndm() .. ']');
	
	for direction, locomotives in pairs(train.locomotives) do
		for idx, locomotive in ipairs(locomotives) do
			locomotive.get_fuel_inventory().clear();
			locomotive.burner.currently_burning = nil;
			locomotive.burner.remaining_burning_fuel = 0.0;
		end
	end
end

function backupLocomotiveFuelConfig(train)
	mod_log('backupLocomotiveFuelConfig for train ' .. train.id .. ' [' .. global.rndm() .. ']');
	
	for direction, locomotives in pairs(train.locomotives) do
		for idx, locomotive in ipairs(locomotives) do
			global.locomotiveId2fuelbackup[locomotive.unit_number] = {
				currently_burning = locomotive.burner.currently_burning,
				remaining_burning_fuel = locomotive.burner.remaining_burning_fuel,
				fuel_inventory_contents = locomotive.get_fuel_inventory().get_contents()
			}
		end
	end
end

function restoreLocomotiveFuelConfig(train)
	mod_log('restoreLocomotiveFuelConfig for train ' .. train.id .. ' [' .. global.rndm() .. ']');
	
	for direction, locomotives in pairs(train.locomotives) do
		for idx, locomotive in ipairs(locomotives) do
			if global.locomotiveId2fuelbackup[locomotive.unit_number] then
				local backup = global.locomotiveId2fuelbackup[locomotive.unit_number];
				
				locomotive.get_fuel_inventory().clear()
				for itemname, itemcount in pairs(backup.fuel_inventory_contents) do
					-- mod_log('restoreLocomotiveFuelConfig for locomotive ' .. locomotive.unit_number .. ' inv[' .. itemcount .. 'x ' .. itemname .. '] [' .. global.rndm() .. ']');
					locomotive.get_fuel_inventory().insert({name=itemname, count=itemcount})
				end
				
				-- mod_log('restoreLocomotiveFuelConfig for locomotive ' .. locomotive.unit_number .. ' burn[' .. backup.currently_burning.name .. ', ' .. backup.remaining_burning_fuel .. '] [' .. global.rndm() .. ']');
				
				
			
				locomotive.burner.currently_burning = backup.currently_burning
				locomotive.burner.remaining_burning_fuel = backup.remaining_burning_fuel
				mod_log('setRemainingFuel=' .. backup.remaining_burning_fuel);
				
				-- global.locomotiveId2fuelbackup[locomotive.unit_number] = nil
			end
		end
	end
end


function monitorTrain(train)
	local speedValue, speedControl = findSpeedSignalConfigForTrain(train);
	
	if speedValue < 0 or speedValue >= 1000 then
		if global.trainId2speedcontrol[train.id] and global.trainId2speedcontrol[train.id] == 'throttle_fuel' then
			restoreLocomotiveFuelConfig(train)
		end
	
		global.trainId2speedcontrol[train.id] = nil;
		global.trainId2maxspeed[train.id] = nil;
	elseif speedValue == 0 then
		-- do nothing
	elseif speedValue > 0 then
		if not global.trainId2speedcontrol[train.id] or global.trainId2speedcontrol[train.id] ~= speedControl then
			mod_log('changing speed-control for train #' .. train.id .. '  to ' .. speedControl)
			
			if global.trainId2speedcontrol[train.id] and global.trainId2speedcontrol[train.id] == 'throttle_fuel' then
				restoreLocomotiveFuelConfig(train)
			end
			
			if speedControl == 'throttle_fuel' then
				backupLocomotiveFuelConfig(train)
			end
		end
		
		if not global.trainId2maxspeed[train.id] or global.trainId2maxspeed[train.id] ~= speedValue then
			mod_log('changing speed-limit for train #' .. train.id .. ' to ' .. speedValue)
		end
	
		global.trainId2speedcontrol[train.id] = speedControl;
		global.trainId2maxspeed[train.id] = speedValue;
	end
end

function addNiceSmokePuffsWhenBreaking(train, intensity)
	local trainSpeed = math.abs(getTrainSpeed(train));
	for direction, locomotives in pairs(train.locomotives) do
		for idx, locomotive in ipairs(locomotives) do
			if global.rndm() / (intensity*intensity) < global.settings.breakingSmoke then
				locomotive.surface.create_trivial_smoke({name='fire-smoke', position=locomotive.position})
			end
		end
	end
end



function ensure_mod_context() 
	if not global.hasContext then
		global.hasContext = true;
		
	 	global.trainId2train = {}
	 	global.trainId2maxspeed = {}
	 	global.trainId2prevspeed = {}
	 	global.trainId2breakingspeed = {}
	 	global.trainId2speedcontrol = {}
	 	global.locomotiveId2fuelbackup = {}
	end
	
	if not global.rndm then
		global.rndm = game.create_random_generator()
		global.rndm.re_seed(1337);
	end
	
	if not global.trainId2prevspeed then
		global.trainId2prevspeed = {}
	end
	
	if not global.trainId2breakingspeed then
		global.trainId2breakingspeed = {}
	end
	
	if not global.trainId2speedcontrol then
		global.trainId2speedcontrol = {}
	end
	
	if not global.locomotiveId2fuelbackup then
		global.locomotiveId2fuelbackup = {}
	end
	
	if not global.settings then
		refresh_mod_settings()
	end
end



function refresh_mod_settings()
	mod_log('trainspeedsigns.refresh_mod_settings');
	global.settings = {}
	global.settings.breakingFactor = settings.global["modtrainspeedsigns-breaking-factor"].value;
	global.settings.breakingSmoke  = settings.global["modtrainspeedsigns-breaking-smoke"].value;
	
	mod_log('modtrainspeedsigns.breakingFactor: ' .. global.settings.breakingFactor);
end


 
script.on_event({defines.events.on_init},
	function (e) 
		refresh_mod_settings();
	end
)
script.on_event({defines.events.on_load},
	function (e) 
		refresh_mod_settings();
	end
)
script.on_event({defines.events.on_runtime_mod_setting_changed},
	function (e) 
		refresh_mod_settings();
	end
)

script.on_event({defines.events.on_tick},
	function (e)
		ensure_mod_context();
		
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
