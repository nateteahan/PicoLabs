ruleset wovyn_base {
	meta {
		name "Wovyn Base"
		author "Nate Teahan"

		use module io.picolabs.subscription alias subscription
		use module sensor_profile alias profile
        use module temperature_store alias store

		shares sensor_managers
	}

	global {
		sensor_managers = function() {
			subscription:established("Tx_role", "sensor_manager").map(function(v) {
				v.get(["Tx"])
			})
		}
	}

	rule process_heartbeat {
		select when wovyn heartbeat where event:attrs{"genericThing"}

		send_directive("temperatureF", event:attrs{"genericThing"}{["data", "temperature", 0, "temperatureF"]})
		fired {
			raise wovyn event "new_temperature_reading" attributes {
				"timestamp": time:now(),
				"temperature": event:attrs{"genericThing"}{["data", "temperature", 0, "temperatureF"]}
			}
		}
	}

	rule get_high_temps {
		select when wovyn new_temperature_reading where event:attrs{"temperature"} > profile:temperature_threshold()

		fired {
			raise wovyn event "threshold_violation" attributes event:attrs
		}
	}

	rule threshold_notification {
		select when wovyn threshold_violation
		foreach sensor_managers() setting (eci)

		event:send({
			"eci": eci,
			"domain": "sensor_manager",
			"type": "sub_sensor_threshold_violation",
			"attrs": event:attrs
		})
	}

    rule start_scatter_report {
        select when scatter start_report
        pre {
            temperatures = store:temperatures().klog("TEMP STORE TEMPERATURES:")
        }

        event:send(
            { "eci": event:attrs{"Rx"}, "eid": "reportDone",
            "domain": "scatter", "type": "report_received",
            "attrs": {"temperatures": temperatures, "Tx": event:attrs{"Tx"}, "reportId": event:attrs{"reportId"}} }
        )
    }

	rule accept_sensor_manager_sub {
		select when wrangler inbound_pending_subscription_added where event:attrs{"Rx_role"} == "sensor"

		fired {
			raise wrangler event "pending_subscription_approval" attributes event:attrs
		}
	}
}