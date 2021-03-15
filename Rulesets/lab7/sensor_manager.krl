ruleset sensor_manager {
	meta {
		name "Manage Sensor"
		author "Nate Teahan"

		use module io.picolabs.subscription alias subscription

		shares collection_sensors, temperatures, get_profiles, get_subscribers
	}

	global {
		rulesets = {
			"io.picolabs.wovyn.emitter": {
				"url": "https://raw.githubusercontent.com/windley/temperature-network/main/io.picolabs.wovyn.emitter.krl"
			},
			"sensor_profile": {
                "url": "file:///Users/NatetheWizard/Documents/School/Fifth%20Year/Winter/462/lab7/sensor_profile.krl"
			},
			"wovyn_base": {
				"url": "file:///Users/NatetheWizard/Documents/School/Fifth%20Year/Winter/462/lab7/wovyn_base.krl"
			},
			"temperature_store": {
				"url": "file:///Users/NatetheWizard/Documents/School/Fifth%20Year/Winter/462/lab7/temperature_store.krl"
			}
		}

		defaults = {
			"location": "Orem, UT",
			"threshold": 77,
			"notification_to": "+18016738779"
		}

		collection_sensors = function() {
			ent:sensors.defaultsTo({})
		}

		get_subscribers = function() {
			subscription:established("Tx_role", "sensor").map(function(v) {
				v.get(["Tx"])
			})
		}

		temperatures = function() {
			get_subscribers().map(function(s) {
				{}.put(s, ctx:query(s, "temperature_store", "temperatures").defaultsTo([]).reverse().head())
			})
		}

		get_profiles = function() {
			get_subscribers().map(function(s) {
				{}.put(s, ctx:query(s, "sensor_profile", "profile").defaultsTo({}))
			})
		}
	}

	rule add_sensor {
		select when sensor new_sensor
		pre {
			name = event:attrs{"name"}
			duplicate = ent:sensors && ent:sensors >< name
		}

		if duplicate then
			send_directive("error", {"error": "cannot create duplicate child"})

		notfired {
			raise wrangler event "new_child_request" attributes {
				"name": name
			}
		}
	}

	rule sensor_added {
		select when wrangler new_child_created
		foreach rulesets setting(rule)

		pre {
			name = event:attrs{"name"}
			eci = event:attrs{"eci"}
		}

		if name && eci then 
			event:send({
				"eci": eci,
				"domain": "wrangler",
				"type": "install_ruleset_request",
				"attrs": {
					"url": rule{"url"},
					"config": rule{"config"},
				}
			})

		fired {
			ent:sensors := ent:sensors.defaultsTo({}).put(name, eci) on final
			raise sensor event "sensor_added" attributes {
				"name": name
			} on final
		}
	}

	rule configure_sensor {
		select when sensor sensor_added where event:attrs{"name"} && ent:sensors{event:attrs{"name"}}
		pre {
			name = event:attrs{"name"}
			eci = ent:sensors{name}
		}

		event:send({
			"eci": eci,
			"domain": "sensor",
			"type": "profile_updated",
			"attrs": {
				"name": name,
				"location": defaults{"location"},
				"temperature_threshold": defaults{"threshold"},
				"notification_to": defaults{"notification_to"}
			}
		})
	}

	rule create_subscription {
		select when sensor sensor_added where event:attrs{"name"} && ent:sensors{event:attrs{"name"}}
		pre {
			name = event:attrs{"name"}
			eci = ent:sensors{name}
		}

		always {
			raise wrangler event "subscription" attributes {
				"name": name,
				"wellKnown_Tx": eci,
				"channel_type": "sensor_management",
				"Rx_role": "sensor_manager",
				"Tx_role": "sensor"
			}
		}
	}

	rule introduce_sensor {
		select when sensor introduce

		pre {
			name = event:attrs{"name"}
			eci = event:attrs{"eci"}
		}

		always {
			raise wrangler event "subscription" attributes {
				"name": name,
				"wellKnown_Tx": eci,
				"channel_type": "sensor_management",
				"Rx_role": "sensor_manager",
				"Tx_role": "sensor"
			}
		}
	}

	rule delete_collection_sensors {
		select when sensor delete__collection_sensors
		foreach ent:sensors setting(eci, name)

		always {
			raise wrangler event "child_deletion_request" attributes {
				"eci": eci
			}

			clear ent:sensors{name}
		}
	}

	rule delete_sensor {
		select when sensor unneeded_sensor where event:attrs{"name"} && ent:sensors{event:attrs{"name"}}
		pre {
			name = event:attrs{"name"}
			eci = ent:sensors{name}
		}

		always {
			raise wrangler event "child_deletion_request" attributes {
				"eci": eci
			}

			clear ent:sensors{name}
		}
	}
}