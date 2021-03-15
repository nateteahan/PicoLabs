ruleset sensor_profile {
	meta {
		name "Sensor Profile"
		author "Nate Teahan"

		provides profile, temperature_threshold, notification_to
		shares profile, temperature_threshold, notification_to
	}

	global {
		profile = function() {
			{
				"name": ent:name.defaultsTo(""),
				"location": ent:location.defaultsTo(""),
				"temperature_threshold": temperature_threshold(),
				"notification_to": notification_to()
			}
		}

		notification_to = function() {
			ent:notification_to.defaultsTo("18016738779")
		}

		temperature_threshold = function() {
			ent:temperature_threshold.defaultsTo(100)
		}
	}

	rule updated {
		select when sensor profile_updated

		always {
			ent:name := event:attrs{"name"}
			ent:location := event:attrs{"location"}
			ent:temperature_threshold := event:attrs{"temperature_threshold"}
			ent:notification_to := event:attrs{"notification_to"}
		}
	}
}