data:extend
{
	{
		type = "string-setting",
		name = "modtrainspeedsigns-speed-control",
		order = "001",
		setting_type = "startup",
		default_value = "set_speed",
		allowed_values =  {"set_speed", "throttle_fuel"}
	},
	{
		type = "double-setting",
		name = "modtrainspeedsigns-speed-limit",
		order = "002",
		setting_type = "runtime-global",
		default_value = 0,
		minimum_value = 0.00,
		maximum_value = 1000.0
	},
	{
		type = "double-setting",
		name = "modtrainspeedsigns-breaking-factor",
		order = "101",
		setting_type = "runtime-global",
		default_value = 12.5,
		minimum_value = 1.00,
		maximum_value = 25.0
	},
	{
		type = "double-setting",
		name = "modtrainspeedsigns-breaking-smoke",
		order = "102",
		setting_type = "runtime-global",
		default_value = 0.025,
		minimum_value = 0.00,
		maximum_value = 1.00
	},
	{
		type = "double-setting",
		name = "modtrainspeedsigns-throttle-range",
		order = "103",
		setting_type = "runtime-global",
		default_value = 0.125,
		minimum_value = 0.01,
		maximum_value = 1.00
	}
}