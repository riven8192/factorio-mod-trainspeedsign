function math_sign(x)
   if x < 0 then
     return -1
   elseif x > 0 then
     return 1
   else
     return 0
   end
end

function math_pow2(x)
	return x * x
end


function findTrains()
	global.modtrainspeedsigns.trainId2train = {}
	for _idx1_, surface in pairs(game.surfaces) do
		for _idx2_, train in pairs(surface.get_trains()) do
			global.modtrainspeedsigns.trainId2train[train.id] = train;
		end
	end
end


function getTrainSpeed(train)
	return train.speed * 60.0 * 3.6;
end

function setTrainSpeed(train, speed)
	train.speed = speed / 60.0 / 3.6;
end




function findSpeedSignalLimit(railSignal)
	local green = railSignal.get_circuit_network(defines.wire_type.green);
	if green then
		return green.get_signal({type="virtual", name="signal-V"});
	end
	
	local red = railSignal.get_circuit_network(defines.wire_type.red);
	if red then
		return red.get_signal({type="virtual", name="signal-V"});
	end
	
	return 0
end



function findSpeedSignalLimitForTrain(train)
	local closestSignal = 0;
	local minDistance = 1000;
	
	for direction, locomotives in pairs(train.locomotives) do
		for idx, locomotive in ipairs(locomotives) do
	
			local railSignals = locomotive.surface.find_entities_filtered({
				area={
					{locomotive.position.x-2, locomotive.position.y-2},
					{locomotive.position.x+2, locomotive.position.y+2}
				},
				type="rail-signal"
			});
			
			for _idx2_, railSignal in ipairs(railSignals) do
				local xdiff = locomotive.position.x - railSignal.position.x;
				local ydiff = locomotive.position.y - railSignal.position.y;
				local distance = math.sqrt(xdiff*xdiff + ydiff*ydiff);
				if distance < minDistance then
					closestSignal = findSpeedSignalLimit(railSignal);
				end
			end
		end
	end
	
	return closestSignal
end



function ensure_mod_context() 
	if not global.modtrainspeedsigns then
		global.modtrainspeedsigns = {}
	 	global.modtrainspeedsigns.trainId2train = {}
	 	global.modtrainspeedsigns.trainId2maxspeed = {}
	 	global.modtrainspeedsigns.railsignalId2railsignal = {}
	 	global.modtrainspeedsigns.railsignalId2maxspeed = {}
	end
end




function respectTrainMaxSpeed(train)
	if not global.modtrainspeedsigns.trainId2maxspeed[train.id] then
		return
	end
	
	local maxSpeed = global.modtrainspeedsigns.trainId2maxspeed[train.id];
	maxSpeed = math.max(2, maxSpeed);
	
	local currSpeed = getTrainSpeed(train);
	if math.abs(currSpeed) > maxSpeed then
		local targetSpeed = math_sign(currSpeed) * maxSpeed;
		setTrainSpeed(train, currSpeed - math_sign(currSpeed) * 1.0);
	end
end



script.on_event({defines.events.on_tick},
	function (e)
		ensure_mod_context();
		
		if (e.tick % 120 == 0) then
			findTrains();
		end
		
		if (e.tick % 5 == 0) then			
			for trainId, train in pairs(global.modtrainspeedsigns.trainId2train) do
				if train.valid then
					local closestSignal = findSpeedSignalLimitForTrain(train);
					
					if closestSignal < 0 or closestSignal > 300 then
						global.modtrainspeedsigns.trainId2maxspeed[trainId] = nil;
					elseif closestSignal == 0 then
						-- do nothing
					elseif closestSignal > 0 then
						global.modtrainspeedsigns.trainId2maxspeed[trainId] = closestSignal;
					end
				end
			end
		end
		
		if (e.tick % 1 == 0) then
			for trainId, train in pairs(global.modtrainspeedsigns.trainId2train) do
				if train.valid then
					respectTrainMaxSpeed(train);
				end
			end
		end
	end
)
