ruleset sensor_manager {
	meta {
		name "Manage Sensor"
		author "Nate Teahan"

		use module io.picolabs.subscription alias subscription

		shares collection_sensors, temperatures, get_profiles, get_subscribers, get_scatter_reports, sensors
	}

	global {
		rulesets = {
			"io.picolabs.wovyn.emitter": {
				"url": "https://raw.githubusercontent.com/windley/temperature-network/main/io.picolabs.wovyn.emitter.krl"
			},
			"sensor_profile": {
                "url": "file:///Users/NatetheWizard/Documents/School/Fifth%20Year/Winter/462/rulesets/lab8/sensor_profile.krl"
			},
            "temperature_store": {
				"url": "file:///Users/NatetheWizard/Documents/School/Fifth%20Year/Winter/462/rulesets/lab8/temperature_store.krl"
			},
			"wovyn_base": {
				"url": "file:///Users/NatetheWizard/Documents/School/Fifth%20Year/Winter/462/rulesets/lab8/wovyn_base.krl"
			},
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

        sensors = function() {
            subscription:established("Tx_role", "sensor")
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
        
        get_scatter_reports = function() {
            // Return 5 most recent reports
            reversed = ent:final_reports.defaultsTo([]).reverse();
            len = reversed.length() > 4 => 4 | reversed.length();
            reversed.slice(len)
        }

        get_unfinished_reports = function() {
            ent:unfinished_reports
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

	rule begin_report {
		select when scatter begin_report
		pre {
			reportId = random:uuid()
		}
		always {
			ent:currentReports := ent:currentReports.defaultsTo({})
			// ent:currentReports := ent:currentReports.put([reportId], {"temperature_sensors": get_subscribers().length(), "temperatures": []})
			ent:currentReports{reportId} := {"temperature_sensors" : get_subscribers().length().klog("SUBSCRIBERS LENGTH:"), "temperatures" : [].klog("TEMPERATURES:")}
			raise scatter event "send_report_to_picos" attributes {"reportId": reportId.klog("REPORT ID:")}
		}
	}

	rule send_report_to_picos {
		select when scatter send_report_to_picos
		foreach sensors() setting(sensor)
		pre {
			send_attributes = {"Rx": sensor{"Rx"}.klog("SENSOR RX:"), "Tx": sensor{"Tx"}.klog("SENSOR TX:"), "reportId": event:attrs{"reportId"}}.klog("REPORT ID:")
		}

		event:send(
            { "eci": sensor{"Tx"}, "eid": "reportStart",
            "domain": "scatter", "type": "start_report",
            "attrs": send_attributes }
        )
	}

    rule report_received {
        select when scatter report_received
        pre {
            reportId = event:attrs{"reportId"}.klog("REPORT ID:")
            tx = event:attrs{"Tx"}.klog("TX:")
            temps = event:attrs{"temperatures"}.klog("TEMPERATURES:")
            report = ent:currentReports{reportId}.klog("REPORT:")
            new_reports = report{"temperatures"}.append({"tx": tx, "temperatures": temps}).klog("NEW REPORTS:")
        }
        if (report["temperature_sensors"].klog("REPORT INDEX") == new_reports.length().klog("REPORT LENGTH")) then noop()
        fired {
            // Move to finished list
            ent:currentReports{reportId} := {"temperature_sensors": report["temperature_sensors"], "temperatures": new_reports};
            ent:final_reports := ent:final_reports.defaultsTo([]).append({
                "temperature_sensors": ent:currentReports{[reportId, "temperature_sensors"]},
                "responding": ent:currentReports{[reportId, "temperatures"]}.length(),
                "temperatures": ent:currentReports{[reportId, "temperatures"]}
            })
        } else {
            // Add to list of respondants
            ent:currentReports{reportId} := {"temperature_sensors": report["temperature_sensors"], "temperatures": new_reports}
        }
    }
}
