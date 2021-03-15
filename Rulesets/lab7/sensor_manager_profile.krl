ruleset sensor_manager_profile {
	meta {
		name "Manage Sensor"
		author "Nate Teahan"

		use module twilio
			with
				accountSID = meta:rulesetConfig{"accountSID"}
				authToken = meta:rulesetConfig{"authToken"}

		shares notification_to
	}

	global {
		notification_from = meta:rulesetConfig{"notification_from"}

		notification_to = function() {
			ent:notification_to.defaultsTo(meta:rulesetConfig{"default_notification_to"})
		}
	}

	rule set_notification_to {
		select when sensor_manager_profile updated
		always {
			ent:notification_to := event:attrs{"notification_to"}
		}
	}

	rule send_sms {
		select when sensor_manager_profile send_sms

		twilio:sendSMS(notification_from,
                       notification_to(),
                       event:attrs{"msg"})
	}
}
